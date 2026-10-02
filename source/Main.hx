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
	 * iPad Pro 11" 屏幕是 2420x1668（比例 1.45），而游戏画面是 16:9（1.78），
	 * 所以在竖黑边的意义上，画面必然上下留黑（而非“顶部刻意让出一段”）：
	 *   画面宽 2220 → 高 1249（=2220*9/16），垂直居中 →
	 *   上下各留 ≈ 209px、左右各 100px。
	 *
	 * 想恢复“铺满屏幕”：把本常量改为 0 即可。
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

		// [PE-iOS] 只决定「画布多大（即缩放倍数）」，居中交给 HaxeFlixel 自己处理。
		//
		// 踩坑记录：之前在这里额外做了 `flxGame.y = 偏移量`，想自己把画面推到中间，
		// 但 FlxGame 内部本来就会按缩放比例把自己居中 → 双重偏移 →
		// 画面被推下去、底部被裁掉，表现为「打歌时像放大了一样」、
		// hitbox 底部的颜色条看着“跑到中间”、大特效盖不住全屏。
		// 所以本版起：不碰 flxGame.x / flxGame.y，只算尺寸。
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

		SUtil.doTheCheck();

		ClientPrefs.loadDefaultKeys();

		var flxGame:FlxGame = new FlxGame(game.width, game.height, game.initialState, #if (flixel < "5.0.0") game.zoom, #end game.framerate, game.framerate, game.skipSplash, game.startFullscreen);
		addChild(flxGame);

		// 诊断：在第 5 / 30 / 120 / 300 帧记录真实数值（含 FlxGame 自己的 x/y/scale）。
		// 下次有任何“黑边不对/被裁”的问题，看这个文件即可，不用猜。
		{
			var frames:Int = 0;
			var applier:Event->Void = null;
			applier = function(e:Event):Void
			{
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

				if (frames > 300 && Lib.current.stage != null)
					Lib.current.stage.removeEventListener(Event.ENTER_FRAME, applier);
			};
			Lib.current.stage.addEventListener(Event.ENTER_FRAME, applier);
		}

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
