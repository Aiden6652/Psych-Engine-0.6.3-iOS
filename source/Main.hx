package;

import flixel.graphics.FlxGraphic;
import flixel.FlxG;
import flixel.FlxGame;
import flixel.FlxState;
import openfl.Assets;
import openfl.Lib;
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
	/** [PE-iOS] 目标画面宽高比（对齐「无视频版」）。改成 0 即恢复铺满。 */
	static inline var IOS_TARGET_ASPECT:Float = 16.0 / 9.0;

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

	/// 诊断帧计数（视频 Bitmap 扫描用）
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

	// ==================== [PE-iOS] 视频显示兜底 ====================
	// 背景：hxvlc 的 FlxVideoSprite 会把视频帧交给一个内部的 OpenFL Bitmap
	//（hxvlc.openfl.Video，继承自 openfl.display.Bitmap，被 addChild 到 FlxG.game 上），
	// 该 Bitmap 默认 visible=false，然后靠 FlxSprite 从它的 bitmapData 中转显示。
	//
	// 实测：标题页（单相机、挂在 FlxState）能正常显示；
	// 打歌场景（多相机、挂在 FlxSubState）无论 GPU 还是 CPU 渲染路径都不出画面，
	// 而 load / 帧尺寸 / 缩放 / 位置 / scrollFactor / 相机都已逐一排除。
	//
	// 所以这里直接把那个原始 Bitmap 显示出来 —— 绕开 FlxSprite 中转，
	// 这也是 libVLC 官方示例使用的显示路径，最直接可靠。
	private function scanAndShowVideoBitmaps():Void
	{
		#if (VIDEOS_ALLOWED && ios)
		var g = FlxG.game;
		if (g == null) return;

		var report:StringBuf = new StringBuf();
		var found:Int = 0;

		for (i in 0...g.numChildren)
		{
			var c = g.getChildAt(i);
			if (c == null) continue;

			var cls = Type.getClass(c);
			var cn:String = cls != null ? Type.getClassName(cls) : '';
			if (cn == null || cn.indexOf('Video') < 0) continue;

			found++;

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

			if (w < 2 || h < 2)
			{
				report.add('[' + i + '] ' + cn + ' w=' + w + ' h=' + h + '（无帧数据，跳过）\n');
				continue;
			}

			// 让它直接显示，并铺满 FlxGame 的逻辑区域（1280x720）
			try
			{
				Reflect.setProperty(c, 'visible', true);
				Reflect.setProperty(c, 'x', 0.0);
				Reflect.setProperty(c, 'y', 0.0);
				Reflect.setProperty(c, 'scaleX', FlxG.width / w);
				Reflect.setProperty(c, 'scaleY', FlxG.height / h);

				var vis:Bool = Reflect.getProperty(c, 'visible');
				var sx:Float = Reflect.getProperty(c, 'scaleX');
				report.add('[' + i + '] ' + cn + ' bmd=' + w + 'x' + h + ' -> visible=' + vis + ' scale=' + sx + '\n');
			}
			catch (e:Dynamic)
			{
				report.add('[' + i + '] ' + cn + ' 设置失败: ' + e + '\n');
			}
		}

		if (found > 0)
		{
			try { File.saveContent(SUtil.getPath() + 'pe_ios_videobitmap.txt', report.toString()); } catch (e:Dynamic) {}
		}
		#end
	}

	private function setupGame():Void
	{
		var stageWidth:Int = Lib.current.stage.stageWidth;
		var stageHeight:Int = Lib.current.stage.stageHeight;

		// [PE-iOS] 只决定画布尺寸；居中交给 HaxeFlixel 自己处理（切勿再手动设 flxGame.y，
		// 否则双重偏移 → 底部被裁）。
		var viewHeight:Int = stageHeight;
		if (IOS_TARGET_ASPECT > 0)
		{
			var targetH:Int = Std.int(stageWidth / IOS_TARGET_ASPECT);
			if (targetH > 0 && targetH < stageHeight)
				viewHeight = targetH;
		}

		if (game.zoom == -1.0)
		{
			var ratioX:Float = stageWidth / game.width;
			var ratioY:Float = viewHeight / game.height;
			game.zoom = Math.min(ratioX, ratioY);
			game.width = Math.ceil(stageWidth / game.zoom);
			game.height = Math.ceil(viewHeight / game.zoom);
		}

		var info:String = 'stage=' + stageWidth + 'x' + stageHeight
			+ '\nviewHeight=' + viewHeight
			+ '\ncanvas=' + game.width + 'x' + game.height
			+ '\nzoom=' + game.zoom + '\n';
		trace('[PE-iOS] 视口(16:9)：' + info.replace('\n', ' '));

		#if ios
		try { File.saveContent(SUtil.getPath() + 'pe_ios_viewport.txt', info); } catch (e:Dynamic) {}
		#end

		SUtil.doTheCheck();

		ClientPrefs.loadDefaultKeys();

		var flxGame:FlxGame = new FlxGame(game.width, game.height, game.initialState, #if (flixel < "5.0.0") game.zoom, #end game.framerate, game.framerate, game.skipSplash, game.startFullscreen);
		addChild(flxGame);

		// 每帧（每 6 帧一次）扫描并显示 hxvlc 内部的原始视频 Bitmap
		Lib.current.stage.addEventListener(Event.ENTER_FRAME, function(e:Event):Void
		{
			scanFrames++;
			if (scanFrames % 6 == 0)
				scanAndShowVideoBitmaps();
		});

		fpsVar = new FPS(10, 3, 0xFFFFFF);
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
				DiscordClient.shutdown();
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
