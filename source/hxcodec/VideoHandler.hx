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
 * 🩺 关键修复（本次）：**把视频钉在屏幕上**。
 *   实测：视频能 load、能拿到 1920x1080 的帧、也能 play，但屏幕上看不见。
 *   原因是 FlxVideoSprite 默认 scrollFactor = (1,1)（跟随世界坐标）：
 *     - 挂在 TitleState（相机固定）时正常 → 所以片头能看见；
 *     - 挂在 FlxSubState（PlayState 有 3 个相机、而且相机在跟随角色）时，
 *       画面会随着相机滚动跑出屏幕 → 表现为「只有声音」。
 *   解决：scrollFactor 置 (0,0) + 指定在最后一个相机上绘制（盖在最上层）。
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
				if (lines.length > 80) old = lines.slice(lines.length - 80, lines.length).join('\n') + '\n';
			}
			File.saveContent(p, old + line + '\n');
		}
		catch (e:Dynamic) {}
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

		// 注意：不传 (0, 0) —— hxvlc 2.x 的签名是 new(?instance, ?x, ?y)，
		// 传 (0, 0) 会被当成 instance=0 而编译失败；不传参数在 1.x / 2.x 下都合法。
		video = new FlxVideoSprite();
		video.antialiasing = false;

		// ★ 关键：钉在屏幕上，不受相机滚动/缩放影响
		video.scrollFactor.set(0, 0);
		try
		{
			var cams:Array<flixel.FlxCamera> = FlxG.cameras.list;
			if (cams != null && cams.length > 0)
				video.cameras = [cams[cams.length - 1]]; // 最上层相机（盖住 HUD）
		}
		catch (e:Dynamic) { diag('[camera] 指定相机失败: ' + e); }

		add(video);
		diag('[create] FlxVideoSprite 已创建 bitmap=' + (video.bitmap == null ? 'null' : 'ok')
			+ ' scroll=' + video.scrollFactor.x + ',' + video.scrollFactor.y
			+ ' cams=' + (video.cameras == null ? 'null' : '' + video.cameras.length));

		if (video.bitmap != null)
		{
			// 视频尺寸就绪后铺满屏幕（保持长宽比，多余的裁掉）
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

				// 防御：尺寸异常（0 / NaN）时不要算缩放，
				// 否则会得到 NaN → Std.int(NaN)=0 → setGraphicSize(0,0) → 精灵不可见。
				if (bmd.width < 2 || bmd.height < 2)
				{
					diag('[formatSetup] 警告：尺寸过小，按原尺寸显示');
					video.updateHitbox();
					video.screenCenter();
					video.scrollFactor.set(0, 0);
					return;
				}

				var scale:Float = Math.max(FlxG.width / bmd.width, FlxG.height / bmd.height);
				if (scale <= 0 || scale != scale) scale = 1; // NaN 自检
				var tw:Int = Std.int(Math.max(1, bmd.width * scale));
				var th:Int = Std.int(Math.max(1, bmd.height * scale));
				video.setGraphicSize(tw, th);
				video.updateHitbox();
				video.screenCenter();
				video.scrollFactor.set(0, 0); // screenCenter 后再次确保（防被重置）
				diag('[formatSetup] 缩放完成 size=' + tw + 'x' + th + ' scale=' + video.scale.x
					+ ' xy=' + video.x + ',' + video.y
					+ ' scroll=' + video.scrollFactor.x + ',' + video.scrollFactor.y);
			});
			video.bitmap.onEndReached.add(onVideoFinished);
		}

		var options:Array<String> = null;
		if (loop) options = ['--input-repeat=999999'];

		var loaded:Bool = false;
		try { loaded = video.load(videoPath, options); } catch (e:Dynamic) { diag('[load] 抛异常: ' + e); loaded = false; }
		diag('[load] 返回值=' + loaded);

		if (!loaded)
		{
			// 回退：某些模组把视频放在游戏目录的 assets/videos 下
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

		// 等一帧再 play，避免刚 load 完立刻播放导致首帧黑屏
		new FlxTimer().start(0.001, function(_:FlxTimer)
		{
			if (video != null && playing)
			{
				try { video.play(); } catch (e:Dynamic) { diag('[play] 异常: ' + e); }
				diag('[play] 已调用 play()');
			}
		});

		// 0.5 秒内不响应跳过，避免开头那一下点击直接把视频跳没
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

		// 视频播完后把菜单音乐恢复回来
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

		// ==================== 🩺 播放期状态快照 ====================
		// 如果又出现「只有声音没画面」，看 pe_ios_video.txt 里这几行：
		//   x/y 是不是在屏幕外、w/h 是不是 0、visible/alpha 是不是不对。
		if (started && video != null && playing)
		{
			diagFrame++;
			if (diagFrame == 30 || diagFrame == 90 || diagFrame == 240)
			{
				var bw:Int = -1;
				var bh:Int = -1;
				if (video.bitmap != null && video.bitmap.bitmapData != null)
				{
					bw = video.bitmap.bitmapData.width;
					bh = video.bitmap.bitmapData.height;
				}
				diag('[state] f=' + diagFrame
					+ ' xy=' + video.x + ',' + video.y
					+ ' size=' + video.width + 'x' + video.height
					+ ' alpha=' + video.alpha + ' visible=' + video.visible
					+ ' scroll=' + video.scrollFactor.x + ',' + video.scrollFactor.y
					+ ' cams=' + (video.cameras == null ? 'null' : '' + video.cameras.length)
					+ ' camSize=' + (video.cameras != null && video.cameras.length > 0 ? (video.cameras[0].width + 'x' + video.cameras[0].height) : '-')
					+ ' bmd=' + bw + 'x' + bh);
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
