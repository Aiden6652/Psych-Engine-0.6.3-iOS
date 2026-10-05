package;

#if desktop
import sys.thread.Thread;
#end
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.input.keyboard.FlxKey;
import flixel.addons.display.FlxGridOverlay;
import flixel.addons.transition.FlxTransitionSprite.GraphicTransTileDiamond;
import flixel.addons.transition.FlxTransitionableState;
import flixel.addons.transition.TransitionData;
import haxe.Json;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
#if MODS_ALLOWED
import sys.FileSystem;
import sys.io.File;
#end
import options.GraphicsSettingsSubState;
//import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.graphics.frames.FlxFrame;
import flixel.group.FlxGroup;
import flixel.input.gamepad.FlxGamepad;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.system.FlxSound;
import flixel.system.ui.FlxSoundTray;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import openfl.Assets;
import flixel.graphics.FlxGraphic;

using StringTools;
typedef TitleData =
{

	titlex:Float,
	titley:Float,
	startx:Float,
	starty:Float,
	gfx:Float,
	gfy:Float,
	backgroundSprite:String,
	bpm:Int
}
class TitleState extends MusicBeatState
{
	public static var muteKeys:Array<FlxKey> = [FlxKey.ZERO];
	public static var volumeDownKeys:Array<FlxKey> = [FlxKey.NUMPADMINUS, FlxKey.MINUS];
	public static var volumeUpKeys:Array<FlxKey> = [FlxKey.NUMPADPLUS, FlxKey.PLUS];

	public static var initialized:Bool = false;

	var blackScreen:FlxSprite;
	var credGroup:FlxGroup;
	var credTextShit:Alphabet;
	var textGroup:FlxGroup;
	var ngSpr:FlxSprite;
	
	var titleTextColors:Array<FlxColor> = [0xFF33FFFF, 0xFF3333CC];
	var titleTextAlphas:Array<Float> = [1, .64];

	var curWacky:Array<String> = [];

	var wackyImage:FlxSprite;

	#if TITLE_SCREEN_EASTER_EGG
	var easterEggKeys:Array<String> = [
		'SHADOW', 'RIVER', 'SHUBS', 'BBPANZU'
	];
	var allowedKeys:String = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
	var easterEggKeysBuffer:String = '';
	#end

	var mustUpdate:Bool = false;

	var titleJSON:TitleData;

	public static var updateVersion:String = '';

	override public function create():Void
	{

		#if android
		FlxG.android.preventDefaultKeys = [BACK];
		#end

		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();

		#if LUA_ALLOWED
		Paths.pushGlobalMods();
		#end
		// Just to load a mod on start up if ya got one. For mods that change the menu music and bg
		WeekData.loadTheFirstEnabledMod();

		//trace(path, FileSystem.exists(path));

		/*#if (polymod && !html5)
		if (sys.FileSystem.exists('mods/')) {
			var folders:Array<String> = [];
			for (file in sys.FileSystem.readDirectory('mods/')) {
				var path = haxe.io.Path.join(['mods/', file]);
				if (sys.FileSystem.isDirectory(path)) {
					folders.push(file);
				}
			}
			if(folders.length > 0) {
				polymod.Polymod.init({modRoot: "mods", dirs: folders});
			}
		}
		#end*/

		FlxG.game.focusLostFramerate = 60;
		FlxG.sound.muteKeys = muteKeys;
		FlxG.sound.volumeDownKeys = volumeDownKeys;
		FlxG.sound.volumeUpKeys = volumeUpKeys;
		FlxG.keys.preventDefaultKeys = [TAB];

		PlayerSettings.init();

		curWacky = FlxG.random.getObject(getIntroTextShit());

		// DEBUG BULLSHIT

		swagShader = new ColorSwap();
		super.create();

		FlxG.save.bind('funkin' , CoolUtil.getSavePath());

		ClientPrefs.loadPrefs();

		#if CHECK_FOR_UPDATES
		if(ClientPrefs.checkForUpdates && !closedState) {
			trace('checking for update');
			var http = new haxe.Http("https://raw.githubusercontent.com/MaysLastPlayGithub/FNF-PsychEngine/main/gitVersion.txt");

			http.onData = function (data:String)
			{
				updateVersion = data.split('\n')[0].trim();
				var curVersion:String = MainMenuState.psychEngineVersion.trim();
				trace('version online: ' + updateVersion + ', your version: ' + curVersion);
				if(updateVersion != curVersion) {
					trace('versions arent matching!');
					mustUpdate = true;
				}
			}

			http.onError = function (error) {
				trace('error: $error');
			}

			http.request();
		}
		#end

		Highscore.load();

		// IGNORE THIS!!!
		titleJSON = Json.parse(Paths.getTextFromFile('images/gfDanceTitle.json'));

		#if TITLE_SCREEN_EASTER_EGG
		if (FlxG.save.data.psychDevsEasterEgg == null) FlxG.save.data.psychDevsEasterEgg = ''; //Crash prevention
		switch(FlxG.save.data.psychDevsEasterEgg.toUpperCase())
		{
			case 'SHADOW':
				titleJSON.gfx += 210;
				titleJSON.gfy += 40;
			case 'RIVER':
				titleJSON.gfx += 100;
				titleJSON.gfy += 20;
			case 'SHUBS':
				titleJSON.gfx += 160;
				titleJSON.gfy -= 10;
			case 'BBPANZU':
				titleJSON.gfx += 45;
				titleJSON.gfy += 100;
		}
		#end

		if(!initialized)
		{
			if(FlxG.save.data != null && FlxG.save.data.fullscreen)
			{
				FlxG.fullscreen = FlxG.save.data.fullscreen;
				//trace('LOADED FULLSCREEN SETTING!!');
			}
			persistentUpdate = true;
			persistentDraw = true;
		}

		if (FlxG.save.data.weekCompleted != null)
		{
			StoryMenuState.weekCompleted = FlxG.save.data.weekCompleted;
		}

		FlxG.mouse.visible = false;
		#if FREEPLAY
		MusicBeatState.switchState(new FreeplayState());
		#elseif CHARTING
		MusicBeatState.switchState(new ChartingState());
		#else
		if(FlxG.save.data.flashing == null && !FlashingState.leftState) {
			FlxTransitionableState.skipNextTransIn = true;
			FlxTransitionableState.skipNextTransOut = true;
			MusicBeatState.switchState(new FlashingState());
		} else {
			if (initialized)
				startIntro();
			else
			{
				new FlxTimer().start(1, function(tmr:FlxTimer)
				{
					startIntro();
				});
			}
		}
		#end
	}

	var logoBl:FlxSprite;
	var gfDance:FlxSprite;
	var danceLeft:Bool = false;
	var titleText:FlxSprite;
	var swagShader:ColorSwap = null;

	function startIntro()
	{
		if (!initialized)
		{
			/*var diamond:FlxGraphic = FlxGraphic.fromClass(GraphicTransTileDiamond);
			diamond.persist = true;
			diamond.destroyOnNoUse = false;

			FlxTransitionableState.defaultTransIn = new TransitionData(FADE, FlxColor.BLACK, 1, new FlxPoint(0, -1), {asset: diamond, width: 32, height: 32},
				new FlxRect(-300, -300, FlxG.width * 1.8, FlxG.height * 1.8));
			FlxTransitionableState.defaultTransOut = new TransitionData(FADE, FlxColor.BLACK, 0.7, new FlxPoint(0, 1),
				{asset: diamond, width: 32, height: 32}, new FlxRect(-300, -300, FlxG.width * 1.8, FlxG.height * 1.8));

			transIn = FlxTransitionableState.defaultTransIn;
			transOut = FlxTransitionableState.defaultTransOut;*/

			// HAD TO MODIFY SOME BACKEND SHIT
			// IF THIS PR IS HERE IF ITS ACCEPTED UR GOOD TO GO
			// https://github.com/HaxeFlixel/flixel-addons/pull/348

			// var music:FlxSound = new FlxSound();
			// music.loadStream(Paths.music('freakyMenu'));
			// FlxG.sound.list.add(music);
			// music.play();

			if(FlxG.sound.music == null) {
				FlxG.sound.playMusic(Paths.music('freakyMenu'), 0);
			}
		}

		Conductor.changeBPM(titleJSON.bpm);
		persistentUpdate = true;

		var bg:FlxSprite = new FlxSprite();

		if (titleJSON.backgroundSprite != null && titleJSON.backgroundSprite.length > 0 && titleJSON.backgroundSprite != "none"){
			bg.loadGraphic(Paths.image(titleJSON.backgroundSprite));
		}else{
			bg.makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		}

		// bg.antialiasing = ClientPrefs.globalAntialiasing;
		// bg.setGraphicSize(Std.int(bg.width * 0.6));
		// bg.updateHitbox();
		add(bg);

		logoBl = new FlxSprite(titleJSON.titlex, titleJSON.titley);
		logoBl.frames = Paths.getSparrowAtlas('logoBumpin');

		logoBl.antialiasing = ClientPrefs.globalAntialiasing;
		logoBl.animation.addByPrefix('bump', 'logo bumpin', 24, false);
		logoBl.animation.play('bump');
		logoBl.updateHitbox();
		// logoBl.screenCenter();
		// logoBl.color = FlxColor.BLACK;

		swagShader = new ColorSwap();
		gfDance = new FlxSprite(titleJSON.gfx, titleJSON.gfy);

		var easterEgg:String = FlxG.save.data.psychDevsEasterEgg;
		if(easterEgg == null) easterEgg = ''; //html5 fix

		switch(easterEgg.toUpperCase())
		{
			#if TITLE_SCREEN_EASTER_EGG
			case 'SHADOW':
				gfDance.frames = Paths.getSparrowAtlas('ShadowBump');
				gfDance.animation.addByPrefix('danceLeft', 'Shadow Title Bump', 24);
				gfDance.animation.addByPrefix('danceRight', 'Shadow Title Bump', 24);
			case 'RIVER':
				gfDance.frames = Paths.getSparrowAtlas('RiverBump');
				gfDance.animation.addByIndices('danceLeft', 'River Title Bump', [15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29], "", 24, false);
				gfDance.animation.addByIndices('danceRight', 'River Title Bump', [29, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14], "", 24, false);
			case 'SHUBS':
				gfDance.frames = Paths.getSparrowAtlas('ShubBump');
				gfDance.animation.addByPrefix('danceLeft', 'Shub Title Bump', 24, false);
				gfDance.animation.addByPrefix('danceRight', 'Shub Title Bump', 24, false);
			case 'BBPANZU':
				gfDance.frames = Paths.getSparrowAtlas('BBBump');
				gfDance.animation.addByIndices('danceLeft', 'BB Title Bump', [14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27], "", 24, false);
				gfDance.animation.addByIndices('danceRight', 'BB Title Bump', [27, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13], "", 24, false);
			#end

			default:
			//EDIT THIS ONE IF YOU'RE MAKING A SOURCE CODE MOD!!!!
			//EDIT THIS ONE IF YOU'RE MAKING A SOURCE CODE MOD!!!!
			//EDIT THIS ONE IF YOU'RE MAKING A SOURCE CODE MOD!!!!
				gfDance.frames = Paths.getSparrowAtlas('gfDanceTitle');
				gfDance.animation.addByIndices('danceLeft', 'gfDance', [30, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14], "", 24, false);
				gfDance.animation.addByIndices('danceRight', 'gfDance', [15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29], "", 24, false);
		}
		gfDance.antialiasing = ClientPrefs.globalAntialiasing;

		add(gfDance);
		gfDance.shader = swagShader.shader;
		add(logoBl);
		logoBl.shader = swagShader.shader;

		titleText = new FlxSprite(titleJSON.startx, titleJSON.starty);
		#if ((desktop || android || ios) && MODS_ALLOWED)
		var path = SUtil.getPath() + "mods/" + Paths.currentModDirectory + "/images/titleEnter.png";
		//trace(path, FileSystem.exists(path));
		if (!FileSystem.exists(path)){
			path = SUtil.getPath() + "mods/images/titleEnter.png";
		}
		//trace(path, FileSystem.exists(path));
		if (!FileSystem.exists(path)){
			path = SUtil.getPath() + "assets/images/titleEnter.png";
		}
		//trace(path, FileSystem.exists(path));
		titleText.frames = FlxAtlasFrames.fromSparrow(BitmapData.fromFile(path),File.getContent(StringTools.replace(path,".png",".xml")));
		#else

		titleText.frames = Paths.getSparrowAtlas('titleEnter');
		#end
		var animFrames:Array<FlxFrame> = [];
		@:privateAccess {
			titleText.animation.findByPrefix(animFrames, "ENTER IDLE");
			titleText.animation.findByPrefix(animFrames, "ENTER FREEZE");
		}
		
		if (animFrames.length > 0) {
			newTitle = true;
			
			titleText.animation.addByPrefix('idle', "ENTER IDLE", 24);
			titleText.animation.addByPrefix('press', ClientPrefs.flashing ? "ENTER PRESSED" : "ENTER FREEZE", 24);
		}
		else {
			newTitle = false;
			
			titleText.animation.addByPrefix('idle', "Press Enter to Begin", 24);
			titleText.animation.addByPrefix('press', "ENTER PRESSED", 24);
		}
		
		titleText.antialiasing = ClientPrefs.globalAntialiasing;
		titleText.animation.play('idle');
		titleText.updateHitbox();
		// titleText.screenCenter(X);
		add(titleText);

		var logo:FlxSprite = new FlxSprite().loadGraphic(Paths.image('logo'));
		logo.screenCenter();
		logo.antialiasing = ClientPrefs.globalAntialiasing;
		// add(logo);

		// FlxTween.tween(logoBl, {y: logoBl.y + 50}, 0.6, {ease: FlxEase.quadInOut, type: PINGPONG});
		// FlxTween.tween(logo, {y: logoBl.y + 50}, 0.6, {ease: FlxEase.quadInOut, type: PINGPONG, startDelay: 0.1});

		credGroup = new FlxGroup();
		add(credGroup);
		textGroup = new FlxGroup();

		blackScreen = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		credGroup.add(blackScreen);

		credTextShit = new Alphabet(0, 0, "", true);
		credTextShit.screenCenter();

		// credTextShit.alignment = CENTER;

		credTextShit.visible = false;

		ngSpr = new FlxSprite(0, FlxG.height * 0.52).loadGraphic(Paths.image('newgrounds_logo'));
		add(ngSpr);
		ngSpr.visible = false;
		ngSpr.setGraphicSize(Std.int(ngSpr.width * 0.8));
		ngSpr.updateHitbox();
		ngSpr.screenCenter(X);
		ngSpr.antialiasing = ClientPrefs.globalAntialiasing;

		FlxTween.tween(credTextShit, {y: credTextShit.y + 20}, 2.9, {ease: FlxEase.quadInOut, type: PINGPONG});

		if (initialized)
			skipIntro();
		else
		{
			initialized = true;
			startIntroVideo(); // [PE-iOS] 开机片头（只有本次启动第一次进标题页才播）
		}

		// credGroup.add(credTextShit);
	}

	function getIntroTextShit():Array<Array<String>>
	{
		var fullText:String = Assets.getText(Paths.txt('introText'));

		var firstArray:Array<String> = fullText.split('\n');
		var swagGoodArray:Array<Array<String>> = [];

		for (i in firstArray)
		{
			swagGoodArray.push(i.split('--'));
		}

		return swagGoodArray;
	}

	// ==================== [PE-iOS] 开机片头 ====================
	// 两种模式，优先真视频：
	//   A) 真视频：mods/<模组>/videos/intro.mp4 或 <游戏目录>/assets/videos/intro.mp4
	//      → 用 hxvlc 直接播（画面与声音都来自 mp4，铺满屏幕、保持比例裁切）。
	//      ⚠ 画面能不能出来取决于 hxvlc 版本：必须 >= 1.9.3（我们用的是 2.3.1）。
	//        1.8.x 的 iOS 静态库缺 visual 模块，会「有声音、没画面」。
	//   B) 逐帧图：images/vfx_frames/intro/0001.png …（intro.mp4 切出来的帧）+ sounds/vfx/intro.ogg
	//      注意：这里**不能**用 Paths.image() —— 它内部 persist = true 会把每张图永久留在缓存里，
	//      2344 帧 1280x720 会吃满内存直接崩。所以自己读文件、自己销毁上一张（同一时刻只留 1~2 张）。
	// 两者都没有时什么都不做，原版流程不受影响。
	static inline var INTRO_FRAMES:Int = 2344;
	static inline var INTRO_FPS:Float = 24;
	static inline var INTRO_W:Int = 1280;

	var introSpr:FlxSprite = null;
	var introGfx:FlxGraphic = null;
	var introSound:FlxSound = null;
	var introPlaying:Bool = false;
	var introTime:Float = 0;
	var introFrame:Int = 0;
	#if VIDEOS_ALLOWED
	var introVideo:hxvlc.flixel.FlxVideoSprite = null;
	/// [PE-iOS] 片头视频时长（秒），由 bitmap.onLengthChanged 填充；0 = 未知
	var introVideoDurSec:Float = 0;
	#end
	/// 本次片头是不是「真视频」模式（否则走逐帧图）
	var introUsingVideo:Bool = false;

	inline function introPath(n:Int):String
	{
		return Paths.modsImages('vfx_frames/intro/' + StringTools.lpad(Std.string(n), '0', 4));
	}

	function startIntroVideo():Void
	{
		#if MODS_ALLOWED
		#if VIDEOS_ALLOWED
		var vidPath:String = Paths.video('intro');
		if (vidPath != null && FileSystem.exists(vidPath))
		{
			startIntroRealVideo(vidPath);
			return;
		}
		#end

		// 兜底：逐帧图
		if (!FileSystem.exists(introPath(1))) return; // 没装模组 / 没有片头帧 → 完全跳过
		introSpr = new FlxSprite(0, 0);
		introSpr.antialiasing = false;
		add(introSpr);
		introFrame = 0;
		introTime = 0;
		introPlaying = true;
		introUsingVideo = false;
		setIntroFrame(1);
		if (FileSystem.exists(Paths.modsSounds('vfx', 'intro')))
		{
			introSound = FlxG.sound.play(Paths.sound('vfx/intro'), 1);
		}
		#end
	}

	/// [PE-iOS] 片头真视频：铺满屏幕（保持长宽比裁切），播完自动收尾，点一下可跳过。
	/// 加载失败时自动回落到逐帧图，不会卡在黑屏。
	function startIntroRealVideo(path:String):Void
	{
		#if (MODS_ALLOWED && VIDEOS_ALLOWED)
		// 注意：不要传 (0, 0) —— hxvlc 2.x 的签名是 new(?instance, ?x, ?y)，
		// 传 (0, 0) 会被当成 instance=0 而编译失败；不传参数在 1.x / 2.x 下都合法。
		var vs:hxvlc.flixel.FlxVideoSprite = new hxvlc.flixel.FlxVideoSprite();
		vs.antialiasing = false;
		add(vs);

		if (vs.bitmap != null)
		{
			vs.bitmap.onFormatSetup.add(function():Void
			{
				if (vs.bitmap == null) return;
				var bmd = vs.bitmap.bitmapData;
				if (bmd == null) return;

				// [PE-iOS] ★ 修「片头视频太靠右 / 右边被切」★
				// 原写法两处问题：
				//   1) Math.max(...) —— 铺满策略，视频被放大到超出屏幕两侧 ⇒ 边缘被裁
				//   2) vs.screenCenter() —— 它是按 FlxSprite 的 width/height 与
				//      FlxG.width/height 算的，但我们刚 setGraphicSize 过、
				//      offset/hitbox 可能还没同步，居中会算歪。
				//
				// 本 sprite 没有指定 cameras ⇒ 挂在 FlxG.cameras.list[0]（camGame）上。
				// camGame 的【视口尺寸】恒等于 FlxG.width x FlxG.height（由 scaleMode
				// 保证），相机自身的 x/y 黑边偏移由 Flixel 在绘制时施加，
				// 与 sprite 坐标无关。所以这里直接用 FlxG.width/height 作为参照
				// 就是正确的，不需要去读 cameras[0]。
				var viewW:Float = FlxG.width;
				var viewH:Float = FlxG.height;

				var scale:Float = Math.min(viewW / bmd.width, viewH / bmd.height);
				if (scale <= 0 || scale != scale) scale = 1;
				var tw:Int = Std.int(Math.max(1, bmd.width * scale));
				var th:Int = Std.int(Math.max(1, bmd.height * scale));
				vs.setGraphicSize(tw, th);
				vs.updateHitbox();
				// ★ 顺序很重要：updateHitbox() 会按 frame 重算 offset/size，
				//   所以 x/y 必须放在它【之后】设，否则会被覆盖。
				vs.x = (viewW - vs.width) / 2;
				vs.y = (viewH - vs.height) / 2;
				vs.scrollFactor.set(0, 0);
			});
			vs.bitmap.onEndReached.add(endIntroVideo);
			// [PE-iOS] 记录视频时长。
			//   注意：FlxVideoSprite 本身【没有 length 字段】，时长在底层
			//   `hxvlc.openfl.Video` 上（即 vs.bitmap.length），单位【微秒】。
			//   而且 length 在媒体解析完成前是 0，所以要靠 onLengthChanged 事件拿。
			//   回调参数用 Dynamic 接收后立刻转成 Float 秒数存起来 ——
			//   避免 Int64（hxcpp 下是对象）参与比较运算导致编译/运行问题。
			try
			{
				vs.bitmap.onLengthChanged.add(function(us:Dynamic):Void
				{
					var v:Float = 0;
					try { v = Std.parseFloat(Std.string(us)); } catch (e:Dynamic) { v = 0; }
					if (v > 0) introVideoDurSec = v / 1000000.0;
				});
			}
			catch (e:Dynamic) {}
		}

		var loaded:Bool = false;
		try { loaded = vs.load(path); } catch (e:Dynamic) { loaded = false; }

		if (!loaded)
		{
			trace('[PE-iOS] 片头视频加载失败，改用逐帧图: ' + path);
			try { vs.destroy(); } catch (e:Dynamic) {}
			// 回落逐帧图
			if (FileSystem.exists(introPath(1)))
			{
				introSpr = new FlxSprite(0, 0);
				introSpr.antialiasing = false;
				add(introSpr);
				introFrame = 0;
				introTime = 0;
				introPlaying = true;
				introUsingVideo = false;
				setIntroFrame(1);
				if (FileSystem.exists(Paths.modsSounds('vfx', 'intro')))
					introSound = FlxG.sound.play(Paths.sound('vfx/intro'), 1);
			}
			return;
		}

		trace('[PE-iOS] 片头视频开始播放: ' + path);
		introVideo = vs;
		introUsingVideo = true;
		introPlaying = true;
		introTime = 0;
		new FlxTimer().start(0.001, function(_:FlxTimer)
		{
			if (introPlaying && introVideo != null)
			{
				try { introVideo.play(); } catch (e:Dynamic) {}
			}
		});
		#end
	}

	function setIntroFrame(n:Int):Void
	{
		#if MODS_ALLOWED
		var p:String = introPath(n);
		if (!FileSystem.exists(p)) return;
		var bmd:BitmapData = null;
		try { bmd = BitmapData.fromFile(p); } catch (e:Dynamic) { bmd = null; }
		if (bmd == null) return;

		var old:FlxGraphic = introGfx;
		introGfx = FlxGraphic.fromBitmapData(bmd, true, null, false);
		introGfx.persist = false;
		introSpr.loadGraphic(introGfx);
		// [PE-iOS] 同样改为「等比完整显示 + 显式居中」，与真视频路径保持一致。
		//   原写法 setGraphicSize(FlxG.width, FlxG.width * 720/INTRO_W) 会把帧拉满宽度，
		//   若帧的宽高比与 16:9 不同就会变形/溢出。
		{
			var viewW:Float = FlxG.width;
			var viewH:Float = FlxG.height;

			var sc:Float = Math.min(viewW / bmd.width, viewH / bmd.height);
			if (sc <= 0 || sc != sc) sc = 1;
			var tw:Int = Std.int(Math.max(1, bmd.width * sc));
			var th:Int = Std.int(Math.max(1, bmd.height * sc));
			introSpr.setGraphicSize(tw, th);
			introSpr.updateHitbox();
			// x/y 必须在 updateHitbox() 之后设（否则被 offset 重算覆盖）
			introSpr.x = (viewW - introSpr.width) / 2;
			introSpr.y = (viewH - introSpr.height) / 2;
		}
		if (old != null) old.destroy();
		#end
	}

	function endIntroVideo():Void
	{
		if (!introPlaying) return;
		introPlaying = false;
		introUsingVideo = false;
		if (introSound != null) { introSound.stop(); introSound = null; }
		if (introSpr != null) { remove(introSpr, true); introSpr = null; }
		if (introGfx != null) { introGfx.destroy(); introGfx = null; }
		#if (MODS_ALLOWED && VIDEOS_ALLOWED)
		if (introVideo != null)
		{
			try { remove(introVideo, true); introVideo.destroy(); } catch (e:Dynamic) {}
			introVideo = null;
		}
		introVideoDurSec = 0;
		#end
		// 记一下：片头播过了（模组里的 lua 会读这个标记，避免在 story 第一首又播一遍）
		#if MODS_ALLOWED
		try { File.saveContent(SUtil.getPath() + Paths.getPreloadPath('intro_seen.txt'), '1'); } catch (e:Dynamic) {}
		#end
		// 片头期间把标题音乐停了，这里恢复
		FlxG.sound.playMusic(Paths.music('freakyMenu'), 0.7);
	}

	function introSkippedByInput():Bool
	{
		var pressed:Bool = FlxG.keys.justPressed.ANY || FlxG.mouse.justPressed;
		#if mobile
		for (touch in FlxG.touches.list)
		{
			if (touch.justPressed) pressed = true;
		}
		#end
		return pressed;
	}

	var transitioning:Bool = false;
	private static var playJingle:Bool = false;
	
	var newTitle:Bool = false;
	var titleTimer:Float = 0;

	override function update(elapsed:Float)
	{
		if (FlxG.sound.music != null)
			Conductor.songPosition = FlxG.sound.music.time;

		// [PE-iOS] 开机片头播放期间：切帧/等视频结束、按键跳过，并屏蔽标题页原有输入
		if (introPlaying)
		{
			introTime += elapsed;
			if (FlxG.sound.music != null) FlxG.sound.music.stop(); // 别和片头的声音打架

			if (introUsingVideo)
			{
				// 真视频：画面与声音都由 hxvlc 负责，正常播完走 onEndReached → endIntroVideo。
				// 这里只处理「点一下跳过」（开场 0.6 秒内不响应，避免误触）。
				if (introTime > 0.6 && introSkippedByInput())
					endIntroVideo();

				// ★★★ [PE-iOS] 关键兜底：不依赖 onEndReached ★★★
				//   实测某些情况下 hxvlc 在 iOS 上【不派发 onEndReached】，
				//   导致 introPlaying 永远为 true ⇒ 标题页输入被永久屏蔽
				//   ⇒ 「片头播完卡住、进不去打歌界面」。
				//
				//   时长来源：bitmap.onLengthChanged（已换算成【秒】存进 introVideoDurSec）。
				//   （FlxVideoSprite 没有 length 字段，别写成 introVideo.length！）
				//   拿不到时长时用固定上限兜底，绝不死锁。
				//
				//   endIntroVideo() 内部有 `if (!introPlaying) return;` 去重，
				//   所以事件正常触发时不会重复执行。
				if (introPlaying && introVideoDurSec > 0
					&& introTime > introVideoDurSec + 1.5)
				{
					trace('[PE-iOS] 片头视频超时兜底收尾（onEndReached 未触发）dur=' + introVideoDurSec);
					endIntroVideo();
				}
				else if (introPlaying && introVideoDurSec <= 0 && introTime > 180.0)
				{
					// 连时长都拿不到 → 3 分钟硬上限，绝不死锁
					trace('[PE-iOS] 片头视频时长未知，硬超时兜底收尾');
					endIntroVideo();
				}
			}
			else
			{
				var want:Int = Std.int(introTime * INTRO_FPS) + 1;
				if (want > introFrame)
				{
					if (want > INTRO_FRAMES)
						endIntroVideo();
					else
					{
						introFrame = want;
						setIntroFrame(introFrame);
					}
				}
				if (introPlaying && introTime > 0.6 && introSkippedByInput())
					endIntroVideo();
			}

			super.update(elapsed);
			return;
		}
		// FlxG.watch.addQuick('amp', FlxG.sound.music.amplitude);

		var pressedEnter:Bool = FlxG.keys.justPressed.ENTER || controls.ACCEPT;

		#if mobile
		for (touch in FlxG.touches.list)
		{
			if (touch.justPressed)
			{
				pressedEnter = true;
			}
		}
		#end

		var gamepad:FlxGamepad = FlxG.gamepads.lastActive;

		if (gamepad != null)
		{
			if (gamepad.justPressed.START)
				pressedEnter = true;

			#if switch
			if (gamepad.justPressed.B)
				pressedEnter = true;
			#end
		}
		
		if (newTitle) {
			titleTimer += CoolUtil.boundTo(elapsed, 0, 1);
			if (titleTimer > 2) titleTimer -= 2;
		}

		// EASTER EGG

		if (initialized && !transitioning && skippedIntro)
		{
			if (newTitle && !pressedEnter)
			{
				var timer:Float = titleTimer;
				if (timer >= 1)
					timer = (-timer) + 2;
				
				timer = FlxEase.quadInOut(timer);
				
				titleText.color = FlxColor.interpolate(titleTextColors[0], titleTextColors[1], timer);
				titleText.alpha = FlxMath.lerp(titleTextAlphas[0], titleTextAlphas[1], timer);
			}
			
			if(pressedEnter)
			{
				titleText.color = FlxColor.WHITE;
				titleText.alpha = 1;
				
				if(titleText != null) titleText.animation.play('press');

				FlxG.camera.flash(ClientPrefs.flashing ? FlxColor.WHITE : 0x4CFFFFFF, 1);
				FlxG.sound.play(Paths.sound('confirmMenu'), 0.7);

				transitioning = true;
				// FlxG.sound.music.stop();

				new FlxTimer().start(1, function(tmr:FlxTimer)
				{
					if (mustUpdate) {
						MusicBeatState.switchState(new OutdatedState());
					} else {
						MusicBeatState.switchState(new MainMenuState());
					}
					closedState = true;
				});
				// FlxG.sound.play(Paths.music('titleShoot'), 0.7);
			}
			#if TITLE_SCREEN_EASTER_EGG
			else if (FlxG.keys.firstJustPressed() != FlxKey.NONE)
			{
				var keyPressed:FlxKey = FlxG.keys.firstJustPressed();
				var keyName:String = Std.string(keyPressed);
				if(allowedKeys.contains(keyName)) {
					easterEggKeysBuffer += keyName;
					if(easterEggKeysBuffer.length >= 32) easterEggKeysBuffer = easterEggKeysBuffer.substring(1);
					//trace('Test! Allowed Key pressed!!! Buffer: ' + easterEggKeysBuffer);

					for (wordRaw in easterEggKeys)
					{
						var word:String = wordRaw.toUpperCase(); //just for being sure you're doing it right
						if (easterEggKeysBuffer.contains(word))
						{
							//trace('YOOO! ' + word);
							if (FlxG.save.data.psychDevsEasterEgg == word)
								FlxG.save.data.psychDevsEasterEgg = '';
							else
								FlxG.save.data.psychDevsEasterEgg = word;
							FlxG.save.flush();

							FlxG.sound.play(Paths.sound('ToggleJingle'));

							var black:FlxSprite = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
							black.alpha = 0;
							add(black);

							FlxTween.tween(black, {alpha: 1}, 1, {onComplete:
								function(twn:FlxTween) {
									FlxTransitionableState.skipNextTransIn = true;
									FlxTransitionableState.skipNextTransOut = true;
									MusicBeatState.switchState(new TitleState());
								}
							});
							FlxG.sound.music.fadeOut();
							if(FreeplayState.vocals != null)
							{
								FreeplayState.vocals.fadeOut();
							}
							closedState = true;
							transitioning = true;
							playJingle = true;
							easterEggKeysBuffer = '';
							break;
						}
					}
				}
			}
			#end
		}

		if (initialized && pressedEnter && !skippedIntro)
		{
			skipIntro();
		}

		if(swagShader != null)
		{
			if(controls.UI_LEFT) swagShader.hue -= elapsed * 0.1;
			if(controls.UI_RIGHT) swagShader.hue += elapsed * 0.1;
		}

		super.update(elapsed);
	}

	function createCoolText(textArray:Array<String>, ?offset:Float = 0)
	{
		for (i in 0...textArray.length)
		{
			var money:Alphabet = new Alphabet(0, 0, textArray[i], true);
			money.screenCenter(X);
			money.y += (i * 60) + 200 + offset;
			if(credGroup != null && textGroup != null) {
				credGroup.add(money);
				textGroup.add(money);
			}
		}
	}

	function addMoreText(text:String, ?offset:Float = 0)
	{
		if(textGroup != null && credGroup != null) {
			var coolText:Alphabet = new Alphabet(0, 0, text, true);
			coolText.screenCenter(X);
			coolText.y += (textGroup.length * 60) + 200 + offset;
			credGroup.add(coolText);
			textGroup.add(coolText);
		}
	}

	function deleteCoolText()
	{
		while (textGroup.members.length > 0)
		{
			credGroup.remove(textGroup.members[0], true);
			textGroup.remove(textGroup.members[0], true);
		}
	}

	private var sickBeats:Int = 0; //Basically curBeat but won't be skipped if you hold the tab or resize the screen
	public static var closedState:Bool = false;
	override function beatHit()
	{
		super.beatHit();

		if(logoBl != null)
			logoBl.animation.play('bump', true);

		if(gfDance != null) {
			danceLeft = !danceLeft;
			if (danceLeft)
				gfDance.animation.play('danceRight');
			else
				gfDance.animation.play('danceLeft');
		}

		if(!closedState) {
			sickBeats++;
			switch (sickBeats)
			{
				case 1:
					//FlxG.sound.music.stop();
					FlxG.sound.playMusic(Paths.music('freakyMenu'), 0);
					FlxG.sound.music.fadeIn(4, 0, 0.7);
				case 2:
					#if PSYCH_WATERMARKS
					createCoolText(['Psych Engine by'], 15);
					#else
					createCoolText(['ninjamuffin99', 'phantomArcade', 'kawaisprite', 'evilsk8er']);
					#end
				// credTextShit.visible = true;
				case 4:
					#if PSYCH_WATERMARKS
					addMoreText('Shadow Mario', 15);
					addMoreText('RiverOaken', 15);
					addMoreText('shubs', 15);
					#else
					addMoreText('present');
					#end
				// credTextShit.text += '\npresent...';
				// credTextShit.addText();
				case 5:
					deleteCoolText();
				// credTextShit.visible = false;
				// credTextShit.text = 'In association \nwith';
				// credTextShit.screenCenter();
				case 6:
					#if PSYCH_WATERMARKS
					createCoolText(['Not associated', 'with'], -40);
					#else
					createCoolText(['In association', 'with'], -40);
					#end
				case 8:
					addMoreText('newgrounds', -40);
					ngSpr.visible = true;
				// credTextShit.text += '\nNewgrounds';
				case 9:
					deleteCoolText();
					ngSpr.visible = false;
				// credTextShit.visible = false;

				// credTextShit.text = 'Shoutouts Tom Fulp';
				// credTextShit.screenCenter();
				case 10:
					createCoolText([curWacky[0]]);
				// credTextShit.visible = true;
				case 12:
					addMoreText(curWacky[1]);
				// credTextShit.text += '\nlmao';
				case 13:
					deleteCoolText();
				// credTextShit.visible = false;
				// credTextShit.text = "Friday";
				// credTextShit.screenCenter();
				case 14:
					addMoreText('Friday');
				// credTextShit.visible = true;
				case 15:
					addMoreText('Night');
				// credTextShit.text += '\nNight';
				case 16:
					addMoreText('Funkin'); // credTextShit.text += '\nFunkin';

				case 17:
					skipIntro();
			}
		}
	}

	var skippedIntro:Bool = false;
	var increaseVolume:Bool = false;
	function skipIntro():Void
	{
		if (!skippedIntro)
		{
			if (playJingle) //Ignore deez
			{
				var easteregg:String = FlxG.save.data.psychDevsEasterEgg;
				if (easteregg == null) easteregg = '';
				easteregg = easteregg.toUpperCase();

				var sound:FlxSound = null;
				switch(easteregg)
				{
					case 'RIVER':
						sound = FlxG.sound.play(Paths.sound('JingleRiver'));
					case 'SHUBS':
						sound = FlxG.sound.play(Paths.sound('JingleShubs'));
					case 'SHADOW':
						FlxG.sound.play(Paths.sound('JingleShadow'));
					case 'BBPANZU':
						sound = FlxG.sound.play(Paths.sound('JingleBB'));

					default: //Go back to normal ugly ass boring GF
						remove(ngSpr);
						remove(credGroup);
						FlxG.camera.flash(FlxColor.WHITE, 2);
						skippedIntro = true;
						playJingle = false;

						FlxG.sound.playMusic(Paths.music('freakyMenu'), 0);
						FlxG.sound.music.fadeIn(4, 0, 0.7);
						return;
				}

				transitioning = true;
				if(easteregg == 'SHADOW')
				{
					new FlxTimer().start(3.2, function(tmr:FlxTimer)
					{
						remove(ngSpr);
						remove(credGroup);
						FlxG.camera.flash(FlxColor.WHITE, 0.6);
						transitioning = false;
					});
				}
				else
				{
					remove(ngSpr);
					remove(credGroup);
					FlxG.camera.flash(FlxColor.WHITE, 3);
					sound.onComplete = function() {
						FlxG.sound.playMusic(Paths.music('freakyMenu'), 0);
						FlxG.sound.music.fadeIn(4, 0, 0.7);
						transitioning = false;
					};
				}
				playJingle = false;
			}
			else //Default! Edit this one!!
			{
				remove(ngSpr);
				remove(credGroup);
				FlxG.camera.flash(FlxColor.WHITE, 4);

				var easteregg:String = FlxG.save.data.psychDevsEasterEgg;
				if (easteregg == null) easteregg = '';
				easteregg = easteregg.toUpperCase();
				#if TITLE_SCREEN_EASTER_EGG
				if(easteregg == 'SHADOW')
				{
					FlxG.sound.music.fadeOut();
					if(FreeplayState.vocals != null)
					{
						FreeplayState.vocals.fadeOut();
					}
				}
				#end
			}
			skippedIntro = true;
		}
	}
}
