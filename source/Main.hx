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
	 * [PE-iOS] 顶部黑边比例（用于对齐「无视频版」画面）。
	 *
	 * 背景：实测两版 IPA 在同一台 iPad（2420x1668）上对比——
	 *   有视频版：游戏视口 2220x1668（铺满整屏高）→ 内部画布 1280x962，角色显得小；
	 *   无视频版：游戏视口 2220x1465（顶部留 202px 黑边）→ 画布 1280x845，角色更大更「近」。
	 * 两版缩放倍数相同（1.734x），差别只在视口高度，所以只要把顶部按比例压掉一段，
	 * 就能得到与无视频版完全一致（含黑边）的画面。
	 *
	 * 202 / 1668 = 0.121（即视口占屏高 87.9%）。
	 * 想恢复成铺满屏幕：把本常量改成 0.0 即可（无需改其它代码）。
	 */
	static inline var IOS_TOP_INSET_RATIO:Float = 0.121;

	var game = {
		width: 1280, // WINDOW width
		height: 720, // WINDOW height
		initialState: TitleState, // initial game state
		zoom: -1.0, // game state bounds
		framerate: 60, // default framerate
		skipSplash: true, // if the default flixel splash screen should be skipped
		startFullscreen: true // if the game should start at fullscreen mode
	};

	public static var fpsVar:FPS;

	// You can pretty much ignore everything from here on - your code should go in your states.

	public static function main():Void
	{
		Lib.current.addChild(new Main());
	}

	public function new()
	{
		super();

    SUtil.gameCrashCheck();
		if (stage != null)
		{
			init();
		}
		else
		{
			addEventListener(Event.ADDED_TO_STAGE, init);
		}
	}

	private function init(?E:Event):Void
	{
		if (hasEventListener(Event.ADDED_TO_STAGE))
		{
			removeEventListener(Event.ADDED_TO_STAGE, init);
		}

		setupGame();
	}

	private function setupGame():Void
	{
		var stageWidth:Int = Lib.current.stage.stageWidth;
		var stageHeight:Int = Lib.current.stage.stageHeight;

		// [PE-iOS] 顶部黑边（对齐无视频版画面）：
		// 把可用高度扣除一段，再按「可用高度」算缩放与画布高度，
		// 最后将整个 FlxGame 下移同样像素，顶部就自然露出黑边。
		var topInset:Int = 0;
		var viewHeight:Int = stageHeight;
		if (IOS_TOP_INSET_RATIO > 0)
		{
			topInset = Std.int(stageHeight * IOS_TOP_INSET_RATIO);
			viewHeight = stageHeight - topInset;
			if (viewHeight < 1) viewHeight = stageHeight;
			trace('[PE-iOS] 视口对齐无视频版：屏高 ' + stageHeight + ' → 顶部黑边 ' + topInset + '，可用高 ' + viewHeight);
		}

		if (game.zoom == -1.0)
		{
			var ratioX:Float = stageWidth / game.width;
			var ratioY:Float = viewHeight / game.height;
			game.zoom = Math.min(ratioX, ratioY);
			game.width = Math.ceil(stageWidth / game.zoom);
			game.height = Math.ceil(viewHeight / game.zoom);
		}
	
			SUtil.doTheCheck();
	
		ClientPrefs.loadDefaultKeys();

		// 用变量接收 FlxGame 以便设置 y 偏移（顶部黑边）
		var flxGame:FlxGame = new FlxGame(game.width, game.height, game.initialState, #if (flixel < "5.0.0") game.zoom, #end game.framerate, game.framerate, game.skipSplash, game.startFullscreen);
		if (topInset > 0)
			flxGame.y = topInset;
		addChild(flxGame);

		fpsVar = new FPS(10, 3, 0xFFFFFF);
		if (topInset > 0)
			fpsVar.y = topInset + 3;
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
	// very cool person for real they don't get enough credit for their work
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
