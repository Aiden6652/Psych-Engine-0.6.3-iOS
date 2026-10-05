package hxcodec;

#if (VIDEOS_ALLOWED && (ios || android))
import flixel.FlxG;
import flixel.FlxSubState;
import flixel.util.FlxTimer;
import hxvlc.flixel.FlxVideoSprite;
import sys.FileSystem;
import sys.io.File;

/**
 * [PE-iOS] hxCodec 兼容层 —— 用 hxvlc 实现真正的视频播放。
 *
 * ⚠ hxvlc 版本要求：**1.9.3**
 *   1.7/1.8.x 没有 GPU 渲染路径（视频帧出不来），
 *   1.9.4+ 又用了 Haxe 4.3 的 `?.` 语法（本仓库 Haxe 4.2.4 编不过）。
 *
 * 🩺 目前已排除的可能（实测日志证明）：
 *   - load 成功、帧 1920x1080 正常、缩放 1280x720 正常；
 *   - scrollFactor=0,0、相机已指定、xy=0,0 —— 位置/滚动都不是原因。
 *
 * 本版新增：直接探测 hxvlc 内部那个「原始 Bitmap」（真正输出视频帧的对象），
 *   记录它的 visible / alpha / x / y / width / height / parent 是否存在。
 *   加了一个 1 秒后的定时快照（不依赖 update()，确保能拿到数据）。
 */
class VideoHandler extends FlxSubState
{
	/** 播放结束（或被跳过）后的回调，老模组靠它继续剧情 */
	public var finishCallback:Void->Void = null;
	/** 兼容别名 */
	public var onVideoEnd:Void->Void = null;
	/** 当前解析后的视频绝对路径 */
	public var videoPath:String = null;
	/** 是否允许点击/按键跳过 */
	public var canSkip:Bool = true;
	/** 是否循环播放 */
	public var loop:Bool = false;
	/** 是否正在播放 */
	public var playing:Bool = false;

	private var video:FlxVideoSprite = null;
	private var ended:Bool = false;
	private var started:Bool = false;
	private var canSkipNow:Bool = false;
	private var diagFrame:Int = 0;
	/** [PE-iOS] 已播放秒数，用于「onEndReached 不触发」的超时兜底 */
	private var playElapsed:Float = 0;
	/** [PE-iOS] 视频时长（秒），由 bitmap.onLengthChanged 填充；0 = 未知 */
	private var videoDurSec:Float = 0;

	public function new():Void
	{
		super();
	}

	// ==================== 🩺 诊断写盘 ====================
	static function diag(line:String):Void
	{
		try
		{
			var p:String = SUtil.getPath() + 'pe_ios_video.txt';
			var old:String = '';
			if (FileSystem.exists(p))
			{
				try { old = File.getContent(p); } catch (e:Dynamic) { old = ''; }
				var lines:Array<String> = old.split('\n');
				if (lines.length > 120) old = lines.slice(lines.length - 120, lines.length).join('\n') + '\n';
			}
			File.saveContent(p, old + line + '\n');
		}
		catch (e:Dynamic) {}
	}

	/// 把 hxvlc 内部那个「原始 Bitmap」（真正输出视频帧的对象）的状态记下来。
	/// 它才是画面能不能出来的关键：FlxSprite 只是从它的 bitmapData 拷了一份。
	static function diagRawBitmap(tag:String, v:FlxVideoSprite):Void
	{
		if (v == null)
		{
			diag('[raw:' + tag + '] video 为 null');
			return;
		}
		var b = v.bitmap;
		if (b == null)
		{
			diag('[raw:' + tag + '] bitmap 为 null');
			return;
		}

		var parentStr:String = 'null';
		try
		{
			if (b.parent != null) parentStr = 'yes';
		}
		catch (e:Dynamic) { parentStr = 'err'; }

		var bmdStr:String = 'null';
		try
		{
			if (b.bitmapData != null) bmdStr = b.bitmapData.width + 'x' + b.bitmapData.height;
		}
		catch (e:Dynamic) { bmdStr = 'err'; }

		diag('[raw:' + tag + '] visible=' + b.visible + ' alpha=' + b.alpha
			+ ' x=' + b.x + ' y=' + b.y
			+ ' w=' + b.width + ' h=' + b.height
			+ ' scale=' + b.scaleX + ',' + b.scaleY
			+ ' parent=' + parentStr + ' bmd=' + bmdStr
			+ ' flixVisible=' + v.visible + ' flixAlpha=' + v.alpha);
	}

	/**
	 * [PE-iOS] 全坐标系快照 —— 用于定位「视频偏右 / 不居中」。
	 *
	 * 偏右这件事，根因只可能在下列几种坐标系之一，所以一次性全打出来：
	 *   1) sprite 自己的 x/y/width/height/scale/offset（相对相机视口）
	 *   2) sprite 所属相机的 x/y/width/height/scroll（视口与滚动）
	 *   3) FlxG.width/height（逻辑画布）
	 *   4) FlxG.game.x/y/scaleX/scaleY（RatioScaleMode 施加的偏移与缩放）
	 *   5) 内层 Bitmap 的 x/y/width/height/scale（直显路径才相关）
	 *   对比 (1) 与 (3)：若 sprite.x == 0 但画面仍偏右，问题在 (2) 或 (4)。
	 */
	static function diagCoords(tag:String, v:FlxVideoSprite):Void
	{
		if (v == null) { diag('[coord:' + tag + '] video=null'); return; }
		try
		{
			var s:String = '[coord:' + tag + ']'
				+ ' spr(x=' + Std.string(v.x) + ',y=' + Std.string(v.y)
				+ ',w=' + Std.string(v.width) + ',h=' + Std.string(v.height)
				+ ',sx=' + Std.string(v.scale.x) + ',sy=' + Std.string(v.scale.y)
				+ ',ox=' + Std.string(v.offset.x) + ',oy=' + Std.string(v.offset.y) + ')'
				+ ' FlxG(' + FlxG.width + 'x' + FlxG.height + ')';

			var g:Dynamic = FlxG.game;
			if (g != null)
			{
				s += ' game(x=' + Std.string(Reflect.getProperty(g, 'x'))
					+ ',y=' + Std.string(Reflect.getProperty(g, 'y'))
					+ ',sx=' + Std.string(Reflect.getProperty(g, 'scaleX'))
					+ ',sy=' + Std.string(Reflect.getProperty(g, 'scaleY')) + ')';
			}

			if (v.cameras != null && v.cameras.length > 0 && v.cameras[0] != null)
			{
				var c = v.cameras[0];
				s += ' cam(' + Std.string(c.x) + ',' + Std.string(c.y)
					+ ' ' + c.width + 'x' + c.height
					+ ' z=' + Std.string(c.zoom)
					+ ' sc=' + Std.string(c.scroll.x) + ',' + Std.string(c.scroll.y) + ')';
			}
			else s += ' cam(无)';

			if (v.bitmap != null)
			{
				var b = v.bitmap;
				s += ' bmp(' + Std.string(b.x) + ',' + Std.string(b.y)
					+ ' ' + Std.string(b.width) + 'x' + Std.string(b.height)
					+ ' s=' + Std.string(b.scaleX) + ' vis=' + b.visible + ')';
			}

			diag(s);
		}
		catch (e:Dynamic) { diag('[coord:' + tag + '] 快照失败: ' + e); }
	}

	/** 播放一个视频。path 可以是绝对路径，也可以是相对游戏目录的路径。 */
	public function playVideo(path:String, ?shouldLoop:Bool = false, ?canSkipIt:Bool = true):Void
	{
		if (path == null || path.length < 1)
		{
			diag('[playVideo] 收到空路径，直接跳过');
			onVideoFinished();
			return;
		}

		loop = shouldLoop;
		canSkip = canSkipIt;
		videoPath = resolvePath(path);
		var fileExists:Bool = FileSystem.exists(videoPath);
		diag('[playVideo] 请求=' + path + ' 解析后=' + videoPath + ' 存在=' + fileExists);

		video = new FlxVideoSprite();
		video.antialiasing = false;

		// 钉在屏幕上，不受相机滚动/缩放影响
		video.scrollFactor.set(0, 0);
		try
		{
			var cams:Array<flixel.FlxCamera> = FlxG.cameras.list;
			if (cams != null && cams.length > 0)
				video.cameras = [cams[cams.length - 1]];
		}
		catch (e:Dynamic) { diag('[camera] 指定相机失败: ' + e); }

		add(video);
		diag('[create] FlxVideoSprite 已创建 bitmap=' + (video.bitmap == null ? 'null' : 'ok')
			+ ' scroll=' + video.scrollFactor.x + ',' + video.scrollFactor.y
			+ ' cams=' + (video.cameras == null ? 'null' : '' + video.cameras.length));

		if (video.bitmap != null)
		{
			video.bitmap.onFormatSetup.add(function():Void
			{
				if (video == null || video.bitmap == null)
				{
					diag('[formatSetup] 警告：video 或 bitmap 已为 null');
					return;
				}
				var bmd = video.bitmap.bitmapData;
				if (bmd == null)
				{
					diag('[formatSetup] 警告：bitmapData 为 null → 画面会是空白');
					return;
				}

				diag('[formatSetup] bitmapData=' + bmd.width + 'x' + bmd.height);

				if (bmd.width < 2 || bmd.height < 2)
				{
					diag('[formatSetup] 警告：尺寸过小，按原尺寸显示');
					// [PE-iOS] 不用 screenCenter（它按 sprite 尺寸算，hitbox 未同步时会歪）。
					video.updateHitbox();
					video.x = (FlxG.width - video.width) / 2;
					video.y = (FlxG.height - video.height) / 2;
					video.scrollFactor.set(0, 0);
					diagRawBitmap('tiny', video);
					return;
				}

				// [PE-iOS] 缩放策略：按「完整放得下」等比缩放（Math.min），不放大不裁切。
				//
				// ── 真正会「偏右 / 右边和下面被裁」的地方不在这里 ──────────────
				//   已经定案：那是 hxvlc 内部那个原始 Bitmap（挂在 FlxG.game 上、
				//   尺寸自动跟随 bitmapData、不受相机管辖）被打开 visible 造成的，
				//   修复在 Main.hx 的 ensureVideoBitmapVisible()（强制隐藏它）。
				//   本节代码只负责 FlxSprite 这条正路的缩放。
				//
				// ★ 不要用 video.setGraphicSize() ★
				//   FlxSprite.setGraphicSize(W,H) 内部是：
				//       scale.x = W / frameWidth;   scale.y = H / frameHeight;
				//   —— 它【除以当前 frame 尺寸】反推缩放比例。
				//   FlxVideoSprite 的帧由 hxvlc 在【它自己的】onFormatSetup 回调里
				//   通过 loadGraphic(FlxGraphic.fromBitmapData(...)) 更新。我们的回调
				//   挂在同一事件上，执行顺序取决于 add 顺序。若我们的先跑，
				//   frameWidth 还是构造时 makeGraphic(1,1) 留下的 1：
				//       scale.x = (1920 * 0.667) / 1 = 1280   ← 灾难性放大
				//   因此：直接设 scale（明确的缩放因子，与 frameWidth 无关），
				//   再 updateHitbox() 同步 width/height/offset。
				//
				// ⚠ 也不用 video.screenCenter()：它按 width/height 算，
				//   而这些值要 updateHitbox() 之后才准。
				var viewW:Float = FlxG.width;
				var viewH:Float = FlxG.height;

				var scale:Float = Math.min(viewW / bmd.width, viewH / bmd.height);
				if (scale <= 0 || scale != scale) scale = 1; // NaN 自检
				video.scale.set(scale, scale);
				video.updateHitbox();
				video.x = (viewW - video.width) / 2;
				video.y = (viewH - video.height) / 2;
				video.scrollFactor.set(0, 0);

				// ★ [PE-iOS] 强制隐藏 hxvlc 内层原始 Bitmap。
				//   它被 FlxVideoSprite 构造时 addChild 到 FlxG.game 上
				//   （FlxVideoSprite.hx 第 95-96 行，默认 visible=false）：
				//     · 尺寸自动跟随 bitmapData（libVLC 逐帧重算 1502x845→1920x1080）
				//     · 不受 flixel 相机与 FlxSprite.scale 管辖
				//     · 父节点 FlxG.game 带黑边偏移（offset.x/offset.y）
				//   ⇒ 一旦它 visible=true，屏幕就多一个偏右、下边被裁的视频。
				//   Main.hx 的 ensureVideoBitmapVisible() 每 12 帧纠一次，这里再补一刀。
				try { video.bitmap.visible = false; } catch (e:Dynamic) {}

				diag('[formatSetup] 居中：view=' + viewW + 'x' + viewH
					+ ' FlxG=' + FlxG.width + 'x' + FlxG.height
					+ ' xy=' + video.x + ',' + video.y);
				diag('[formatSetup] 缩放完成 frame=' + video.frameWidth + 'x' + video.frameHeight
					+ ' scale=' + video.scale.x + ' -> ' + video.width + 'x' + video.height
					+ ' xy=' + video.x + ',' + video.y
					+ ' scroll=' + video.scrollFactor.x + ',' + video.scrollFactor.y);

				diagRawBitmap('afterFormat', video);
				diagCoords('afterFormat', video);
			});
			video.bitmap.onEndReached.add(onVideoFinished);
			// [PE-iOS] 记录时长。
			//   FlxVideoSprite 无 length 字段，时长在底层 bitmap(Video) 上，
			//   单位【微秒】，且解析完成前为 0，所以用 onLengthChanged 事件拿。
			//   参数用 Dynamic 接收后立刻转 Float 秒数，避免 Int64 参与运算。
			try
			{
				video.bitmap.onLengthChanged.add(function(us:Dynamic):Void
				{
					var v:Float = 0;
					try { v = Std.parseFloat(Std.string(us)); } catch (e:Dynamic) { v = 0; }
					if (v > 0) videoDurSec = v / 1000000.0;
				});
			}
			catch (e:Dynamic) {}
		}

		var options:Array<String> = null;
		if (loop) options = ['--input-repeat=999999'];

		var loaded:Bool = false;
		try { loaded = video.load(videoPath, options); } catch (e:Dynamic) { diag('[load] 抛异常: ' + e); loaded = false; }
		diag('[load] 返回值=' + loaded);

		if (!loaded)
		{
			var fileName:String = videoPath.split('/').pop();
			var retryPath:String = SUtil.getPath() + 'assets/videos/' + fileName;
			diag('[load] 首次失败，改用资源路径重试: ' + retryPath);
			try { loaded = video.load(retryPath, options); } catch (e:Dynamic) { loaded = false; }
			diag('[load] 重试返回值=' + loaded);
		}

		if (!loaded)
		{
			diag('[load] 两次都失败，跳过该视频');
			onVideoFinished();
			return;
		}

		playing = true;
		started = true;
		diagFrame = 0;
		playElapsed = 0;
		videoDurSec = 0;

		new FlxTimer().start(0.001, function(_:FlxTimer)
		{
			if (video != null && playing)
			{
				try { video.play(); } catch (e:Dynamic) { diag('[play] 异常: ' + e); }
				diag('[play] 已调用 play()');
			}
		});

		// ★ 不依赖 update() 的定时快照：0.5s / 1.5s / 3s 各记一次原始 Bitmap 状态。
		// 之前只靠 update() 记录，结果一行 [state] 都没写出来（说明 update 没被驱动），
		// 所以改成定时器，确保一定能拿到数据。
		new FlxTimer().start(0.5, function(_:FlxTimer) {
			if (playing && video != null) { diagRawBitmap('t0.5', video); diagCoords('t0.5', video); }
		});
		new FlxTimer().start(1.5, function(_:FlxTimer) {
			if (playing && video != null) { diagRawBitmap('t1.5', video); diagCoords('t1.5', video); }
		});
		new FlxTimer().start(3.0, function(_:FlxTimer) {
			if (playing && video != null) { diagRawBitmap('t3.0', video); diagCoords('t3.0', video); }
		});

		new FlxTimer().start(0.5, function(_:FlxTimer) canSkipNow = true);
	}

	/** 老模组会调用的跳过接口 */
	public function skipVideo():Void
	{
		onVideoFinished();
	}

	/** 播放结束 / 被跳过：收尾、回调、关掉 substate */
	public function onVideoFinished():Void
	{
		if (ended) return;
		ended = true;
		playing = false;
		diag('[finish] 视频结束/被跳过');

		if (video != null)
		{
			try
			{
				remove(video, true);
				video.destroy();
			}
			catch (e:Dynamic)
			{
				diag('[finish] 释放视频对象出错（已忽略）: ' + e);
			}
			video = null;
		}

		if (FlxG.sound.music != null && !FlxG.sound.music.playing)
		{
			try { FlxG.sound.music.play(); } catch (e:Dynamic) {}
		}

		if (finishCallback != null) finishCallback();
		if (onVideoEnd != null) onVideoEnd();

		try { close(); } catch (e:Dynamic) {}
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (started && video != null && playing)
		{
			diagFrame++;
			if (diagFrame == 30 || diagFrame == 120)
				diagRawBitmap('f' + diagFrame, video);

			// ★★★ [PE-iOS] 关键兜底：不依赖 onEndReached ★★★
			//   某些情况下 hxvlc 在 iOS 上【不派发 onEndReached】，
			//   导致 substate 永远不关 ⇒ 「过场播完卡住、进不去打歌界面」。
			//   用「已播放时长 > 视频时长 + 2 秒」做超时兜底；
			//   时长来自 bitmap.onLengthChanged（已换算成秒，见 videoDurSec）；
			//   拿不到时长时用 180 秒固定上限，绝不死锁。
			//   （onVideoFinished 内部有 `if (ended) return;` 去重。）
			playElapsed += elapsed;
			if (videoDurSec > 0 && playElapsed > videoDurSec + 2.0)
			{
				diag('[PE-iOS] 过场视频超时兜底收尾（onEndReached 未触发）dur=' + videoDurSec
					+ ' elapsed=' + playElapsed);
				onVideoFinished();
				return;
			}
			else if (videoDurSec <= 0 && playElapsed > 180.0)
			{
				diag('[PE-iOS] 过场视频时长未知，硬超时兜底收尾 elapsed=' + playElapsed);
				onVideoFinished();
				return;
			}
		}

		if (!started || !playing || !canSkip || !canSkipNow) return;

		var pressed:Bool = FlxG.keys.justPressed.ANY || FlxG.mouse.justPressed;
		#if mobile
		for (touch in FlxG.touches.list)
		{
			if (touch.justPressed) pressed = true;
		}
		#end

		if (pressed) skipVideo();
	}

	/** 把相对路径补成绝对路径（libVLC 需要绝对路径） */
	private function resolvePath(path:String):String
	{
		if (path == null || path.length < 1) return path;
		if (path.indexOf('/') == 0) return path;

		var candidate:String = SUtil.getPath() + path;
		if (FileSystem.exists(candidate)) return candidate;

		var inAssets:String = SUtil.getPath() + 'assets/videos/' + path;
		if (FileSystem.exists(inAssets)) return inAssets;

		return path;
	}
}
#end
