package;

import flixel.graphics.FlxGraphic;
import flixel.FlxG;
import flixel.FlxGame;
import flixel.FlxState;
import flixel.system.scaleModes.RatioScaleMode;   // [PE-iOS] 16:9 等比适配 + 黑边居中
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
	/**
	 * [PE-iOS] 顶部刘海/安全区占屏高的比例。
	 *
	 * 注意：**画面本身已不再做任何顶部裁切**（见 start() 里的视口段落）。
	 * 本常量现在只用于一件事：给 FPS 计数器之类的浮动 HUD 让开刘海区。
	 * 色带贴底由 FlxHitbox / Controls 各自处理。
	 *
	 * 实测参照（iPad Pro 11"，屏幕 2420x1668，stage 1024x768）：
	 *   无视频版：顶部留黑 ≈ 202px（屏幕坐标）。
	 *   换算到 stage：202 / 2.172 ≈ 92px，即 768 的 12.1%。
	 */
	static inline var IOS_TOP_INSET_RATIO:Float = 0.121;

	// ==================== [PE-iOS] 画布定义 ====================
	// width/height 恒为 1280x720（16:9）—— 这是全局唯一真相源：
	//   · 它们被传给 `new FlxGame(...)` → FlxG.initialWidth/initialHeight
	//   · BaseScaleMode.onMeasure() 每次都把 FlxG.width/height 重置回这两个值
	//   · RatioScaleMode 按 FlxG.width/height 的【比例】(=16:9) 适配屏幕
	//   · 相机视口（camGame/camHUD）也取 FlxG.width/height
	// ⇒ 只要这里是 16:9，全链路就是 16:9。
	//
	// ⚠ zoom 字段已【不再使用】：原版用它同时充当「FlxGame 的 Zoom 参数」，
	//   但那个参数实际只写进 FlxCamera.defaultZoom（见构造处说明），
	//   拿它做屏幕适配会污染 initialZoom。现在固定传 1.0，此字段仅作历史保留。
	//   屏幕适配统一交给 RatioScaleMode。
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
				// 用 Math.min（等比缩放到「完整放得下」）：不放大、不裁切。
				// 之前用 Math.max 是「铺满画布」策略，会把画面放大并裁掉边缘
				// —— 这正是用户反馈的「视频被放大」的来源之一。
				// 视频本来就该完整显示，宁可留黑边也不要放大。
				var sc:Float = Math.min(FlxG.width / w, FlxG.height / h);
				if (sc <= 0 || sc != sc) sc = 1;
				Reflect.setProperty(c, 'scaleX', sc);
				Reflect.setProperty(c, 'scaleY', sc);
				Reflect.setProperty(c, 'x', (FlxG.width - w * sc) / 2);
				Reflect.setProperty(c, 'y', (FlxG.height - h * sc) / 2);
				report.add('[' + i + '] ' + cn + ' bmd=' + w + 'x' + h + ' -> scale=' + sc + ' (min/等比完整)\n');
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
		// ==================== [PE-iOS] 视频渲染路径 ====================
		// 必须走 CPU 位图路径（Video.useTexture = false）：
		//   hxvlc 默认的 GPU 纹理路径在「多相机」场景（打歌 / 过场 substate）下不出图，
		//   实测表现就是「有声音、没画面」；而 intro.mp4 挂在单相机的 TitleState 上，
		//   所以它在 GPU 路径下能正常显示 —— 这也解释了「只有 intro 正常」的现象。
		//   切到 CPU 位图路径后，过场视频（hxcodec 兼容层 VideoHandler）才能出画面。
		//
		// 代价：每帧多拷一份视频帧（1080p 约 8MB）到内存。
		//   之前担心它造成随机卡顿，但那只是推测（未坐实），而「过场视频没画面」是确定的问题，
		//   两害相权取其轻 —— 先保证画面能出来。
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

		// ==================== [PE-iOS] 视口：锁定 16:9（交给 RatioScaleMode）====================
		//
		// ── 根因（对照上游 0.6.3 原版 setupGame()）────────────────────────
		// 上游在 zoom == -1 时：
		//     zoom       = Math.min(stageWidth / gameWidth, stageHeight / gameHeight);
		//     gameWidth  = Math.ceil(stageWidth / zoom);
		//     gameHeight = Math.ceil(stageHeight / zoom);
		// 这两行把画布重算成【屏幕比例】。iPad 是 4:3 ⇒ gameWidth:gameHeight = 4:3。
		//
		// 而 HaxeFlixel 的默认缩放模式 RatioScaleMode（FlxG.hx 第 179 行
		// `scaleMode = new RatioScaleMode()`）是按 `FlxG.width/FlxG.height`
		// 这个【比例】去适配屏幕的：
		//     ratio = FlxG.width / FlxG.height            // 4:3 = 1.3333
		//     realRatio = stageWidth / stageHeight        // 1024/768 = 1.3333
		//     ⇒ 两者相等 ⇒ 整屏铺满、不加黑边
		//     ⇒ 相机视口就是 4:3
		//
		// ⇒ 模组特效按 16:9 设计 ⇒ 在 4:3 视口里【铺不满】。
		//    这就是「不是 16:9」的唯一根因。
		//
		// ── 修法：只做一件事 —— 把画布锁回 16:9 ──────────────────────────
		// 不再自己算 scale / 自己居中（那是重复劳动，而且会和 Flixel 打架：
		//   BaseScaleMode.updateGamePosition() 第 92-93 行会
		//   `FlxG.game.x = offset.x; FlxG.game.y = offset.y;` 自己居中）。
		//
		// 只要让 FlxG.width/height = 1280:720，RatioScaleMode 就会自动算：
		//   ratio = 1.7778 > realRatio = 1.3333
		//   ⇒ 按宽度适配：gameSize = 1024 x 576（标准 16:9）
		//   ⇒ 等比 scale、上下黑边、自动居中
		// 完全是 Flixel 原生行为，零手写适配代码。
		//
		// FlxG.width/height 的来源：BaseScaleMode.onMeasure() 第 34-35 行
		//   `FlxG.width = FlxG.initialWidth; FlxG.height = FlxG.initialHeight;`
		// 而 initialWidth/Height 就是 `new FlxGame(game.width, game.height, ...)`
		// 传进去的那两个值。所以下面把 game.width/height 钉死即可。
		game.width = 1280;
		game.height = 720;   // 1280 : 720 = 16 : 9

		// 若 build 配置或外部改动把比例弄坏了，这里兜底纠正
		if (Math.abs(game.width / game.height - 16.0 / 9.0) > 0.001)
		{
			trace('[PE-iOS] 画布比例异常（' + game.width + 'x' + game.height + '），已纠正为 1280x720');
			game.width = 1280;
			game.height = 720;
		}

		var info:String = 'stage=' + stageWidth + 'x' + stageHeight
			+ '\ncanvas=' + game.width + 'x' + game.height
			+ '\ncanvasRatio=' + Math.round(game.width / game.height * 10000) / 10000
			+ '\nstageRatio=' + Math.round(stageWidth / stageHeight * 10000) / 10000
			+ '\n（RatioScaleMode 将按 canvasRatio 适配并自动加黑边居中）\n';
		trace('[PE-iOS] 视口：' + info.replace('\n', ' '));

		#if ios
		try { File.saveContent(SUtil.getPath() + 'pe_ios_viewport.txt', info); } catch (e:Dynamic) {}
		#end

		SUtil.doTheCheck();

		ClientPrefs.loadDefaultKeys();

		// ==================== [PE-iOS] FlxGame 构造 ====================
		// ⚠ Zoom 参数【传 1.0】，不传 game.zoom —— 两个原因：
		//
		// (1) 依据 flixel 4.11.0 源码（本项目 hmm.json 锁的就是 4.11.0）：
		//       FlxGame.new(..., Zoom, ...)  →  FlxG.init(this, W, H, Zoom)
		//       FlxG.init() 第 584 行：
		//           FlxG.initialZoom = FlxCamera.defaultZoom = Zoom;
		//     也就是说这个 Zoom【不是】用来适配屏幕的，它只是
		//       「每个相机的默认缩放系数」。
		//     传 game.zoom(≈0.8) 进去 = 给所有相机预设放大
		//       ⇒ 画面 + UI 一起被推近（「放大」感的来源之一）。
		//
		// (2) 更关键：BaseScaleMode 算屏幕适配时用的是
		//       scale.x = gameSize.x / (FlxG.width  * FlxG.initialZoom)
		//       scale.y = gameSize.y / (FlxG.height * FlxG.initialZoom)
		//     initialZoom 若掺进一个「为了适配屏幕而算出来的数」，
		//     会和 gameSize 的适配计算互相抵消/打架，缩放结果不可预期。
		//     传 1.0 让 initialZoom 保持中性，适配完全由 RatioScaleMode 负责。
		//
		// 结论：initialZoom 归 1，画布比例归 16:9，屏幕适配归 RatioScaleMode。
		//       三件事各司其职，不重叠、不打架。
		var flxGame:FlxGame = new FlxGame(game.width, game.height, game.initialState, 1.0, game.framerate, game.framerate, game.skipSplash, game.startFullscreen);
		addChild(flxGame);

		// ==================== [PE-iOS] 屏幕适配：交给 RatioScaleMode ====================
		// 不再手写 scaleX/scaleY/x/y —— 那是重复劳动，而且会被 Flixel 覆盖：
		//   BaseScaleMode.updateGamePosition()（BaseScaleMode.hx 第 92-93 行）：
		//       FlxG.game.x = offset.x;
		//       FlxG.game.y = offset.y;
		//   Flixel 每帧/每次 resize 都会自己给 FlxGame 设居中偏移。
		//
		// FlxG.scaleMode 默认就是 `new RatioScaleMode()`（FlxG.hx 第 179 行），
		// 行为：
		//   用 FlxG.width/FlxG.height 的比例（现在是 1280:720 = 16:9）去适配屏幕，
		//   按需加黑边、等比缩放、自动居中。
		//
		// 这里显式再设一次（幂等），并确保它是「显示全部（不裁切）」那种：
		//   RatioScaleMode(false)  = 完整显示 + 黑边（我们要的）
		//   RatioScaleMode(true)   = 裁掉多余边、铺满屏幕（不要）
		var ratioMode:RatioScaleMode = new RatioScaleMode(false);
		FlxG.scaleMode = ratioMode;
		trace('[PE-iOS] 适配模式：RatioScaleMode(fillScreen=false) —— 完整显示 + 黑边');

		// stage 保持 FlxGame 设的 NO_SCALE / TOP_LEFT 即可：
		//   缩放和居中由 scaleMode 在 Sprite 层完成，stage 本身不缩放。
		//   （FlxGame 构造时已设，这里显式重复一次以防被外部改动。）
		Lib.current.stage.align = "tl";
		Lib.current.stage.scaleMode = StageScaleMode.NO_SCALE;

		// 视频 Bitmap 尺寸纠正（无视频时内部会直接跳过，不产生开销）
		Lib.current.stage.addEventListener(Event.ENTER_FRAME, function(e:Event):Void
		{
			scanFrames++;
			if (scanFrames % 12 == 0)
				scaleVideoBitmaps();
		});

		fpsVar = new FPS(10, 3, 0xFFFFFF);
		// [PE-iOS] 不再用已删除的 yOffset。FPS 计数器直接避开顶部刘海区，
		//   用常量比例算一个固定下移量（画面本身是完全居中的，不受影响）。
		{
			var hudInset:Int = Std.int(Lib.current.stage.stageHeight * IOS_TOP_INSET_RATIO);
			if (hudInset > 6)
				fpsVar.y = hudInset - 3;
		}
		addChild(fpsVar);
		// align/scaleMode 已在上面统一设置（NO_SCALE + tl），此处不再重复。
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
