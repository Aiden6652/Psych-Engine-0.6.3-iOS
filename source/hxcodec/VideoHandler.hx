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
 * 为什么需要这个文件：
 *   - 引擎（PlayState.hx 等）和大量老模组写的都是 `import hxcodec.VideoHandler` / `new MP4Handler()`；
 *   - 但官方 hxCodec 在 iOS 上是个空壳（include.xml 的 ios 段只声明了几个 Apple 框架，
 *     完全没有链接 libvlc），拿它播视频只会黑屏/直接挂；
 *   - hxvlc 自带 libvlc 的 iOS 静态库（libvlc_device.a），所以 iOS 上让它干活，
 *     再补一个同名的 VideoHandler，让老模组一行代码都不用改。
 *
 * ⚠ hxvlc 版本要求：**1.9.3**
 *   原因一：1.7/1.8.x 的 FlxVideoSprite 没有 `bitmap.forceRendering = true`，
 *   也不带 1.9.x 的 GPU 纹理渲染路径 → 表现为「能播出声音、但画面出不来」。
 *   原因二：1.9.4+ / 2.x 用了 `bitmap?.xxx`（Haxe 4.3 安全导航语法），
 *   本仓库 Haxe 固定 4.2.4，会直接语法报错。
 *
 * 🩺 诊断：播视频全过程会追加写入 <游戏目录>/pe_ios_video.txt，
 *   含路径、文件是否存在、load 返回值、onFormatSetup 是否触发、bitmapData 尺寸等。
 *   再出现「有声音无画面」时，直接看这个文件即可定位。
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

	public function new():Void
	{
		super();
	}

	// ==================== 🩺 诊断写盘 ====================
	// 追加一行到 <游戏目录>/pe_ios_video.txt（只保留最近 60 行，避免无限增长）。
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
				if (lines.length > 60) old = lines.slice(lines.length - 60, lines.length).join('\n') + '\n';
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

		if (!fileExists)
			diag('[playVideo] 警告：文件不存在，libvlc 会加载失败');

		// 注意：这里刻意不传 (0, 0)。hxvlc 2.x 的签名是 new(?instance, ?x, ?y)，
		// 传 (0, 0) 会被当成「instance=0, x=0」，类型不匹配直接编译失败；
		// 而不传任何参数在 1.x / 2.x 下都合法（x/y 默认为 0）。
		video = new FlxVideoSprite();
		video.antialiasing = false;
		add(video);
		diag('[create] FlxVideoSprite 已创建，bitmap=' + (video.bitmap == null ? 'null' : 'ok'));

		if (video.bitmap != null)
		{
			// 视频尺寸就绪后铺满屏幕（保持长宽比，多余的裁掉）
			video.bitmap.onFormatSetup.add(function():Void
			{
				if (video == null || video.bitmap == null)
				{
					diag('[formatSetup] 警告：video 或 bitmap 已为 null，放弃缩放');
					return;
				}
				var bmd = video.bitmap.bitmapData;
				if (bmd == null)
				{
					diag('[formatSetup] 警告：bitmapData 为 null（视频帧没准备好）→ 画面会是空白');
					return;
				}

				diag('[formatSetup] bitmapData=' + bmd.width + 'x' + bmd.height);

				// 防御：尺寸异常（0 / NaN）时不要算缩放，
				// 否则会得到 NaN → Std.int(NaN)=0 → setGraphicSize(0,0)
				// → 精灵完全不可见（正好就是「有声音无画面」的样子）。
				if (bmd.width < 2 || bmd.height < 2)
				{
					diag('[formatSetup] 警告：尺寸过小，跳过缩放，按原尺寸显示');
					video.updateHitbox();
					video.screenCenter();
					return;
				}

				var scale:Float = Math.max(FlxG.width / bmd.width, FlxG.height / bmd.height);
				if (scale <= 0 || scale != scale) scale = 1; // NaN 自检（NaN != NaN）
				var tw:Int = Std.int(Math.max(1, bmd.width * scale));
				var th:Int = Std.int(Math.max(1, bmd.height * scale));
				video.setGraphicSize(tw, th);
				video.updateHitbox();
				video.screenCenter();
				diag('[formatSetup] 缩放完成 size=' + tw + 'x' + th + ' scale=' + video.scale.x);
			});
			video.bitmap.onEndReached.add(onVideoFinished);
		}

		var options:Array<String> = null;
		if (loop) options = ['--input-repeat=999999'];

		var loaded:Bool = false;
		try
		{
			loaded = video.load(videoPath, options);
		}
		catch (e:Dynamic)
		{
			diag('[load] 抛异常: ' + e);
			loaded = false;
		}
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

		// 再试：相对游戏目录的 assets/videos/
		var inAssets:String = SUtil.getPath() + 'assets/videos/' + path;
		if (FileSystem.exists(inAssets)) return inAssets;

		return path;
	}
}
#end
