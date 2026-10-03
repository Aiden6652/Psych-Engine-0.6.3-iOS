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
	 * [PE-iOS] 顶部黑边比例（对齐「无视频版」画面）。
	 *
	 * 实测参照（iPad Pro 11"，屏幕 2420x1668，stage 1024x768）：
	 *   无视频版：顶部留黑 ≈ 202px（屏幕坐标），【内容一直蓴到屏幕最底部】。
	 *   换算到 stage：202 / 2.172 ≈ 92px，即 768 的 12.1%。
	 *
	 * ⚠ 为什么不能用「16:9 居中」：
	 *   居中会把画面上下各留一半黑边，画布底部就离屏幕底部 208px，
	 *   结果手机触控色带（画在画布底部）会悬在半空、不在屏幕最下方。
	 *   所以这里采用「顶部留黑 + 内容贴底」，与无视频版一致。
	 *
	 * 想恢复“铺满屏幕”：把本常量改为 0。
	 */
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
	// hxvlc 内部会把视频帧写进一个原始 Bitmap（hxvlc.openfl.Video，继承 openfl.display.Bitmap），
	// 并 addChild 到 FlxG.game 上；它的尺寸是【视频原始分辨率】（如 1920x1080），
	// 而游戏画布只有 1280x720 → 它比画布大 1.5 倍，表现出来就是“视频被放大了”。
	//
	// 这里每 12 帧把这个 Bitmap 的缩放对到画布大小（只改尺寸，不动 visible，
	// 避免误伤真正在显示的那条路径），并写诊断文件。
	private function scaleVideoBitmaps():Void
	{
		#if (VIDEOS_ALLOWED && ios)
		var g = FlxG.game;
		if (g == null) return;

		var report:StringBuf = new StringBuf();
		var found:Int = 0;

		for (i in 0...g.numChildren)
		{
			var c = g.getChildAt(i);
			if (c == null || !Std.isOfType(c, Bitmap)) continue;

			var cn:String = '';
			try { cn = Type.getClassName(Type.getClass(c)); } catch (e:Dynamic) {}
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
				report.add('[' + i + '] ' + cn + ' w=' + w + ' h=' + h + '（无帧数据）\n');
				continue;
			}

			try
			{
				// 只做「缩放到画布」：与 FlxSprite 的铺满策略一致（保持比例、居中裁切）
				var sc:Float = Math.max(FlxG.width / w, FlxG.height / h);
				if (sc <= 0 || sc != sc) sc = 1;
				Reflect.setProperty(c, 'scaleX', sc);
				Reflect.setProperty(c, 'scaleY', sc);
				// 居中：让放大后的内容围绕画布中心
				Reflect.setProperty(c, 'x', (FlxG.width - w * sc) / 2);
				Reflect.setProperty(c, 'y', (FlxG.height - h * sc) / 2);

				var nsx:Float = Reflect.getProperty(c, 'scaleX');
				report.add('[' + i + '] ' + cn + ' bmd=' + w + 'x' + h + ' -> scale=' + nsx + '\n');
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
		// ==================== [PE-iOS] 视频渲染路径 ====================
		// hxvlc 默认走 GPU 纹理输出帧；实测打歌场景不出图，这里统一改走 CPU 位图路径。
		#if (VIDEOS_ALLOWED && ios)
		try
		{
			hxvlc.openfl.Video.useTexture = false;
			trace('[PE-iOS] 视频渲染：已切换为 CPU 位图路径 (Video.useTexture=false)');
		}
		catch (e:Dynamic)
		{
			trace('[PE-iOS] 切换视频渲染路径失败（已忽略）: ' + e);
		}
		#end

		var stageWidth:Int = Lib.current.stage.stageWidth;
		var stageHeight:Int = Lib.current.stage.stageHeight;

		// 顶部留黑 + 内容贴底（对齐无视频版；同时保证触控色带落在屏幕最下方）
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

		var info:String = 'stage=' + stageWidth + 'x' + stageHeight
			+ '\ntopInset=' + topInset
			+ '\nviewHeight=' + viewHeight
			+ '\ncanvas=' + game.width + 'x' + game.height
			+ '\nzoom=' + game.zoom + '\n';
		trace('[PE-iOS] 视口(顶部留黑+贴底)：' + info.replace('\n', ' '));

		#if ios
		try { File.saveContent(SUtil.getPath() + 'pe_ios_viewport.txt', info); } catch (e:Dynamic) {}
		#end

		SUtil.doTheCheck();

		ClientPrefs.loadDefaultKeys();

		var flxGame:FlxGame = new FlxGame(game.width, game.height, game.initialState, #if (flixel < "5.0.0") game.zoom, #end game.framerate, game.framerate, game.skipSplash, game.startFullscreen);
		addChild(flxGame);

		// ★ 贴底：FlxGame 自己会把画面居中（算出 y=topInset/2），
		// 这里把它覆写成 topInset，让内容一直蓴到 stage 底部（=> 屏幕上也就贴底了）。
		// 注意是【直接赋值】而不是累加，所以不存在双重偏移。
		if (topInset > 0)
		{
			flxGame.y = topInset;
			var frames:Int = 0;
			var applier:Event->Void = null;
			applier = function(e:Event):Void
			{
				flxGame.y = topInset;
				frames++;
				if (frames > 60 && Lib.current.stage != null)
					Lib.current.stage.removeEventListener(Event.ENTER_FRAME, applier);
			};
			Lib.current.stage.addEventListener(Event.ENTER_FRAME, applier);
		}

		// 每 12 帧把 hxvlc 的原始视频 Bitmap 缩放到画布大小（修“视频被放大”）
		Lib.current.stage.addEventListener(Event.ENTER_FRAME, function(e:Event):Void
		{
			scanFrames++;
			if (scanFrames % 12 == 0)
				scaleVideoBitmaps();
		});

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
