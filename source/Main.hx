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
	/**
	 * [PE-iOS] 目标画面宽高比（对齐「无视频版」）。
	 *
	 * 为什么是 16:9：
	 *   实测「无视频版」在 iPad Pro 11"（2420x1668，宽高比 1.45）上的样子是：
	 *     画面宽 2220、高约 1249（= 2220 * 9/16），垂直居中，
	 *     上下各留 (1668-1249)/2 ≈ 209px 黑边，左右各留 100px。
	 *   也就是说：它本来就是「16:9 的游戏画面在非 16:9 的 iPad 屏幕上自然地上下留黑」，
	 *   不是「顶部刻意让出一段」。
	 *
	 * 之前用“顶部黑边比例”的做法（把画面拉满高度、只在上方留黑）是错的：
	 *   会出现左右对上、但底部没有黑边、而且竖向视野偏大（角色显得小）的现象。
	 *
	 * 想恢复“铺满屏幕”：把本常量改为 0 即可（不做任何处理）。
	 */
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

	private function setupGame():Void
	{
		var stageWidth:Int = Lib.current.stage.stageWidth;
		var stageHeight:Int = Lib.current.stage.stageHeight;

		// [PE-iOS] 视口：按目标宽高比（16:9）算出可用高度，并在 stage 内垂直居中。
		// stage 会被引擎整体缩放到屏幕：
		//   stage 1024x768 → 屏幕 2224x1668（缩放 2.172），
		//   所以 stage 内 96px 的上下留白，到屏幕上就是约 208px。
		var viewHeight:Int = stageHeight;
		var yOffset:Int = 0;
		if (IOS_TARGET_ASPECT > 0)
		{
			var targetH:Int = Std.int(stageWidth / IOS_TARGET_ASPECT);
			if (targetH > 0 && targetH < stageHeight)
			{
				viewHeight = targetH;
				yOffset = Std.int((stageHeight - viewHeight) / 2);
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

		var info:String = 'stage=' + stageWidth + 'x' + stageHeight
			+ '\nviewHeight=' + viewHeight
			+ '\nyOffset=' + yOffset
			+ '\ncanvas=' + game.width + 'x' + game.height
			+ '\nzoom=' + game.zoom + '\n';
		trace('[PE-iOS] 视口(16:9 居中)：' + info.replace('\n', ' '));

		SUtil.doTheCheck();

		ClientPrefs.loadDefaultKeys();

		var flxGame:FlxGame = new FlxGame(game.width, game.height, game.initialState, #if (flixel < "5.0.0") game.zoom, #end game.framerate, game.framerate, game.skipSplash, game.startFullscreen);
		addChild(flxGame);

		// ==================== [PE-iOS] 垂直居中 + 诊断 ====================
		// 把 FlxGame 下移 yOffset（即上下各留一段黑边），前 600 帧内反复纠正，
		// 并在第 5 / 30 / 120 / 300 帧把真实数值写进 pe_ios_viewport.txt。
		if (yOffset > 0)
		{
			var frames:Int = 0;
			var applier:Event->Void = null;
			applier = function(e:Event):Void
			{
				flxGame.y = yOffset;
				frames++;

				if (frames == 5 || frames == 30 || frames == 120 || frames == 300)
				{
					try
					{
						var out:String = 'frame=' + frames + '\n'
							+ info
							+ 'FlxG=' + FlxG.width + 'x' + FlxG.height + '\n'
							+ 'cam0=' + (FlxG.camera != null ? (FlxG.camera.width + 'x' + FlxG.camera.height) : 'null') + '\n'
							+ 'game.x=' + flxGame.x + ' game.y=' + flxGame.y + '\n'
							+ 'game.scale=' + flxGame.scaleX + ',' + flxGame.scaleY + '\n'
							+ 'game.size=' + flxGame.width + 'x' + flxGame.height + '\n';
						File.saveContent(SUtil.getPath() + 'pe_ios_viewport.txt', out);
					}
					catch (err:Dynamic) {}
				}

				if (frames > 600 && Lib.current.stage != null)
					Lib.current.stage.removeEventListener(Event.ENTER_FRAME, applier);
			};
			Lib.current.stage.addEventListener(Event.ENTER_FRAME, applier);
		}

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
				DiscordClient.shutdown();
			});
		}
		#end
	}

	// Code was entirely made by sqirra-rng for their fnf engine named "Izzy Engine", big props to them!!!
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
