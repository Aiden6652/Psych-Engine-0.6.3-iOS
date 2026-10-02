package hxcodec;

#if (VIDEOS_ALLOWED && (ios || android))
import flixel.FlxG;
import flixel.FlxSubState;
import flixel.util.FlxTimer;
import hxvlc.flixel.FlxVideoSprite;
import sys.FileSystem;

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
 * 模组里常见写法都能继续用：
 *   var video:MP4Handler = new MP4Handler();
 *   video.finishCallback = function() { ... };
 *   video.playVideo(Paths.video('cutscene'));   // 也可以是相对游戏目录的路径
 *   PlayState.instance.openSubState(video);
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

	/** 播放一个视频。path 可以是绝对路径，也可以是相对游戏目录的路径。 */
	public function playVideo(path:String, ?shouldLoop:Bool = false, ?canSkipIt:Bool = true):Void
	{
		if (path == null || path.length < 1)
		{
			trace('[PE-iOS] playVideo 收到空路径，直接跳过视频');
			onVideoFinished();
			return;
		}

		loop = shouldLoop;
		canSkip = canSkipIt;
		videoPath = resolvePath(path);
		trace('[PE-iOS] 开始播放视频: ' + videoPath);

		if (!FileSystem.exists(videoPath))
			trace('[PE-iOS] 警告：这个路径在文件系统里不存在，视频可能播不出来');

		video = new FlxVideoSprite(0, 0);
		video.antialiasing = false;
		add(video);

		if (video.bitmap != null)
		{
			// 视频尺寸就绪后铺满屏幕（保持长宽比，多余的裁掉）
			video.bitmap.onFormatSetup.add(function():Void
			{
				if (video == null || video.bitmap == null) return;
				var bmd = video.bitmap.bitmapData;
				if (bmd == null) return;
				var scale:Float = Math.max(FlxG.width / bmd.width, FlxG.height / bmd.height);
				if (scale <= 0) scale = 1;
				video.setGraphicSize(bmd.width * scale, bmd.height * scale);
				video.updateHitbox();
				video.screenCenter();
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
			trace('[PE-iOS] 视频加载异常: ' + e);
			loaded = false;
		}

		if (!loaded)
		{
			trace('[PE-iOS] 视频加载失败: ' + videoPath);
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
				try { video.play(); } catch (e:Dynamic) { trace('[PE-iOS] play 异常: ' + e); }
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

		if (video != null)
		{
			try
			{
				remove(video, true);
				video.destroy();
			}
			catch (e:Dynamic)
			{
				trace('[PE-iOS] 释放视频对象出错（已忽略）: ' + e);
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

		return path;
	}
}
#end
