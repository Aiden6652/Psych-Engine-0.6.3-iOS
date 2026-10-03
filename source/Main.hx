package;

import flixel.graphics.FlxGraphic;
import flixel.FlxG;
import flixel.FlxGame;
import flixel.FlxState;
import openfl.Assets;
import openfl.Lib;
import openfl.display.Bitmap;
import openfl.display.FPS;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.display.StageScaleMode;
import lime.app.Application;

#if desktop
import Discord.DiscordClient;
#end

//crash handler stuff
#if CRASH_HANDLER
import openfl.events.UncaughtErrorEvent;
import haxe.CallStack;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;
#end

using StringTools;

class Main extends Sprite
{
	/**
	 * [PE-iOS] 顶部黑边比例。
	 *
	 * 实测参照（iPad Pro 11"，屏幕 2420x1668，stage 1024x768）：
	 *   无视频版：顶部留黑 ≈ 202px（屏幕坐标），内容一直蓴到屏幕最底部。
	 *   换算到 stage：202 / 2.172 ≈ 92px，即 768 的 12.1%。
	 */
	static inline var IOS_TOP_INSET_RATIO:Float = 0.121;

	/**
	 * [PE-iOS] 实际下移量占“顶部黑边”的比例（折中系数）。
	 *
	 * 两个需求是矛盾的，这里取折中：
	 *   - 完全不下移（0.0）：画面居中，打歌不会“被放大/底部被裁”，
	 *     但触控色带会悬在屏幕上边（离底约 208px）；
	 *   - 完全下移（1.0）：色带能贴到屏幕底，但画面底部会被裁 208px，
	 *     表现出来就是“打歌时画面放大”。
	 * 0.5 时：色带下移约 104px（已经很接近底部），
	 * 底部裁切同样减半（104px），“放大”感明显减轻。
	 *
	 * 想回哪边就把这两个常量往哪边调：
	 *   只要不裁切 → 把本常量改 0.0；
	 *   只要色带贴底 → 改成 1.0。
	 */
	static inline var IOS_YOFFSET_FACTOR:Float = 0.5;

	var game = {
		width: 1280,
		height: 720,
		initialState: TitleState,
		zoom: -1.0,
		framerate: 60,
		skipSplash: true,
		startFullscreen: true
	};

	public static var fpsVar:FPS;

	/// 视频 Bitmap 扫描的帧计数
	var scanFrames:Int = 0;

	public static function main():Void
	{
		Lib.current.addChild(new Main());
	}

	public function new()
	{
		super();

    SUtil.gameCrashCheck();
		if (stage != null)
			init();
		else
			addEventListener(Event.ADDED_TO_STAGE, init);
	}

	private function init(?E:Event):Void
	{
		if (hasEventListener(Event.ADDED_TO_STAGE))
			removeEventListener(Event.ADDED_TO_STAGE, init);

		setupGame();
	}

	// ==================== [PE-iOS] 视频 Bitmap 尺寸纠正 ====================
	// 只在确实存在 hxvlc 的 Video Bitmap 时才干活（无视频时零开销），
	// 把它的缩放对到画布大小（修“视频被放大”）。
	private function scaleVideoBitmaps():Void
	{
		#if (VIDEOS_ALLOWED && ios)
		var g = FlxG.game;
		if (g == null) return;

		var report:StringBuf = null;
		var found:Int = 0;

		for (i in 0...g.numChildren)
		{
			var c = g.getChildAt(i);
			if (c == null || !Std.isOfType(c, Bitmap)) continue;

			var cn:String = '';
			try { cn = Type.getClassName(Type.getClass(c)); } catch (e:Dynamic) {}
			if (cn == null || cn.indexOf('Video') < 0) continue;

			var w:Float = 0;
			var h:Float = 0;
			try
			{
				var bmd:Dynamic = Reflect.getProperty(c, 'bitmapData');
				if (bmd != null)
				{
					w = Reflect.getProperty(bmd, 'width');
					h = Reflect.getProperty(bmd, 'height');
				}
			}
			catch (e:Dynamic) {}

			// 只有真正拿到帧的才处理（否则无视频时每帧都白跑）
			if (w < 2 || h < 2) continue;

			found++;
			if (report == null) report = new StringBuf();

			try
			{
				var sc:Float = Math.max(FlxG.width / w, FlxG.height / h);
				if (sc <= 0 || sc != sc) sc = 1;
				Reflect.setProperty(c, 'scaleX', sc);
				Reflect.setProperty(c, 'scaleY', sc);
				Reflect.setProperty(c, 'x', (FlxG.width - w * sc) / 2);
				Reflect.setProperty(c, 'y', (FlxG.height - h * sc) / 2);
				report.add('[' + i + '] ' + cn + ' bmd=' + w + 'x' + h + ' -> scale=' + sc + '\n');
			}
			catch (e:Dynamic)
			{
				if (report != null) report.add('[' + i + '] ' + cn + ' 设置失败: ' + e + '\n');
			}
		}

		// 没有视频时不写文件（也减少磁盘 IO）
		if (found > 0 && report != null)
		{
			try { File.saveContent(SUtil.getPath() + 'pe_ios_videobitmap.txt', report.toString()); } catch (e:Dynamic) {}
		}
		#end
	}

	private function setupGame():Void
	{
		// 注意：这里【不再】强制 Video.useTexture=false。
		// 那是排查「打歌时视频没画面」时的临时手段，代价是每帧多拷一份
		// 1920x1080 的帧（约 8MB）到内存，容易造成随机掉帧甚至卡死。
		// 视频现在能正常播放，所以回默认的 GPU 纹理路径。

		var stageWidth:Int = Lib.current.stage.stageWidth;
		var stageHeight:Int = Lib.current.stage.stageHeight;

		var topInset:Int = 0;
		var viewHeight:Int = stageHeight;
		if (IOS_TOP_INSET_RATIO > 0)
		{
			topInset = Std.int(stageHeight * IOS_TOP_INSET_RATIO);
			viewHeight = stageHeight - topInset;
			if (viewHeight < 1)
			{
				topInset = 0;
				viewHeight = stageHeight;
			}
		}

		if (game.zoom == -1.0)
		{
			var ratioX:Float = stageWidth / game.width;
			var ratioY:Float = viewHeight / game.height;
			game.zoom = Math.min(ratioX, ratioY);
			game.width = Math.ceil(stageWidth / game.zoom);
			game.height = Math.ceil(viewHeight / game.zoom);
		}

		var yOffset:Int = Std.int(topInset * IOS_YOFFSET_FACTOR);

		var info:String = 'stage=' + stageWidth + 'x' + stageHeight
			+ '\ntopInset=' + topInset
			+ '\nyOffset=' + yOffset + '（折中系数 ' + IOS_YOFFSET_FACTOR + '）'
			+ '\nviewHeight=' + viewHeight
			+ '\ncanvas=' + game.width + 'x' + game.height
			+ '\nzoom=' + game.zoom + '\n';
		trace('[PE-iOS] 视口：' + info.replace('\n', ' '));

		#if ios
		try { File.saveContent(SUtil.getPath() + 'pe_ios_viewport.txt', info); } catch (e:Dynamic) {}
		#end

		SUtil.doTheCheck();

		ClientPrefs.loadDefaultKeys();

		var flxGame:FlxGame = new FlxGame(game.width, game.height, game.initialState, #if (flixel < "5.0.0") game.zoom, #end game.framerate, game.framerate, game.skipSplash, game.startFullscreen);
		addChild(flxGame);

		// 折中下移（直接赋值，不累加，所以不存在双重偏移）：
		// Flixel 自己会算 y = topInset/2；这里覆写成 topInset*factor。
		if (yOffset > 0)
		{
			flxGame.y = yOffset;
			var frames:Int = 0;
			var applier:Event->Void = null;
			applier = function(e:Event):Void
			{
				flxGame.y = yOffset;
				frames++;
				if (frames > 60 && Lib.current.stage != null)
					Lib.current.stage.removeEventListener(Event.ENTER_FRAME, applier);
			};
			Lib.current.stage.addEventListener(Event.ENTER_FRAME, applier);
		}

		// 视频 Bitmap 尺寸纠正（无视频时内部会直接跳过，不产生开销）
		Lib.current.stage.addEventListener(Event.ENTER_FRAME, function(e:Event):Void
		{
			scanFrames++;
			if (scanFrames % 12 == 0)
				scaleVideoBitmaps();
		});

		fpsVar = new FPS(10, 3, 0xFFFFFF);
		if (yOffset > 0)
			fpsVar.y = yOffset + 3;
		addChild(fpsVar);
		Lib.current.stage.align = "tl";
		Lib.current.stage.scaleMode = StageScaleMode.NO_SCALE;
		if(fpsVar != null) {
			fpsVar.visible = ClientPrefs.showFPS;
		}

		#if html5
		FlxG.autoPause = false;
		FlxG.mouse.visible = false;
		#end

		#if CRASH_HANDLER
		Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onCrash);
		#end

		#if desktop
		if (!DiscordClient.isInitialized) {
			DiscordClient.initialize();
			Application.current.window.onClose.add(function() {
				DiscordClient.down();
			});
		}
		#end
	}

	// Code was entirely made by sqirra-rng for their fnz engine named "Izzy Engine", big props to them!!!
	#if CRASH_HANDLER
	public static function onCrash(e:UncaughtErrorEvent):Void
		{
			var callStack:Array<StackItem> = CallStack.exceptionStack(true);
			var dateNow:String = Date.now().toString();
			dateNow = StringTools.replace(dateNow, " ", "_");
			dateNow = StringTools.replace(dateNow, ":", "'");

			var path:String = "crash/" + "crash_" + dateNow + ".txt";
			var errMsg:String = "";

			for (stackItem in callStack)
			{
				switch (stackItem)
				{
					case FilePos(s, file, line, column):
						errMsg += file + " (line " + line + ")\n";
					default:
						Sys.println(stackItem);
				}
			}

			errMsg += e.error;

			if (!FileSystem.exists(SUtil.getPath() + "crash"))
			FileSystem.createDirectory(SUtil.getPath() + "crash");

			File.saveContent(SUtil.getPath() + path, errMsg + "\n");

			Sys.println(errMsg);
			Sys.println("Crash dump saved in " + Path.normalize(path));
			Sys.println("Making a simple alert ...");

			FlxG.switchState(new CrashState());
		}
	#end
}
