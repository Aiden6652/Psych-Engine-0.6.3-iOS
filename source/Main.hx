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

		// ==================== [PE-iOS] 视口：锁 16:9 + 等比居中 ====================
		// 背景（问题根因，对照上游 0.6.3 原版 setupGame()）：
		//   1) 上游在 zoom==-1 时会 `gameWidth = Math.ceil(stageWidth/zoom)`，
		//      把画布重算成「屏幕比例」。iPad 是 4:3 ⇒ 舞台变成 4:3，
		//      而模组特效/HUD 都按 16:9 设计 ⇒ 铺不满 + HUD 被裁一半。
		//   2) 上游是 `new FlxGame(..., zoom, ...)` 无条件传 zoom；
		//      本 iOS 版把它包在 `#if (flixel < "5.0.0")` 里 ⇒ flixel 5.x 下
		//      zoom 根本没传，舞台按 1280x720 原始尺寸直接贴左上角。
		//      iPad stage 是 1024x768 < 1280x720 中的宽 ⇒ 右侧/底部被裁，
		//      表现为「箭头只剩一半、血条只剩一半」。
		//
		// 修法：不依赖 FlxGame 的 zoom 参数（跨 flixel 版本行为不一致），
		//   改为「画布恒定 16:9 + 手动 scale + 居中」——
		//   本段只做数值计算，真正的 scale/x/y 在 addChild 之后统一施加。
		var canvasW:Float = game.width;                 // 1280，恒定
		var canvasH:Float = canvasW * 9.0 / 16.0;       // 720，恒定 16:9
		var viewHeight:Float = stageHeight;

		// 等比缩放系数：min ⇒ 保证画布完整放得下，宁可留黑边也不裁切
		if (game.zoom == -1.0)
			game.zoom = Math.min(stageWidth / canvasW, viewHeight / canvasH);

		// 缩放后画布的像素尺寸 + 居中偏移（黑边均分到两侧）
		var fillW:Float = canvasW * game.zoom;
		var fillH:Float = canvasH * game.zoom;
		var canvasX:Float = Math.floor((stageWidth - fillW) * 0.5);
		var canvasY:Float = Math.floor((viewHeight - fillH) * 0.5);

		// 把画布实际尺寸写回 game（供 FlxGame 构造使用；值恒为 16:9）
		game.width = Std.int(canvasW);
		game.height = Std.int(canvasH);

		var info:String = 'stage=' + stageWidth + 'x' + stageHeight
			+ '\ncanvas=' + game.width + 'x' + game.height
			+ ' (比例 ' + Math.round(canvasW / canvasH * 1000) / 1000 + ')'
			+ '\nscale=' + Math.round(game.zoom * 1000) / 1000
			+ '\nfill=' + Math.round(fillW) + 'x' + Math.round(fillH)
			+ '\nletterbox=' + Math.round(stageWidth - fillW) + 'x' + Math.round(viewHeight - fillH)
			+ '\noffset=' + canvasX + ',' + canvasY + '\n';
		trace('[PE-iOS] 视口：' + info.replace('\n', ' '));

		#if ios
		try { File.saveContent(SUtil.getPath() + 'pe_ios_viewport.txt', info); } catch (e:Dynamic) {}
		#end

		SUtil.doTheCheck();

		ClientPrefs.loadDefaultKeys();

		// ==================== [PE-iOS] FlxGame 构造 ====================
		// ⚠ 关键：Zoom 参数【传 1.0】，不传 game.zoom！
		//
		// 依据 flixel 4.11.0 源码（本项目 hmm.json 锁的就是 flixel 4.11.0）：
		//   FlxGame.new(..., Zoom, ...)  →  FlxG.init(this, W, H, Zoom)
		//   FlxG.init() 里：
		//       FlxG.initialZoom = FlxCamera.defaultZoom = Zoom;   // ← Zoom 只影响相机
		//       resizeGame(stage.stageWidth, stage.stageHeight);
		//
		// 也就是说 FlxGame 的 Zoom【不是】缩放游戏画面用的，它只被当作
		//   「每个相机默认带一个 zoom 系数」。传 game.zoom(=0.8) 进去，
		//   等于给所有相机预设了放大 ⇒ 画面 + UI 一起被推近（"放大"感来源之一）。
		//
		// 所以这里传 1.0，让相机默认缩放回归 1；
		//   画面缩放完全交给下面手动设置的 flxGame.scaleX/scaleY，
		//   这样「相机缩放」与「画布适配」两件事彻底解耦，互不干扰。
		//
		// 注：FlxGame 自己会设 stage.scaleMode = NO_SCALE / align = TOP_LEFT
		//   （flixel 4.11 FlxGame.hx 第 318-319 行），且是在构造阶段。
		//   我们在 addChild 之后覆写 align/scaleMode 与 x/y/scale，故不受影响。
		var flxGame:FlxGame = new FlxGame(game.width, game.height, game.initialState, 1.0, game.framerate, game.framerate, game.skipSplash, game.startFullscreen);
		addChild(flxGame);

		// ==================== [PE-iOS] 手动缩放 + 居中 ====================
		// 为什么不用 FlxGame 的 zoom 参数缩放画面：
		//   见上面构造处的说明 —— 那个参数只被写进 FlxCamera.defaultZoom，
		//   用它「适配屏幕」等于给所有相机预设放大，画面和 UI 会一起被推近。
		//   而 FlxGame 自己设的 stage.align=TOP_LEFT + NO_SCALE，
		//   又让 1280x720 的画布在 iPad(1024x768) 上左上对齐、右侧底部被裁。
		//
		// 做法：直接对 flxGame 这个 Sprite 施加等比 scale 并居中：
		//   scaleX/scaleY = game.zoom（min 系数，等比，不变形）
		//   x/y = 居中偏移（canvasX/canvasY，黑边两侧均分）
		// ⇒ 16:9 画布永远完整可见、居中，黑边由 stage 背景填充。
		//
		// ⚠ 用「每帧兜底」而不是一次性赋值：
		//   FlxGame 内部有 RESIZE 监听 → onResize → FlxG.resizeGame →
		//   scaleMode.onMeasure()，在某些时机（如首次真正拿到 stage 尺寸、
		//   或设备旋转）会把 scale/位置改回去。所以每帧确认一次，代价可忽略。
		var applyViewport:Void->Void = function():Void
		{
			if (flxGame.scaleX != game.zoom) flxGame.scaleX = game.zoom;
			if (flxGame.scaleY != game.zoom) flxGame.scaleY = game.zoom;
			if (flxGame.x != canvasX) flxGame.x = canvasX;
			if (flxGame.y != canvasY) flxGame.y = canvasY;
		};
		applyViewport();

		// stage 不缩放、左上角对齐 —— 我们自己在 Sprite 层面做缩放和居中
		//   （保持 NO_SCALE 可以避免 OpenFL 二次缩放导致坐标错乱）
		Lib.current.stage.align = "tl";
		Lib.current.stage.scaleMode = StageScaleMode.NO_SCALE;

		// 每帧兜底：前 300 帧内持续校正（约 5 秒，覆盖启动期各种 resize 时机）。
		//   之后若尺寸没变就自动摘掉监听，正常运行零开销。
		{
			var vpFrames:Int = 0;
			var vpApplier:Event->Void = null;
			vpApplier = function(e:Event):Void
			{
				vpFrames++;
				applyViewport();
				if (vpFrames > 300 && Lib.current.stage != null)
					Lib.current.stage.removeEventListener(Event.ENTER_FRAME, vpApplier);
			};
			Lib.current.stage.addEventListener(Event.ENTER_FRAME, vpApplier);
			trace('[PE-iOS] 视口兜底校正已挂载（前 300 帧）');
		}

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
