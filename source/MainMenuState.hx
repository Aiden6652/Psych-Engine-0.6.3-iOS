package;

#if desktop
import Discord.DiscordClient;
#end
import flixel.FlxG;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.addons.transition.FlxTransitionableState;
import flixel.effects.FlxFlicker;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.text.FlxText;
import flixel.math.FlxMath;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import lime.app.Application;
import Achievements;
import editors.MasterEditorMenu;
import flixel.input.keyboard.FlxKey;
import flixel.graphics.FlxGraphic;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;
import openfl.geom.Point;

using StringTools;

class MainMenuState extends MusicBeatState
{
	public static var psychEngineVersion:String = '0.6.3'; //This is also used for Discord RPC
	public static var curSelected:Int = 0;

	public var menuItems:FlxTypedGroup<FlxSprite>;
	private var camGame:FlxCamera;
	private var camAchievement:FlxCamera;
	
	var optionShit:Array<String> = [
		'story_mode',
		'freeplay',
		#if MODS_ALLOWED 'mods', #end
		#if ACHIEVEMENTS_ALLOWED 'awards', #end
		'credits',
		'options'
	];

	public var magenta:FlxSprite;
	// [AE-iOS] 暴露默认底给 AECover，便于第一天套把它隐藏掉
	public var menuBG:FlxSprite;
	// [AE-iOS] AE 按钮已切成"白色版/紫色版"两张图，选中时切换
	var btnIdle:Array<FlxGraphic> = [];
	var btnSel:Array<FlxGraphic> = [];
	var camFollow:FlxObject;
	var camFollowPos:FlxObject;
	var debugKeys:Array<FlxKey>;

	override function create()
	{
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();

		#if MODS_ALLOWED
		Paths.pushGlobalMods();
		#end
		WeekData.loadTheFirstEnabledMod();

		#if desktop
		// Updating Discord Rich Presence
		DiscordClient.changePresence("In the Menus", null);
		#end
		debugKeys = ClientPrefs.copyKey(ClientPrefs.keyBinds.get('debug_1'));

		camGame = new FlxCamera();
		camAchievement = new FlxCamera();
		camAchievement.bgColor.alpha = 0;

		FlxG.cameras.reset(camGame);
		FlxG.cameras.add(camAchievement, false);
		FlxG.cameras.setDefaultDrawTarget(camGame, true);

		transIn = FlxTransitionableState.defaultTransIn;
		transOut = FlxTransitionableState.defaultTransOut;

		persistentUpdate = persistentDraw = true;

		var yScroll:Float = Math.max(0.25 - (0.05 * (optionShit.length - 4)), 0.1);
		var bg:FlxSprite = new FlxSprite(-80).loadGraphic(Paths.image('menuBG'));
		bg.scrollFactor.set(0, yScroll);
		bg.setGraphicSize(Std.int(bg.width * 1.175));
		bg.updateHitbox();
		bg.screenCenter();
		bg.antialiasing = ClientPrefs.globalAntialiasing;
		add(bg);
		menuBG = bg;

		camFollow = new FlxObject(0, 0, 1, 1);
		camFollowPos = new FlxObject(0, 0, 1, 1);
		add(camFollow);
		add(camFollowPos);

		magenta = new FlxSprite(-80).loadGraphic(Paths.image('menuDesat'));
		magenta.scrollFactor.set(0, yScroll);
		magenta.setGraphicSize(Std.int(magenta.width * 1.175));
		magenta.updateHitbox();
		magenta.screenCenter();
		magenta.visible = false;
		magenta.antialiasing = ClientPrefs.globalAntialiasing;
		magenta.color = 0xFFfd719b;
		add(magenta);
		
		// magenta.scrollFactor.set();

		menuItems = new FlxTypedGroup<FlxSprite>();
		add(menuItems);

		// [AE-iOS] AE 按钮图集每帧 644x124 且带非零 frameX/frameY（width==frameWidth，本无需裁剪）。
		// stock 的 screenCenter(X) 不认这个帧偏移，导致按钮被横向推出屏幕、逐项纵向错开
		// （你看到的 "LAY / FR / ARDS / DITS" 半个词溢出就是这个原因）。
		// 这里：清零帧偏移 + 固定等比缩放 + 居中竖排。
		var btnScale:Float = 0.48;
		var btnGap:Float = 64;
		var topY:Float = (FlxG.height - ((optionShit.length - 1) * btnGap)) / 2;

		for (i in 0...optionShit.length)
		{
			var nm:String = 'mainmenu/menu_' + optionShit[i];
			btnIdle[i] = splitBtn(nm, false);
			btnSel[i] = splitBtn(nm, true);

			var menuItem:FlxSprite = new FlxSprite(0, topY + i * btnGap);
			if (btnIdle[i] != null) menuItem.loadGraphic(btnIdle[i]);
			menuItem.ID = i;
			menuItem.scale.set(btnScale, btnScale);
			menuItem.updateHitbox();
			menuItem.screenCenter(X);
			menuItems.add(menuItem);
			menuItem.scrollFactor.set();
			menuItem.antialiasing = ClientPrefs.globalAntialiasing;
		}

		FlxG.camera.follow(camFollowPos, null, 1);

		var versionShit:FlxText = new FlxText(12, FlxG.height - 44, 0, "Psych Engine v" + psychEngineVersion, 12);
		versionShit.scrollFactor.set();
		versionShit.setFormat("VCR OSD Mono", 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		versionShit.antialiasing = ClientPrefs.globalAntialiasing;
		add(versionShit);
		var versionShit:FlxText = new FlxText(12, FlxG.height - 24, 0, "Friday Night Funkin' v" + Application.current.meta.get('version'), 12);
		versionShit.scrollFactor.set();
		versionShit.setFormat("VCR OSD Mono", 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		versionShit.antialiasing = ClientPrefs.globalAntialiasing;
		add(versionShit);

		// NG.core.calls.event.logEvent('swag').send();

		changeItem();

		// AE 动态封面（数据驱动；无 AE 菜单数据则静默跳过，保留 PE 默认）
		AECover.apply(this);

		#if ACHIEVEMENTS_ALLOWED
		Achievements.loadAchievements();
		var leDate = Date.now();
		if (leDate.getDay() == 5 && leDate.getHours() >= 18) {
			var achieveID:Int = Achievements.getAchievementIndex('friday_night_play');
			if(!Achievements.isAchievementUnlocked(Achievements.achievementsStuff[achieveID][2])) { //It's a friday night. WEEEEEEEEEEEEEEEEEE
				Achievements.achievementsMap.set(Achievements.achievementsStuff[achieveID][2], true);
				giveAchievement();
				ClientPrefs.saveSettings();
			}
		}
		#end

		#if mobile
		addVirtualPad(UP_DOWN, A_B_E);
		#end

		super.create();
	}

	#if ACHIEVEMENTS_ALLOWED
	// Unlocks "Freaky on a Friday Night" achievement
	function giveAchievement() {
		add(new AchievementObject('friday_night_play', camAchievement));
		FlxG.sound.play(Paths.sound('confirmMenu'), 0.7);
		trace('Giving achievement "friday_night_play"');
	}
	#end

	var selectedSomethin:Bool = false;

	override function update(elapsed:Float)
	{
		if (FlxG.sound.music.volume < 0.8)
		{
			FlxG.sound.music.volume += 0.5 * FlxG.elapsed;
			if(FreeplayState.vocals != null) FreeplayState.vocals.volume += 0.5 * elapsed;
		}

		var lerpVal:Float = CoolUtil.boundTo(elapsed * 7.5, 0, 1);
		camFollowPos.setPosition(FlxMath.lerp(camFollowPos.x, camFollow.x, lerpVal), FlxMath.lerp(camFollowPos.y, camFollow.y, lerpVal));

		if (!selectedSomethin)
		{
			if (controls.UI_UP_P)
			{
				FlxG.sound.play(Paths.sound('scrollMenu'));
				changeItem(-1);
			}

			if (controls.UI_DOWN_P)
			{
				FlxG.sound.play(Paths.sound('scrollMenu'));
				changeItem(1);
			}

			if (controls.BACK)
			{
				selectedSomethin = true;
				FlxG.sound.play(Paths.sound('cancelMenu'));
				MusicBeatState.switchState(new TitleState());
			}

			if (controls.ACCEPT)
			{
					selectedSomethin = true;
					FlxG.sound.play(Paths.sound('confirmMenu'));

					if(ClientPrefs.flashing) FlxFlicker.flicker(magenta, 1.1, 0.15, false);

					menuItems.forEach(function(spr:FlxSprite)
					{
						if (curSelected != spr.ID)
						{
							FlxTween.tween(spr, {alpha: 0}, 0.4, {
								ease: FlxEase.quadOut,
								onComplete: function(twn:FlxTween)
								{
									spr.kill();
								}
							});
						}
						else
						{
							FlxFlicker.flicker(spr, 1, 0.06, false, false, function(flick:FlxFlicker)
							{
								var daChoice:String = optionShit[curSelected];

								switch (daChoice)
								{
									case 'story_mode':
						// [AE-iOS] 进 story 推镜（相机拉近后再切场景，切换前复位 zoom）
						FlxTween.tween(FlxG.camera, {zoom: 1.3}, 0.5, {ease: FlxEase.cubeIn, onComplete: function(t:FlxTween)
						{
							FlxG.camera.zoom = 1;
							MusicBeatState.switchState(new StoryMenuState());
						}});
									case 'freeplay':
										MusicBeatState.switchState(new FreeplayState());
									#if MODS_ALLOWED
									case 'mods':
										MusicBeatState.switchState(new ModsMenuState());
									#end
									case 'awards':
										MusicBeatState.switchState(new AchievementsMenuState());
									case 'credits':
										MusicBeatState.switchState(new CreditsState());
									case 'options':
										LoadingState.loadAndSwitchState(new options.OptionsState());
								}
							});
						}
					});
			}
			#if (desktop || mobile)
			else if (FlxG.keys.anyJustPressed(debugKeys) #if mobile || _virtualpad.buttonE.justPressed #end)
			{
				selectedSomethin = true;
				MusicBeatState.switchState(new MasterEditorMenu());
			}
			#end
		}

		super.update(elapsed);

		menuItems.forEach(function(spr:FlxSprite)
		{
			spr.screenCenter(X);
		});
	}

	// [AE-iOS] AE 按钮图是「左半=白色版 / 右半=紫色选中版」并排的一张 1288x124。
	// 直接按 x 切两半，彻底绕开图集里错误的 frameX/frameY
	// （之前正是它把按钮推出屏幕、让左半被裁只剩 "LAY/FR/ARDS"、并露出右半紫条）。
	static function splitBtn(name:String, sel:Bool):FlxGraphic
	{
		try
		{
			var full:FlxGraphic = Paths.image(name);
			if (full == null || full.bitmap == null) return null;
			var bmd = full.bitmap;
			var w:Int = Std.int(bmd.width / 2);
			var h:Int = bmd.height;
			if (w <= 0 || h <= 0) return null;
			var out = new BitmapData(w, h, true, 0x00000000);
			out.copyPixels(bmd, new Rectangle(sel ? w : 0, 0, w, h), new Point(0, 0));
			return FlxGraphic.fromBitmapData(out);
		}
		catch (e:Dynamic)
		{
			trace('[AE-iOS] splitBtn failed: ' + e);
			return null;
		}
	}

	function changeItem(huh:Int = 0)
	{
		curSelected += huh;

		if (curSelected >= menuItems.length)
			curSelected = 0;
		if (curSelected < 0)
			curSelected = menuItems.length - 1;

		menuItems.forEach(function(spr:FlxSprite)
		{
			var sel:Bool = (spr.ID == curSelected);
			var g:FlxGraphic = sel ? btnSel[spr.ID] : btnIdle[spr.ID];
			if (g != null) spr.loadGraphic(g);
			var sc:Float = sel ? 0.58 : 0.48; // [AE-iOS] 选中项放大
			spr.scale.set(sc, sc);
			spr.updateHitbox();
			spr.screenCenter(X);

			if (sel)
			{
				var add:Float = 0;
				if(menuItems.length > 4) {
					add = menuItems.length * 8;
				}
				camFollow.setPosition(spr.getGraphicMidpoint().x, spr.getGraphicMidpoint().y - add);
			}
		});
	}
}
