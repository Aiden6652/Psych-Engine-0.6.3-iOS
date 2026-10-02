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
	/** [PE-iOS] 顶部黑边比例（对齐「无视频版」画面）。202/1668 = 0.121；改成 0.0 即恢复铺满。 */
	static inline var IOS_TOP_INSET_RATIO:Float = 0.121;

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

		// 顶部黑边：扣除一段可用高度，再把整个 FlxGame 下移同样像素
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

		// 标记文件：用于确认「当前装的包到底有没有包含本改动」
		#if ios
		try
		{
			File.saveContent(SUtil.getPath() + 'pe_ios_viewport.txt',
				'stage=' + stageWidth + 'x' + stageHeight
				+ '\ntopInset=' + topInset
				+ '\ncanvas=' + game.width + 'x' + game.height
				+ '\nzoom=' + game.zoom + '\n');
		}
		catch (e:Dynamic) {}
		#end

		trace('[PE-iOS] 视口对齐无视频版：stage=' + stageWidth + 'x' + stageHeight + '，顶部黑边 ' + topInset + '，画布 ' + game.width + 'x' + game.height);

		SUtil.doTheCheck();

		ClientPrefs.loadDefaultKeys();

		var flxGame:FlxGame = new FlxGame(game.width, game.height, game.initialState, #if (flixel < "5.0.0") game.zoom, #end game.framerate, game.framerate, game.skipSplash, game.startFullscreen);
		addChild(flxGame);

		if (topInset > 0)
		{
			flxGame.y = topInset;
			// 保险：前 15 帧每帧重置一次，防止被其它代码/尺寸变化重置坐标
			var frames:Int = 0;
			var applier:Event->Void = null;
			applier = function(e:Event):Void
			{
				flxGame.y = topInset;
				frames++;
				if (frames > 15 && Lib.current.stage != null)
					Lib.current.stage.removeEventListener(Event.ENTER_FRAME, applier);
			};
			Lib.current.stage.addEventListener(Event.ENTER_FRAME, applier);
		}

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
