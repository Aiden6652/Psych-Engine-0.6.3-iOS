package hxcodec;

#if (VIDEOS_ALLOWED && (ios || android))
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.util.FlxTimer;
import hxvlc.flixel.FlxVideoSprite;
import sys.FileSystem;
import sys.io.File;

/**
 * [PE-iOS] hxCodec 兼容层 —— 把 hxCodec 的调用【翻译】成 hxvlc 的操作。
 *
 * ── 定位：这是一层「翻译器」，不是一套独立实现 ──────────────────────────
 * 老模组调用的是 hxCodec 的 API，契约极简（三个动作）：
 *
 *     var video = new MP4Handler();        // ① 造对象（无参构造）
 *     video.playVideo(filepath);           // ② 播放（画面从这一刻开始出）
 *     video.finishCallback = function(){}; // ③ 播完回调
 *
 * 模组【不会】自己 addChild / openSubState —— 挂载必须由 playVideo() 完成。
 * 本层把这些调用翻译成 hxvlc 的 `FlxVideoSprite` 操作，接口保持与 hxCodec 一致，
 * 这样任何模组都不用改代码。
 *
 * ── ★★ 本版架构（彻底换掉 substate 方案）★★ ─────────────────────────
 *
 *   【旧方案失败】本类曾是 `FlxSubState`，需要 `openSubState(this)` 才能进
 *   FlxG 的更新/绘制链。实测在本项目里这条路反复失败（不进链 ⇒ 黑屏 +
 *   不回调 + 不更新），是过场黑屏折腾 7+ 轮的真正原因。
 *
 *   【新方案：复刻 intro】intro 之所以一直稳，是因为它的写法极简且正确：
 *       var vs = new FlxVideoSprite();
 *       add(vs);                       // ← 挂在 FlxState 上，被正常绘制
 *   所以现在：
 *     · 本类 = 不可见的 `FlxSprite`【控制器】（拿回调、计时、跳过），
 *     · 真正的视频 sprite 由 `playVideo()` 直接 `FlxG.state.add(video)`，
 *       与 intro 完全同一种挂法，不再依赖 substate 机制。
 *
 * ⚠ hxvlc 版本要求：**1.9.3**
 *   1.7/1.8.x 没有 GPU 渲染路径（视频帧出不来），
 *   1.9.4+ 又用了 Haxe 4.3 的 `?.` 语法（本仓库 Haxe 4.2.4 编不过）。
 *
 * ── 已修掉的坑（全部有日志/源码依据）────────────────────────────────────
 *   ① 【黑屏】旧 substate 方案从未真正进更新/绘制链 ⇒ 改为直接挂 FlxG.state。
 *   ② 【偏右/被裁】曾把 video.cameras 指定成 FlxG.cameras.list 的【最后一个】，
 *      那不是 camGame ⇒ 画到别的视口。现改为不指定，与 intro 对齐。
 *   ③ 【不居中】缩放基准曾用 FlxG.width（实测该值在回调触发时不稳定），
 *      现改用相机视口 cam.width/height。
 *   ④ 【一播就过】iOS 上 mouse/touches 会误判 justPressed ⇒ 门槛提高到 1.5s
 *      且要求 justPressed && pressed 双重确认。
 *   ⑤ 时长解析增加 Int64.low 兜底，避免 parseFloat 失败变 0 秒。
 */
class VideoHandler extends FlxSprite
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
	private var diagFrame:Int = 0;
	/** [PE-iOS] 已播放秒数，用于「onEndReached 不触发」的超时兜底 */
	private var playElapsed:Float = 0;
	/** [PE-iOS] 视频时长（秒），由 bitmap.onLengthChanged 填充；0 = 未知 */
	private var videoDurSec:Float = 0;

	/**
	 * [PE-iOS] 过场视频的「最小播放时长」门槛（秒）。
	 *
	 * 与 TitleState.MIN_INTRO_SECONDS 同一套逻辑：iOS 上 hxvlc 可能过早
	 * 派发 onEndReached / onLengthChanged，导致过场刚播 1 秒就被收尾。
	 * 低于此值的一律视为误报。
	 */
	static inline var MIN_PLAY_SECONDS:Float = 2.5;
	/** [PE-iOS] 视频 sprite 被挂到了哪个 state 上（收尾时要从它身上摘掉） */
	private var hostState:flixel.FlxState = null;

	/**
	 * [PE-iOS] 自动兜底激活标记。
	 *
	 * 默认 false：内层 Bitmap 保持隐藏（正确状态，避免与 FlxSprite 重叠 → 偏右/被裁）。
	 * 仅当 autoFallbackTimer 判定「FlxSprite 正路确实没出画面」时置 true，
	 * 此时 Main.hx 的 ensureVideoBitmapVisible() 会停止强行隐藏它（避免反复横跳闪烁）。
	 */
	public static var PEI_VIDEO_FALLBACK_ACTIVE:Bool = false;

	public function new():Void
	{
		super();

		// ★★★ [PE-iOS] 本类【不再是 FlxSubState】，而是一个不可见的 FlxSprite 控制器 ★★★
		//
		//   为什么改：hxCodec 的契约要求 `new MP4Handler()` 后调 `playVideo()` 就能出画面，
		//   而 substate 方案要求我们主动 openSubState(this) —— 那条路在本项目里
		//   反复失败（substate 不进 FlxG 的更新/绘制链 ⇒ 黑屏）。
		//
		//   现改为【复刻 intro 的挂载方式】：intro 之所以稳，是因为它：
		//       var vs = new FlxVideoSprite();
		//       add(vs);            // ← 加在 FlxState 上，被正常绘制
		//   所以这里也把真正的视频 sprite 直接挂到 FlxG.state（见 playVideo）。
		//
		//   本对象自己只是「控制器」：持有回调、计时、处理跳过，不参与绘制。
		this.visible = false;          // 控制器本身不画
		this.alpha = 0;
		try { this.scrollFactor.set(0, 0); } catch (e:Dynamic) {}
	}

	// ==================== 🩺 诊断写盘 ====================
	static function diag(line:String):Void
	{
		try
		{
			var p:String = SUtil.getPath() + 'pe_ios_video.txt';
			var old:String = '';
			if (FileSystem.exists(p))
			{
				try { old = File.getContent(p); } catch (e:Dynamic) { old = ''; }
				var lines:Array<String> = old.split('\n');
				if (lines.length > 120) old = lines.slice(lines.length - 120, lines.length).join('\n') + '\n';
			}
			File.saveContent(p, old + line + '\n');
		}
		catch (e:Dynamic) {}
	}

	/// 把 hxvlc 内部那个「原始 Bitmap」（真正输出视频帧的对象）的状态记下来。
	/// 它才是画面能不能出来的关键：FlxSprite 只是从它的 bitmapData 拷了一份。
	static function diagRawBitmap(tag:String, v:FlxVideoSprite):Void
	{
		if (v == null)
		{
			diag('[raw:' + tag + '] video 为 null');
			return;
		}
		var b = v.bitmap;
		if (b == null)
		{
			diag('[raw:' + tag + '] bitmap 为 null');
			return;
		}

		var parentStr:String = 'null';
		try
		{
			if (b.parent != null) parentStr = 'yes';
		}
		catch (e:Dynamic) { parentStr = 'err'; }

		var bmdStr:String = 'null';
		try
		{
			if (b.bitmapData != null) bmdStr = b.bitmapData.width + 'x' + b.bitmapData.height;
		}
		catch (e:Dynamic) { bmdStr = 'err'; }

		diag('[raw:' + tag + '] visible=' + b.visible + ' alpha=' + b.alpha
			+ ' x=' + b.x + ' y=' + b.y
			+ ' w=' + b.width + ' h=' + b.height
			+ ' scale=' + b.scaleX + ',' + b.scaleY
			+ ' parent=' + parentStr + ' bmd=' + bmdStr
			+ ' flixVisible=' + v.visible + ' flixAlpha=' + v.alpha);
	}

	/**
	 * [PE-iOS] 全坐标系快照 —— 用于定位「视频偏右 / 不居中」。
	 *
	 * 偏右这件事，根因只可能在下列几种坐标系之一，所以一次性全打出来：
	 *   1) sprite 自己的 x/y/width/height/scale/offset（相对相机视口）
	 *   2) sprite 所属相机的 x/y/width/height/scroll（视口与滚动）
	 *   3) FlxG.width/height（逻辑画布）
	 *   4) FlxG.game.x/y/scaleX/scaleY（RatioScaleMode 施加的偏移与缩放）
	 *   5) 内层 Bitmap 的 x/y/width/height/scale（直显路径才相关）
	 *   对比 (1) 与 (3)：若 sprite.x == 0 但画面仍偏右，问题在 (2) 或 (4)。
	 */
	static function diagCoords(tag:String, v:FlxVideoSprite):Void
	{
		if (v == null) { diag('[coord:' + tag + '] video=null'); return; }
		try
		{
			var s:String = '[coord:' + tag + ']'
				+ ' spr(x=' + Std.string(v.x) + ',y=' + Std.string(v.y)
				+ ',w=' + Std.string(v.width) + ',h=' + Std.string(v.height)
				+ ',sx=' + Std.string(v.scale.x) + ',sy=' + Std.string(v.scale.y)
				+ ',ox=' + Std.string(v.offset.x) + ',oy=' + Std.string(v.offset.y) + ')'
				+ ' FlxG(' + FlxG.width + 'x' + FlxG.height + ')';

			// ★★★ [PE-iOS] 决定性诊断：FlxSprite.draw() 的三个「提前 return」条件 ★★★
			//
			//   源码依据（flixel 4.11.0 FlxSprite.hx:664 起）：
			//       override public function draw():Void
			//       {
			//           checkEmptyFrame();
			//           if (alpha == 0 || _frame.type == FlxFrameType.EMPTY)
			//               return;                      // ← 条件A：alpha / 空帧
			//           ...
			//           for (camera in cameras)
			//           {
			//               if (!camera.visible || !camera.exists
			//                   || !isOnScreen(camera)) continue;   // ← 条件B
			//               ...
			//           }
			//       }
			//
			//   只要命中任一条件，视频 sprite 就【完全不画】—— 而声音走的是
			//   libVLC 的音频回调（与绘制链无关），于是表现为【有声音、没画面】。
			//   把这三项直接打出来，一次就能确认到底卡在哪一条。
			s += ' sprite(alpha=' + Std.string(v.alpha)
				+ ' vis=' + v.visible
				+ ' exists=' + v.exists
				+ ' frameType=' + Std.string(Reflect.field(v, '_frame'))
				+ ' hasGfx=' + (Reflect.field(v, 'graphic') != null) + ')';

			var fl:Dynamic = Reflect.field(v, '_frame');
			if (fl != null)
			{
				var ft:Dynamic = Reflect.field(fl, 'type');
				s += ' frame.type=' + Std.string(ft)
					+ ' frame.size=' + Std.string(Reflect.field(fl, 'sourceSize'));
			}
			try { s += ' camCount=' + (v.cameras == null ? -1 : v.cameras.length); }
			catch (e:Dynamic) { s += ' camCount=?'; }

			var g:Dynamic = FlxG.game;
			if (g != null)
			{
				s += ' game(x=' + Std.string(Reflect.getProperty(g, 'x'))
					+ ',y=' + Std.string(Reflect.getProperty(g, 'y'))
					+ ',sx=' + Std.string(Reflect.getProperty(g, 'scaleX'))
					+ ',sy=' + Std.string(Reflect.getProperty(g, 'scaleY')) + ')';
			}

			if (v.cameras != null && v.cameras.length > 0 && v.cameras[0] != null)
			{
				var c = v.cameras[0];
				s += ' cam(' + Std.string(c.x) + ',' + Std.string(c.y)
					+ ' ' + c.width + 'x' + c.height
					+ ' z=' + Std.string(c.zoom)
					+ ' sc=' + Std.string(c.scroll.x) + ',' + Std.string(c.scroll.y) + ')';
			}
			else s += ' cam(无)';

			if (v.bitmap != null)
			{
				var b = v.bitmap;
				s += ' bmp(' + Std.string(b.x) + ',' + Std.string(b.y)
					+ ' ' + Std.string(b.width) + 'x' + Std.string(b.height)
					+ ' s=' + Std.string(b.scaleX) + ' vis=' + b.visible + ')';
			}

			diag(s);
		}
		catch (e:Dynamic) { diag('[coord:' + tag + '] 快照失败: ' + e); }
	}

	/** 播放一个视频。path 可以是绝对路径，也可以是相对游戏目录的路径。 */
	public function playVideo(path:String, ?shouldLoop:Bool = false, ?canSkipIt:Bool = true):Void
	{
		if (path == null || path.length < 1)
		{
			diag('[playVideo] 收到空路径，跳过');
			// ★ 不要在这里直接 onVideoFinished()。
			//   模组侧的调用顺序是：
			//       var video = new MP4Handler();
			//       video.playVideo(filepath);          // ← 先播放
			//       video.finishCallback = function(){};// ← 后设回调
			//   若 playVideo 内部【同步】走到 onVideoFinished()，此时
			//   finishCallback 还是 null ⇒ 回调丢失 ⇒ 剧情卡死（inCutscene
			//   永远为 true，startAndEnd() 永不执行）。
			//   统一延迟一拍，保证调用方有机会先把 finishCallback 赋上。
			deferFinish();
			return;
		}

		loop = shouldLoop;
		canSkip = canSkipIt;
		videoPath = resolvePath(path);
		var fileExists:Bool = FileSystem.exists(videoPath);
		diag('[playVideo] 请求=' + path + ' 解析后=' + videoPath + ' 存在=' + fileExists);

		video = new FlxVideoSprite();
		video.antialiasing = false;

		// 钉在屏幕上，不受相机滚动/缩放影响
		video.scrollFactor.set(0, 0);

		// ★★★ [PE-iOS] 关键修正：与 intro 保持一致 —— 【不手动指定相机】 ★★★
		//
		//   旧代码在这里把 video.cameras 指定成 `FlxG.cameras.list` 的【最后一个】：
		//       video.cameras = [cams[cams.length - 1]];
		//   但 FlxG.cameras.list 的最后一个【不是 camGame】—— PlayState 里
		//   通常还有 HUD 相机或其它附加相机，它们的视口/滚动与 camGame 不同。
		//
		//   FlxSubState 里的 sprite 默认走父 state 的默认相机链（camGame），
		//   而 intro（TitleState 里 `add(vs)`、不指定相机）正是这么做的 —— 所以
		//   intro 能正常出画面。把过场也交给「最后一个相机」就等于把它画到
		//   另一个视口里 ⇒ 出画外 ⇒ **看着像黑屏**。
		//
		//   ⇒ 结论：不指定相机，与 intro 完全对齐。
		//   （scrollFactor=0 已保证不受滚动影响；缩放居中在 onFormatSetup 里做。）
		try
		{
			// 仅记录，不修改：便于日志确认默认相机是哪一个。
			diag('[camera] 不指定相机（与 intro 对齐）；当前相机数=' + FlxG.cameras.list.length);
		}
		catch (e:Dynamic) {}

		// ★★★ [PE-iOS] ★★★ 关键：复刻 intro 的挂载方式 ★★★
		//
		//   intro 稳，是因为它在 FlxState 里 `add(vs)` —— 视频 sprite 成为
		//   state 的直接成员，被正常 update/draw。
		//
		//   本类不再是 substate，所以这里也要把【视频 sprite】直接挂到
		//   `FlxG.state` 上（而不是挂到 this 这个控制器上 —— 控制器不在显示树里）。
		//
		//   同时把【控制器自己】也挂到 FlxG.state，这样它的 update() 才会跑
		//   （计时、跳过检测、超时兜底都在 update 里）。
		hostState = null;
		try { hostState = FlxG.state; } catch (e:Dynamic) { hostState = null; }

		if (hostState != null)
		{
			try
			{
				// 视频 sprite 挂到 state（真正被绘制的对象）
				hostState.add(video);
				diag('[mount] video 已 add 到 FlxG.state');
			}
			catch (e:Dynamic) { diag('[mount] video add 到 state 失败: ' + e); }

			try
			{
				// 控制器自己挂到 state（让 update() 跑起来）
				hostState.add(this);
				diag('[mount] 控制器已 add 到 FlxG.state');
			}
			catch (e:Dynamic) { diag('[mount] 控制器 add 到 state 失败: ' + e); }
		}
		else
		{
			// 极端兜底：FlxG.state 取不到（几乎不可能）。
			//
			// ⚠⚠ 这里【只能】放弃挂载，绝不能走 `FlxG.game.addChild(video)`。
			//   编译错误实录（commit 9f7860c8，CI 失败）：
			//     VideoHandler.hx:304: hxvlc.flixel.FlxVideoSprite should be
			//     openfl.display.DisplayObject ... For function argument 'child'
			//   原因：FlxG.game 是 `FlxGame extends Sprite`，addChild 形参要求
			//   `DisplayObject`；而 FlxVideoSprite 继承自 `FlxSprite`（纯 Haxe
			//   对象，不是 openfl 显示树节点），两者没有继承关系 ⇒ 编译不过。
			//
			//   而对比 intro 的写法（TitleState.startIntroRealVideo）：
			//       var vs = new FlxVideoSprite();
			//       add(vs);                 // ← add 到 FlxState，不是 addChild 到 game
			//   它从来不需要 addChild。⇒ 这里也保持「要么挂 state，要么不挂」。
			diag('[mount] FlxG.state 为 null！无法挂载（不会崩溃，视频将不显示）');
		}

		diag('[create] FlxVideoSprite 已创建 bitmap=' + (video.bitmap == null ? 'null' : 'ok')
			+ ' scroll=' + video.scrollFactor.x + ',' + video.scrollFactor.y
			+ ' cams=' + (video.cameras == null ? 'null' : '' + video.cameras.length));

		if (video.bitmap != null)
		{
			video.bitmap.onFormatSetup.add(function():Void
			{
				if (video == null || video.bitmap == null)
				{
					diag('[formatSetup] 警告：video 或 bitmap 已为 null');
					return;
				}
				var bmd = video.bitmap.bitmapData;
				if (bmd == null)
				{
					diag('[formatSetup] 警告：bitmapData 为 null → 画面会是空白');
					return;
				}

				diag('[formatSetup] bitmapData=' + bmd.width + 'x' + bmd.height);

				if (bmd.width < 2 || bmd.height < 2)
				{
					diag('[formatSetup] 警告：尺寸过小，按原尺寸显示');
					// [PE-iOS] 不用 screenCenter（它按 sprite 尺寸算，hitbox 未同步时会歪）。
					video.updateHitbox();
					video.x = (FlxG.width - video.width) / 2;
					video.y = (FlxG.height - video.height) / 2;
					video.scrollFactor.set(0, 0);
					diagRawBitmap('tiny', video);
					return;
				}

				// [PE-iOS] 缩放策略：按「完整放得下」等比缩放（Math.min），不放大不裁切。
				//
				// ── 真正会「偏右 / 右边和下面被裁」的地方不在这里 ──────────────
				//   已经定案：那是 hxvlc 内部那个原始 Bitmap（挂在 FlxG.game 上、
				//   尺寸自动跟随 bitmapData、不受相机管辖）被打开 visible 造成的，
				//   修复在 Main.hx 的 ensureVideoBitmapVisible()（强制隐藏它）。
				//   本节代码只负责 FlxSprite 这条正路的缩放。
				//
				// ★ 不要用 video.setGraphicSize() ★
				//   FlxSprite.setGraphicSize(W,H) 内部是：
				//       scale.x = W / frameWidth;   scale.y = H / frameHeight;
				//   —— 它【除以当前 frame 尺寸】反推缩放比例。
				//   FlxVideoSprite 的帧由 hxvlc 在【它自己的】onFormatSetup 回调里
				//   通过 loadGraphic(FlxGraphic.fromBitmapData(...)) 更新。我们的回调
				//   挂在同一事件上，执行顺序取决于 add 顺序。若我们的先跑，
				//   frameWidth 还是构造时 makeGraphic(1,1) 留下的 1：
				//       scale.x = (1920 * 0.667) / 1 = 1280   ← 灾难性放大
				//   因此：直接设 scale（明确的缩放因子，与 frameWidth 无关），
				//   再 updateHitbox() 同步 width/height/offset。
				//
				// ⚠ 也不用 video.screenCenter()：它按 width/height 算，
				//   而这些值要 updateHitbox() 之后才准。
				//
				// ★★★ [PE-iOS] 适配基准：用【游戏窗口逻辑尺寸 FlxG.width/height】 ★★★
				//
				//   ── 为什么从「相机视口」改回 FlxG ────────────────────────────
				//   用户实测：「画面出来了，但没铺满整个游戏窗口。」
				//   说明视频只填满了【相机视口那一条】，而不是整个 game 面。
				//
				//   本项目视口结构（用户实测数据）：
				//       stage    = 1024x768   （设备横屏 4:3）
				//       canvas   = 1280x720   （FlxG.width/height，游戏逻辑尺寸）
				//       gameSize = 1024x576   （RatioScaleMode(false) 缩放后的显示区）
				//       offset.y = 96         （上下黑边）
				//   视频 sprite 由相机绘制，最终会被【拉伸到整个 game 面】显示。
				//   所以视频自己的逻辑尺寸必须是【游戏逻辑尺寸 1280x720】，
				//   而不是相机视口尺寸 —— 后者小于前者时就会「没铺满」。
				//
				//   ⚠ 历史教训：早先改成相机视口，是因为看到「同一 bmd 两次算出
				//     0.667 / 0.782 两个 scale」，怀疑 FlxG.width 不稳。
				//     现在 update() 里已经有【每帧矫正】，会持续把 scale 拉回正确值，
				//     所以这里可以放心用 FlxG.width/height（1280x720 是确定的）。
				var viewW:Float = FlxG.width;
				var viewH:Float = FlxG.height;
				if (viewW <= 0 || viewH <= 0)
				{
					viewW = FlxG.initialWidth;
					viewH = FlxG.initialHeight;
				}
				if (viewW <= 0 || viewH <= 0)
				{
					viewW = 1280;
					viewH = 720;
				}

				// 诊断：把候选基准全打出来，一眼看出谁在飘。
				diag('[basis] FlxG=' + FlxG.width + 'x' + FlxG.height
					+ ' cam=' + (cam == null ? 'null' : cam.width + 'x' + cam.height)
					+ ' initial=' + FlxG.initialWidth + 'x' + FlxG.initialHeight
					+ ' → 采用 view=' + viewW + 'x' + viewH);

				var scale:Float = Math.min(viewW / bmd.width, viewH / bmd.height);
				if (scale <= 0 || scale != scale) scale = 1; // NaN 自检
				video.scale.set(scale, scale);
				video.updateHitbox();
				video.x = (viewW - video.width) / 2;
				video.y = (viewH - video.height) / 2;
				video.scrollFactor.set(0, 0);

				// ★ [PE-iOS] 强制隐藏 hxvlc 内层原始 Bitmap。
				//   它被 FlxVideoSprite 构造时 addChild 到 FlxG.game 上
				//   （FlxVideoSprite.hx 第 95-96 行，默认 visible=false）：
				//     · 尺寸自动跟随 bitmapData（libVLC 逐帧重算 1502x845→1920x1080）
				//     · 不受 flixel 相机与 FlxSprite.scale 管辖
				//     · 父节点 FlxG.game 带黑边偏移（offset.x/offset.y）
				//   ⇒ 一旦它 visible=true，屏幕就多一个偏右、下边被裁的视频。
				//   Main.hx 的 ensureVideoBitmapVisible() 每 12 帧纠一次，这里再补一刀。
				//
				//   ⚠ 关掉它【不会】导致没画面：Video.hx videoDisplay() 第 1554 行是
				//       if ((__renderable || forceRendering) && ...)
				//     而 FlxVideoSprite 构造时设了 forceRendering = true（第 77 行），
				//     所以即使 __renderable(≈visible) 为 false，帧仍每帧写进 bitmapData
				//     （第 1570 行 setPixels 无条件执行），FlxSprite 照常显示。
				//     visible 只影响第 1572 行的 __setRenderDirty()，即「这一层自己重不重绘」。
				//   —— 若哪天正路真不通，下面的 autoFallbackTimer 会自动把它打开兜底。
				try { video.bitmap.visible = false; } catch (e:Dynamic) {}

				diag('[formatSetup] 居中：view=' + viewW + 'x' + viewH
					+ ' FlxG=' + FlxG.width + 'x' + FlxG.height
					+ ' xy=' + video.x + ',' + video.y);
				diag('[formatSetup] 缩放完成 frame=' + video.frameWidth + 'x' + video.frameHeight
					+ ' scale=' + video.scale.x + ' -> ' + video.width + 'x' + video.height
					+ ' xy=' + video.x + ',' + video.y
					+ ' scroll=' + video.scrollFactor.x + ',' + video.scrollFactor.y);

				diagRawBitmap('afterFormat', video);
				diagCoords('afterFormat', video);
			});
			// ★★★ [PE-iOS] onEndReached 必须加「最小播放时长」守卫 ★★★
			//
			//   现象：过场动画只播 1 秒就被收尾（intro 早就修了，这里漏了）。
			//   原因：iOS 上 hxvlc 会在【加载 / 格式化阶段】就误派发一次
			//   onEndReached（或在视频还没真正跑起来时派发）。原实现是
			//   直接 `.add(onVideoFinished)` —— 于是 playElapsed 才 1 秒就收尾。
			//
			//   intro 那边（TitleState）早就用 MIN_INTRO_SECONDS(2.5s) 挡掉了，
			//   兼容层这条路径当时没同步 ⇒ 就是「过场只播 1 秒」的真凶。
			//
			//   守卫逻辑：
			//     · 播放不足门槛的 onEndReached 一律忽略（等真正播完）；
			//     · 超过门槛才认为是真的播完，收尾。
			//   onVideoFinished() 自带 `if (ended) return;` 去重，安全。
			video.bitmap.onEndReached.add(function():Void
			{
				if (!playing) return;
				if (playElapsed < MIN_PLAY_SECONDS)
				{
					diag('[onEndReached] 忽略过早的结束事件（playElapsed=' + playElapsed
						+ ' < ' + MIN_PLAY_SECONDS + '）');
					return;
				}
				onVideoFinished();
			});
			// [PE-iOS] 记录时长。
			//   FlxVideoSprite 无 length 字段，时长在底层 bitmap(Video) 上，
			//   单位【微秒】，且解析完成前为 0，所以用 onLengthChanged 事件拿。
			//   参数用 Dynamic 接收后立刻转 Float 秒数，避免 Int64 参与运算。
			try
			{
				video.bitmap.onLengthChanged.add(function(us:Dynamic):Void
				{
					var v:Float = 0;
					try { v = Std.parseFloat(Std.string(us)); } catch (e:Dynamic) { v = 0; }

					if (v != v || v <= 0)
					{
						// Int64 对象兜底：取 low（对常见短视频足够）
						try
						{
							var low:Dynamic = Reflect.field(us, 'low');
							if (low != null) v = Std.parseFloat(Std.string(low));
						}
						catch (e:Dynamic) {}
					}

					if (v > 0) videoDurSec = v / 1000000.0;
				});
			}
			catch (e:Dynamic) {}
		}

		var options:Array<String> = null;
		if (loop) options = ['--input-repeat=999999'];

		var loaded:Bool = false;
		try { loaded = video.load(videoPath, options); } catch (e:Dynamic) { diag('[load] 抛异常: ' + e); loaded = false; }
		diag('[load] 返回值=' + loaded);

		if (!loaded)
		{
			var fileName:String = videoPath.split('/').pop();
			var retryPath:String = SUtil.getPath() + 'assets/videos/' + fileName;
			diag('[load] 首次失败，改用资源路径重试: ' + retryPath);
			try { loaded = video.load(retryPath, options); } catch (e:Dynamic) { loaded = false; }
			diag('[load] 重试返回值=' + loaded);
		}

		if (!loaded)
		{
			diag('[load] 两次都失败，跳过该视频');
			// ★ 同上：这里仍在 playVideo() 的【同步】栈里，调用方很可能还没
			//   来得及赋 finishCallback。延迟一拍再收尾，避免回调丢失卡死。
			deferFinish();
			return;
		}

		playing = true;
		started = true;
		diagFrame = 0;
		playElapsed = 0;
		videoDurSec = 0;

		new FlxTimer().start(0.001, function(_:FlxTimer)
		{
			if (video != null && playing)
			{
				try { video.play(); } catch (e:Dynamic) { diag('[play] 异常: ' + e); }
				diag('[play] 已调用 play()');
			}
		});

		// ★ 不依赖 update() 的定时快照：0.5s / 1.5s / 3s 各记一次原始 Bitmap 状态。
		// 之前只靠 update() 记录，结果一行 [state] 都没写出来（说明 update 没被驱动），
		// 所以改成定时器，确保一定能拿到数据。
		new FlxTimer().start(0.5, function(_:FlxTimer) {
			if (playing && video != null) { diagRawBitmap('t0.5', video); diagCoords('t0.5', video); }
		});
		new FlxTimer().start(1.5, function(_:FlxTimer) {
			if (playing && video != null) { diagRawBitmap('t1.5', video); diagCoords('t1.5', video); }
		});
		new FlxTimer().start(3.0, function(_:FlxTimer) {
			if (playing && video != null) { diagRawBitmap('t3.0', video); diagCoords('t3.0', video); }
		});

		// 跳过冷却：1.5 秒（原 0.5）。iOS 开场易有幽灵触摸，太短会导致「一播就过」。
		new FlxTimer().start(1.5, function(_:FlxTimer) canSkipNow = true);

		// ★ [PE-iOS] 自动兜底：1.5 秒后检查 FlxSprite 正路到底出没出画面，
		//   没出画面就自动打开内层 Bitmap（画面会偏右/被裁，但至少不黑屏）。
		//
		// ── 为什么需要这个保险 ──────────────────────────────────────────
		//   我们【主动关掉了】内层 Bitmap，因为它在 visible 时会与 FlxSprite
		//   视频重叠，造成「偏右 + 右边和下面被裁」。但万一在别的设备上
		//   FlxSprite 正路真的不通，关掉它就是黑屏。
		//   这条定时器就是那张安全网：只在「正路确实没出画面」时才退回去。
		//
		// ── 判据（多重，任一不满足即认为正路异常）────────────────────────
		//   1) bitmapData 存在且尺寸 > 1（hxvlc 建帧成功）
		//   2) FlxSprite.frameWidth > 1（loadGraphic 真的换了帧）
		//   3) FlxSprite 宽高 > 1（updateHitbox 后有效）
		//   4) sprite 至少与相机视口有交集（不是被放到屏幕外）
		//
		//   正常情况下 1-4 全满足 ⇒ 保持内层 Bitmap 隐藏（画面正确、不重叠）。
		new FlxTimer().start(1.5, function(_:FlxTimer)
		{
			if (!playing || video == null || video.bitmap == null) return;

			var bmdOK:Bool = false;
			var bmdDesc:String = 'null';
			var bmd = video.bitmap.bitmapData;
			if (bmd != null)
			{
				bmdDesc = bmd.width + 'x' + bmd.height;
				bmdOK = (bmd.width > 1 && bmd.height > 1);
			}

			var fw:Float = 0;
			try { fw = video.frameWidth; } catch (e:Dynamic) { fw = 0; }
			var vw:Float = 0;
			try { vw = video.width; } catch (e:Dynamic) { vw = 0; }
			var vh:Float = 0;
			try { vh = video.height; } catch (e:Dynamic) { vh = 0; }

			// 与相机视口求交集（该 sprite 挂在最后那个相机上）
			var onScreen:Bool = false;
			try
			{
				if (video.cameras != null && video.cameras.length > 0 && video.cameras[0] != null)
				{
					var cam = video.cameras[0];
					var visX:Bool = (video.x + vw > cam.x) && (video.x < cam.x + cam.width);
					var visY:Bool = (video.y + vh > cam.y) && (video.y < cam.y + cam.height);
					onScreen = visX && visY;
				}
			}
			catch (e:Dynamic) { onScreen = false; }

			var ok:Bool = bmdOK && fw > 1 && vw > 1 && vh > 1 && onScreen;

			diag('[autoFallback] 1.5s 判据: bmd=' + bmdDesc
				+ ' frameWidth=' + fw + ' size=' + vw + 'x' + vh
				+ ' onScreen=' + onScreen + ' → 正路' + (ok ? '正常' : '异常'));

			if (!ok)
			{
				diag('[autoFallback] ★ FlxSprite 正路异常 → 打开内层 Bitmap 兜底（画面可能偏右/被裁）');
				try { video.bitmap.visible = true; } catch (e:Dynamic) {}
				// 置静态标记，让 Main.hx 的每 12 帧扫描停手（避免反复横跳闪烁）
				VideoHandler.PEI_VIDEO_FALLBACK_ACTIVE = true;
			}
			else
			{
				diag('[autoFallback] ✓ FlxSprite 正路正常 → 保持内层 Bitmap 隐藏（无重叠、不偏右）');
			}
		});
	}

	/** 老模组会调用的跳过接口 */
	public function skipVideo():Void
	{
		onVideoFinished();
	}

	/**
	 * [PE-iOS] 把「收尾」推迟到下一拍执行。
	 *
	 * ── 为什么必需 ────────────────────────────────────────────────────
	 * 模组（以及 PlayState.startVideo）的调用顺序是【播放在前、回调在后】：
	 *
	 *     var video = new MP4Handler();
	 *     video.playVideo(filepath);            // ①
	 *     video.finishCallback = function(){};  // ②  ← 晚一步才赋值
	 *
	 * 而 playVideo() 里存在若干【同步】失败出口（空路径、文件不存在、
	 * load 两次失败…）。若在这些出口直接 onVideoFinished()，此时
	 * finishCallback 必然还是 null：
	 *   · 回调丢失 ⇒ 模组的 startCountdown()/endSong() 永不执行；
	 *   · PlayState.inCutscene 永远为 true ⇒ 整个打歌卡死。
	 *
	 * 推迟一拍（FlxTimer 0.001s）后，调用方已执行完 ②，回调不再丢失。
	 * onVideoFinished() 自身有 `if (ended) return;` 去重，重复调用无副作用。
	 */
	private function deferFinish():Void
	{
		new FlxTimer().start(0.001, function(_:FlxTimer) { onVideoFinished(); });
	}

	/** 播放结束 / 被跳过：收尾、回调 */
	public function onVideoFinished():Void
	{
		if (ended) return;
		ended = true;
		playing = false;
		diag('[finish] 视频结束/被跳过');

		// ★ [PE-iOS] 先把视频与控制器从它挂的那个 state 上摘掉。
		//   本类不是 substate，所以没有 close()，必须手动 remove。
		try
		{
			if (hostState != null)
			{
				if (video != null) { try { hostState.remove(video, true); } catch (e:Dynamic) {} }
				try { hostState.remove(this, true); } catch (e:Dynamic) {}
			}
		}
		catch (e:Dynamic) { diag('[finish] 从 state 摘除出错（已忽略）: ' + e); }

		if (video != null)
		{
			try { video.destroy(); } catch (e:Dynamic) { diag('[finish] 释放视频对象出错（已忽略）: ' + e); }
			video = null;
		}

		if (FlxG.sound.music != null && !FlxG.sound.music.playing)
		{
			try { FlxG.sound.music.play(); } catch (e:Dynamic) {}
		}

		// ★ [PE-iOS] 先收尾（已摘除），再触发回调。
		//   finishCallback 里模组通常会 startCountdown()/endSong()，可能马上又开新东西。
		if (finishCallback != null) finishCallback();
		if (onVideoEnd != null) onVideoEnd();
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (started && video != null && playing)
		{
			// ★★★ [PE-iOS] 每帧「保命」矫正 ★★★
			//
			//   现象：有声音、没画面。音频走 libVLC 回调，与 flixel 绘制链无关；
			//   所以只要 sprite 命中 FlxSprite.draw() 的任一提前 return 条件，
			//   就会「有声音没画面」。这里每帧把这三条都按下去：
			//
			//     A. alpha == 0 或空帧     → 强制 alpha=1（帧由 hxvlc 的
			//        loadGraphic 填，若为空帧则下面的 forceFrameFix 会记录）
			//     B. visible == false       → 强制 true（我们只关 bitmap 的 visible，
			//        从不关 sprite 自己的；但有别的代码可能误关）
			//     C. !isOnScreen(camera)    → 重算居中坐标，保证落在视口内
			//
			//   同时把「我们关掉的内层 bitmap」状态维持住（避免它跳出来叠画）。
			if (video.alpha <= 0) video.alpha = 1;
			if (!video.visible) video.visible = true;
			if (!video.exists) video.exists = true;

			// 坐标/缩放矫正：以【游戏窗口逻辑尺寸 FlxG.width/height】为基准重新居中。
			// 只在尺寸有效时做，避免每帧抖动。
			try
			{
				var bmd = video.bitmap != null ? video.bitmap.bitmapData : null;
				if (bmd != null && bmd.width > 1 && bmd.height > 1)
				{
					// ★ 基准与 onFormatSetup 保持一致：用游戏窗口逻辑尺寸 FlxG.width/height。
					//   （不能用相机视口 —— 那会让视频只填满相机那一条，表现为「没铺满」。）
					var viewW:Float = FlxG.width;
					var viewH:Float = FlxG.height;
					if (viewW <= 0 || viewH <= 0)
					{
						viewW = FlxG.initialWidth;
						viewH = FlxG.initialHeight;
					}
					if (viewW <= 0 || viewH <= 0) { viewW = 1280; viewH = 720; }
					if (viewW > 0 && viewH > 0)
					{
						var sc:Float = Math.min(viewW / bmd.width, viewH / bmd.height);
						if (sc > 0 && sc == sc)
						{
							if (Math.abs(video.scale.x - sc) > 0.001)
							{
								video.scale.set(sc, sc);
								video.updateHitbox();
								video.x = (viewW - video.width) / 2;
								video.y = (viewH - video.height) / 2;
							}
						}
					}
				}
			}
			catch (e:Dynamic) {}

			diagFrame++;
			if (diagFrame == 30 || diagFrame == 60 || diagFrame == 120)
			{
				diagRawBitmap('f' + diagFrame, video);
				diagCoords('f' + diagFrame, video);
			}

			// ★★★ [PE-iOS] 关键兜底：不依赖 onEndReached ★★★
			//   某些情况下 hxvlc 在 iOS 上【不派发 onEndReached】，
			//   导致永远不关 ⇒ 「过场播完卡住、进不去打歌界面」。
			//
			//   ⚠ 时长必须是「合理值」才用它做基准。
			//   iOS 上 onLengthChanged 可能过早派发（解析未完成时给个 1 秒级的
			//   假值），若直接拿它算 `videoDurSec + 2`，过场就会在 1 秒多被收尾
			//   —— 这正是「只播 1s」的另一条路径。
			//   所以：只有 videoDurSec >= MIN_PLAY_SECONDS 才认为时长可信。
			playElapsed += elapsed;
			var durUsable:Bool = (videoDurSec >= MIN_PLAY_SECONDS);
			if (durUsable && playElapsed > videoDurSec + 2.0)
			{
				diag('[PE-iOS] 过场视频超时兜底收尾（onEndReached 未触发）dur=' + videoDurSec
					+ ' elapsed=' + playElapsed);
				onVideoFinished();
				return;
			}
			else if (!durUsable && playElapsed > 180.0)
			{
				diag('[PE-iOS] 过场视频时长未知，硬超时兜底收尾 elapsed=' + playElapsed);
				onVideoFinished();
				return;
			}
		}

		if (!started || !playing || !canSkip || !canSkipNow) return;

		// ★ [PE-iOS] 与 intro 对齐：iOS 上 FlxG.mouse / touches 会在开场误判 justPressed，
		//   导致过场「一播就过」。这里同样：键盘直接认；鼠标/触摸做双重确认。
		var pressed:Bool = FlxG.keys.justPressed.ANY;
		if (!pressed)
		{
			try
			{
				if (FlxG.mouse != null && FlxG.mouse.justPressed) pressed = true;
			}
			catch (e:Dynamic) {}
		}
		#if mobile
		if (!pressed)
		{
			try
			{
				for (touch in FlxG.touches.list)
				{
					if (touch != null && touch.justPressed && touch.pressed) { pressed = true; break; }
				}
			}
			catch (e:Dynamic) {}
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

		var inAssets:String = SUtil.getPath() + 'assets/videos/' + path;
		if (FileSystem.exists(inAssets)) return inAssets;

		return path;
	}
}
#end
