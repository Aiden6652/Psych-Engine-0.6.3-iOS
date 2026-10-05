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

				// [PE-iOS] 用 Math.min（等比缩放到「完整放得下」）：不放大、不裁切。
				//   之前用 Math.max 是「铺满画布」策略 —— 会把视频放大并裁掉边缘，
				//   这就是用户反馈的「过场视频被放大」的直接原因。
				//   视频本来就该完整显示，宁可留黑边也不要放大。
				//   注意：必须与 Main.hx 的 scaleVideoBitmaps() 保持一致（同为 Math.min）。
				//
				// ⚠ 关于居中：不要用 video.screenCenter()！
				//   它按 sprite 的 width/height 与 FlxG.width/height 算，
				//   而 setGraphicSize() 之后 hitbox/offset 可能未同步 ⇒ 算歪。
				//   这里直接手动算，并且把 x/y 放在 updateHitbox() 【之后】。
				//
				//   参照系用 FlxG.width/height：FlxVideoSprite 挂在某个相机上，
				//   而相机【视口尺寸】恒等于 FlxG.width x FlxG.height（scaleMode 保证），
				//   相机自身的黑边偏移在绘制时施加，与 sprite 坐标无关。
				var viewW:Float = FlxG.width;
				var viewH:Float = FlxG.height;

				var scale:Float = Math.min(viewW / bmd.width, viewH / bmd.height);
				if (scale <= 0 || scale != scale) scale = 1; // NaN 自检
				var tw:Int = Std.int(Math.max(1, bmd.width * scale));
				var th:Int = Std.int(Math.max(1, bmd.height * scale));
				video.setGraphicSize(tw, th);
				video.updateHitbox();
				// ★ 必须在 updateHitbox() 之后设坐标（否则被 offset 重算覆盖）
				video.x = (viewW - video.width) / 2;
				video.y = (viewH - video.height) / 2;
				video.scrollFactor.set(0, 0);
				video.scrollFactor.set(0, 0);
				diag('[formatSetup] 居中：view=' + viewW + 'x' + viewH
					+ ' FlxG=' + FlxG.width + 'x' + FlxG.height
					+ ' xy=' + video.x + ',' + video.y);
				diag('[formatSetup] 缩放完成 size=' + tw + 'x' + th + ' scale=' + video.scale.x
					+ ' xy=' + video.x + ',' + video.y
					+ ' scroll=' + video.scrollFactor.x + ',' + video.scrollFactor.y);

				diagRawBitmap('afterFormat', video);
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
		new FlxTimer().start(0.5, function(_:FlxTimer) { if (playing && video != null) diagRawBitmap('t0.5', video); });
		new FlxTimer().start(1.5, function(_:FlxTimer) { if (playing && video != null) diagRawBitmap('t1.5', video); });
		new FlxTimer().start(3.0, function(_:FlxTimer) { if (playing && video != null) diagRawBitmap('t3.0', video); });

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
