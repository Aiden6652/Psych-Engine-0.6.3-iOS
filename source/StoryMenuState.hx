package;

#if desktop
import Discord.DiscordClient;
#end
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxSubState;
import flixel.addons.transition.FlxTransitionableState;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.group.FlxGroup;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import lime.net.curl.CURLCode;
import flixel.graphics.FlxGraphic;
import WeekData;
#if MODS_ALLOWED
import sys.FileSystem;
#end

using StringTools;

class StoryMenuState extends MusicBeatState
{
	public static var weekCompleted:Map<String, Bool> = new Map<String, Bool>();

	var scoreText:FlxText;

	// [AE-iOS] AE 的 week json 把 weekBackground / weekCharacters 全部留空
	// （AE 用闭源 SoftCodeMenu 自己渲染背景和人物，不走 stock 这两个字段），
	// 导致 stock StoryMenuState 隐藏背景、不渲染人物，露出原生黄色 bgYellow 占位块。
	// 这里按周索引兜底，恢复背景图与人物显示。
	static var AE_BG_FALLBACK:Array<String> = ['stage','halloween','limo','philly','philly','stage','school-pixel','school','tank','stage','stage'];
	static var AE_CHARS_FALLBACK:Array<Array<String>> = [
		['dad','bf','gf'],
		['spooky','bf','gf'],
		['mom','bf','gf'],
		['dad','bf','gf'],
		['pico','bf','gf'],
		['dad','bf','gf'],
		['senpai','bf','gf'],
		['dad','bf','gf'],
		['tankman','bf','gf'],
		['dad','bf','gf'],
		['dad','bf','gf']
	];

	static function aeBgFallback(idx:Int):String
	{
		if (idx < 0) idx = 0;
		return AE_BG_FALLBACK[idx % AE_BG_FALLBACK.length];
	}

	static function aeCharsFallback(idx:Int):Array<String>
	{
		if (idx < 0) idx = 0;
		return AE_CHARS_FALLBACK[idx % AE_CHARS_FALLBACK.length];
	}

	static function aeCharsEmpty(arr:Array<String>):Bool
	{
		return (arr == null || arr.length < 3 || (arr[0] == '' && arr[1] == '' && arr[2] == ''));
	}

	private static var lastDifficultyName:String = '';
	var curDifficulty:Int = 1;

	var txtWeekTitle:FlxText;
	var bgSprite:FlxSprite;

	private static var curWeek:Int = 0;

	var txtTracklist:FlxText;

	var grpWeekText:FlxTypedGroup<MenuItem>;
	var grpWeekCharacters:FlxTypedGroup<MenuCharacter>;

	var grpLocks:FlxTypedGroup<FlxSprite>;

	var difficultySelectors:FlxGroup;
	var sprDifficulty:FlxSprite;
	var leftArrow:FlxSprite;
	var rightArrow:FlxSprite;
	var blackBarThingie:FlxSprite;

	var loadedWeeks:Array<WeekData> = [];

	// [AE-iOS] story 页动态背景：videos/story/MenuVideo<周>.mp4（1280x720、约 11 秒循环）
	#if (MODS_ALLOWED && VIDEOS_ALLOWED)
	var weekVideo:hxvlc.flixel.FlxVideoSprite = null;
	var weekVideoIndex:Int = -1;
	#end
	/// 视频插入位置：AECover 城市分层背景之上、周名列表之下
	var bgInsertIndex:Int = 0;
	/// SELECT YOUR VICTIM 入场动画
	var victimSpr:FlxSprite = null;

	override function create()
	{
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();

		PlayState.isStoryMode = true;
		WeekData.reloadWeekFiles(true);
		if(curWeek >= WeekData.weeksList.length) curWeek = 0;
		persistentUpdate = persistentDraw = true;

		// [AE-iOS] story 页周名列表布局（对齐录屏：行距约 63px、首项基准 127px，1280x720 基准）
		MenuItem.itemSpacing = FlxG.height * 0.0875;
		MenuItem.itemBaseY = FlxG.height * 0.176;

		scoreText = new FlxText(10, 10, 0, "SCORE: 49324858", 36);
		scoreText.antialiasing = ClientPrefs.globalAntialiasing;
		scoreText.setFormat("VCR OSD Mono", 32);

		txtWeekTitle = new FlxText(FlxG.width * 0.7, 10, 0, "", 32);
		txtWeekTitle.setFormat("VCR OSD Mono", 32, FlxColor.WHITE, RIGHT);
		txtWeekTitle.antialiasing = ClientPrefs.globalAntialiasing;
		txtWeekTitle.alpha = 1; // [AE-iOS] 录屏里右上周名是全亮白字

		var rankText:FlxText = new FlxText(0, 10);
		rankText.text = 'RANK: GREAT';
		rankText.setFormat(Paths.font("vcr.ttf"), 32);
		rankText.size = scoreText.size;
		rankText.antialiasing = ClientPrefs.globalAntialiasing;
		rankText.screenCenter(X);

		var ui_tex = Paths.getSparrowAtlas('campaign_menu_UI_assets');
		var bgYellow:FlxSprite = new FlxSprite(0, 56).makeGraphic(FlxG.width, 386, 0xFFF9CF51);
		bgSprite = new FlxSprite(0, 56);
		bgSprite.antialiasing = ClientPrefs.globalAntialiasing;

		grpWeekText = new FlxTypedGroup<MenuItem>();
		add(grpWeekText);

		blackBarThingie = new FlxSprite().makeGraphic(FlxG.width, 56, FlxColor.BLACK);
		add(blackBarThingie);

		grpWeekCharacters = new FlxTypedGroup<MenuCharacter>();

		grpLocks = new FlxTypedGroup<FlxSprite>();
		add(grpLocks);

		#if desktop
		// Updating Discord Rich Presence
		DiscordClient.changePresence("In the Menus", null);
		#end

		var num:Int = 0;
		for (i in 0...WeekData.weeksList.length)
		{
			var weekFile:WeekData = WeekData.weeksLoaded.get(WeekData.weeksList[i]);
			var isLocked:Bool = weekIsLocked(WeekData.weeksList[i]);
			if(!isLocked || !weekFile.hiddenUntilUnlocked)
			{
				loadedWeeks.push(weekFile);
				WeekData.setDirectoryFromWeek(weekFile);
				var weekThing:MenuItem = new MenuItem(0, bgSprite.y + 396, WeekData.weeksList[i]);
				weekThing.y += ((weekThing.height + 20) * num);
				weekThing.targetY = num;
				grpWeekText.add(weekThing);

				weekThing.x = FlxG.width * 0.03; // [AE-iOS] 周名列表左对齐（PC 布局）
				weekThing.scale.set(0.85, 0.85); // [AE-iOS] 对齐录屏列表项大小
				weekThing.updateHitbox();
				weekThing.antialiasing = ClientPrefs.globalAntialiasing;
				// weekThing.updateHitbox();

				// Needs an offset thingie
				if (isLocked)
				{
					var lock:FlxSprite = new FlxSprite(weekThing.width + 10 + weekThing.x);
					lock.frames = ui_tex;
					lock.animation.addByPrefix('lock', 'lock');
					lock.animation.play('lock');
					lock.ID = i;
					lock.antialiasing = ClientPrefs.globalAntialiasing;
					grpLocks.add(lock);
				}
				num++;
			}
		}

		WeekData.setDirectoryFromWeek(loadedWeeks[0]);
		var charArray:Array<String> = loadedWeeks[0].weekCharacters;
		// [AE-iOS] 周数据人物留空时兜底
		if (aeCharsEmpty(charArray)) charArray = aeCharsFallback(0);
		for (char in 0...3)
		{
			var weekCharacterThing:MenuCharacter = new MenuCharacter((FlxG.width * 0.25) * (1 + char) - 150, charArray[char]);
			weekCharacterThing.y += 70;
			grpWeekCharacters.add(weekCharacterThing);
		}

		difficultySelectors = new FlxGroup();
		add(difficultySelectors);

		// [AE-iOS] 难度左右箭头换成 mod 自带的红色箭头图
		leftArrow = new FlxSprite();
		leftArrow.loadGraphic(Paths.image('selectionArrowLEFT'));
		leftArrow.antialiasing = ClientPrefs.globalAntialiasing;
		difficultySelectors.add(leftArrow);

		CoolUtil.difficulties = CoolUtil.defaultDifficulties.copy();
		if(lastDifficultyName == '')
		{
			lastDifficultyName = CoolUtil.defaultDifficulty;
		}
		curDifficulty = Math.round(Math.max(0, CoolUtil.defaultDifficulties.indexOf(lastDifficultyName)));
		
		sprDifficulty = new FlxSprite(0, leftArrow.y);
		sprDifficulty.antialiasing = ClientPrefs.globalAntialiasing;
		difficultySelectors.add(sprDifficulty);

		rightArrow = new FlxSprite();
		rightArrow.loadGraphic(Paths.image('selectionArrowRIGHT'));
		rightArrow.antialiasing = ClientPrefs.globalAntialiasing;
		difficultySelectors.add(rightArrow);

		add(bgYellow);
		bgYellow.visible = false; // [AE-iOS] 隐藏 stock 黄底，story 页用 bgback 城市背景
		add(bgSprite);
		add(grpWeekCharacters);
		grpWeekCharacters.visible = false; // [AE-iOS] story 页不显示周人物
		blackBarThingie.visible = false; // [AE-iOS] 顶部黑条由 chains 链条层替代

		var tracksSprite:FlxSprite = new FlxSprite(FlxG.width * 0.07, bgSprite.y + 425).loadGraphic(Paths.image('Menu_Tracks'));
		tracksSprite.antialiasing = ClientPrefs.globalAntialiasing;
		add(tracksSprite);
		tracksSprite.visible = false; // [AE-iOS] 不需要 stock 的 "SONGS" 标题图

		txtTracklist = new FlxText(FlxG.width * 0.05, tracksSprite.y + 60, 0, "", 32);
		txtTracklist.alignment = CENTER;
		txtTracklist.font = rankText.font;
		txtTracklist.color = 0xFFe55777;
		txtTracklist.antialiasing = ClientPrefs.globalAntialiasing;
		add(txtTracklist);
		// add(rankText);
		add(scoreText);
		add(txtWeekTitle);

		// [AE-iOS] story 页背景：bgback 城市夜景 + 顶部链条（mod 自带素材）
		insertAeBackground();

		changeWeek();
		changeDifficulty();
		showVictimTitle();
		initClock();

        #if mobile
        addVirtualPad(FULL, A_B_X_Y);
        addPadCamera();
        #end

		super.create();
	}

	override function closeSubState() {
		persistentUpdate = true;
		changeWeek();
		super.closeSubState();
	}

	override function update(elapsed:Float)
	{
		// scoreText.setFormat('VCR OSD Mono', 32);
		lerpScore = Math.floor(FlxMath.lerp(lerpScore, intendedScore, CoolUtil.boundTo(elapsed * 30, 0, 1)));
		if(Math.abs(intendedScore - lerpScore) < 10) lerpScore = intendedScore;

		scoreText.text = "WEEK SCORE:" + lerpScore;

		// FlxG.watch.addQuick('font', scoreText.font);

		if (!movedBack && !selectedWeek)
		{
			var upP = controls.UI_UP_P;
			var downP = controls.UI_DOWN_P;
			if (upP)
			{
				changeWeek(-1);
				FlxG.sound.play(Paths.sound('scrollMenu'));
			}

			if (downP)
			{
				changeWeek(1);
				FlxG.sound.play(Paths.sound('scrollMenu'));
			}

			if(FlxG.mouse.wheel != 0)
			{
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
				changeWeek(-FlxG.mouse.wheel);
				changeDifficulty();
			}

			if (controls.UI_RIGHT)
				rightArrow.animation.play('press')
			else
				rightArrow.animation.play('idle');

			if (controls.UI_LEFT)
				leftArrow.animation.play('press');
			else
				leftArrow.animation.play('idle');

			if (controls.UI_RIGHT_P)
				changeDifficulty(1);
			else if (controls.UI_LEFT_P)
				changeDifficulty(-1);
			else if (upP || downP)
				changeDifficulty();

			if(FlxG.keys.justPressed.CONTROL #if (android || ios) || _virtualpad.buttonX.justPressed #end)
			{
				#if (android || ios)
				removeVirtualPad();
				#end
				persistentUpdate = false;
				openSubState(new GameplayChangersSubstate());
			}
			else if(controls.RESET #if (android || ios) || _virtualpad.buttonY.justPressed #end)
			{
				#if (android || ios)
				removeVirtualPad();
				#end
				persistentUpdate = false;
				openSubState(new ResetScoreSubState('', curDifficulty, '', curWeek));
				//FlxG.sound.play(Paths.sound('scrollMenu'));
			}
			else if (controls.ACCEPT)
			{
				selectWeek();
			}
		}

		if (controls.BACK && !movedBack && !selectedWeek)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'));
			movedBack = true;
			MusicBeatState.switchState(new MainMenuState());
		}

		super.update(elapsed);

		// 时钟每 0.5s 才取一次系统时间，避免每帧 new Date 的 GC 压力
		clockTimer += elapsed;
		if (clockTimer >= 0.5)
		{
			clockTimer = 0;
			updateClock();
		}

		grpLocks.forEach(function(lock:FlxSprite)
		{
			lock.y = grpWeekText.members[lock.ID].y;
			lock.visible = (lock.y > FlxG.height / 2);
		});
	}

	var movedBack:Bool = false;
	var selectedWeek:Bool = false;
	var stopspamming:Bool = false;

	function selectWeek()
	{
		if (!weekIsLocked(loadedWeeks[curWeek].fileName))
		{
			if (stopspamming == false)
			{
				FlxG.sound.play(Paths.sound('confirmMenu'));

				grpWeekText.members[curWeek].startFlashing();

				for (char in grpWeekCharacters.members)
				{
					if (char.character != '' && char.hasConfirmAnimation)
					{
						char.animation.play('confirm');
					}
				}
				stopspamming = true;
			}

			// We can't use Dynamic Array .copy() because that crashes HTML5, here's a workaround.
			var songArray:Array<String> = [];
			var leWeek:Array<Dynamic> = loadedWeeks[curWeek].songs;
			for (i in 0...leWeek.length) {
				songArray.push(leWeek[i][0]);
			}

			// Nevermind that's stupid lmao
			PlayState.storyPlaylist = songArray;
			PlayState.isStoryMode = true;
			selectedWeek = true;

			// [AE-iOS] 选中周后进入「预览」态：周名列表滑到屏幕下半，上方让位给
			// MenuVideo<周> 预览窗（对齐录屏里选中周后的画面）。
			MenuItem.itemBaseY = FlxG.height * 0.60;
			if (weekVideo != null) weekVideo.visible = true;

			var diffic = CoolUtil.getDifficultyFilePath(curDifficulty);
			if(diffic == null) diffic = '';

			PlayState.storyDifficulty = curDifficulty;

			PlayState.SONG = Song.loadFromJson(PlayState.storyPlaylist[0].toLowerCase() + diffic, PlayState.storyPlaylist[0].toLowerCase());
			PlayState.campaignScore = 0;
			PlayState.campaignMisses = 0;
			new FlxTimer().start(1.2, function(tmr:FlxTimer)
			{
				LoadingState.loadAndSwitchState(new PlayState(), true);
				FreeplayState.destroyFreeplayVocals();
			});
		} else {
			FlxG.sound.play(Paths.sound('cancelMenu'));
		}
	}

	var tweenDifficulty:FlxTween;
	function changeDifficulty(change:Int = 0):Void
	{
		curDifficulty += change;

		if (curDifficulty < 0)
			curDifficulty = CoolUtil.difficulties.length-1;
		if (curDifficulty >= CoolUtil.difficulties.length)
			curDifficulty = 0;

		WeekData.setDirectoryFromWeek(loadedWeeks[curWeek]);

		var diff:String = CoolUtil.difficulties[curDifficulty];
		// [AE-iOS] 难度标签改用 mod 自带图：CANON / SAFE / -Playable-
		var diffKey:String = Paths.formatToSongPath(diff);
		var imgName:String = 'safeInfo';
		if (diffKey.indexOf('canon') >= 0) imgName = 'canonInfo';
		else if (diffKey.indexOf('play') >= 0) imgName = 'playable';
		var newImage:FlxGraphic = Paths.image(imgName);

		if(sprDifficulty.graphic != newImage)
		{
			sprDifficulty.loadGraphic(newImage);
			sprDifficulty.alpha = 0;

			if(tweenDifficulty != null) tweenDifficulty.cancel();
			tweenDifficulty = FlxTween.tween(sprDifficulty, {alpha: 1}, 0.07, {onComplete: function(twn:FlxTween)
			{
				tweenDifficulty = null;
			}});
		}

		// [AE-iOS] 标签水平居中、红色箭头分列两侧（对齐录屏布局）
		sprDifficulty.screenCenter(X);
		sprDifficulty.y = FlxG.height * 0.46;
		leftArrow.x = sprDifficulty.x - leftArrow.width - 20;
		leftArrow.y = sprDifficulty.y + (sprDifficulty.height - leftArrow.height) / 2;
		rightArrow.x = sprDifficulty.x + sprDifficulty.width + 20;
		rightArrow.y = leftArrow.y;

		lastDifficultyName = diff;

		#if !switch
		intendedScore = Highscore.getWeekScore(loadedWeeks[curWeek].fileName, curDifficulty);
		#end
	}

	var lerpScore:Int = 0;
	var intendedScore:Int = 0;

	function changeWeek(change:Int = 0):Void
	{
		curWeek += change;

		if (curWeek >= loadedWeeks.length)
			curWeek = 0;
		if (curWeek < 0)
			curWeek = loadedWeeks.length - 1;

		var leWeek:WeekData = loadedWeeks[curWeek];
		WeekData.setDirectoryFromWeek(leWeek);

		var leName:String = leWeek.storyName;
		txtWeekTitle.text = leName.toUpperCase();
		txtWeekTitle.x = FlxG.width - (txtWeekTitle.width + 10);

		var bullShit:Int = 0;

		var unlocked:Bool = !weekIsLocked(leWeek.fileName);
		for (item in grpWeekText.members)
		{
			item.targetY = bullShit - curWeek;
			if (item.targetY == Std.int(0) && unlocked)
				item.alpha = 1;
			else
				item.alpha = 0.6;
			bullShit++;
		}

		var assetName:String = leWeek.weekBackground;
		// [AE-iOS] 周数据 weekBackground 留空时，stock 逻辑会隐藏背景露出原生黄块 -> 兜底取 AE 自带背景图
		if(assetName == null || assetName.length < 1) {
			assetName = aeBgFallback(curWeek);
		}
		bgSprite.loadGraphic(Paths.image('menubackgrounds/menu_' + assetName));
		// [AE-iOS] story 页背景由 MenuVideo<周>.mp4 / AECover 城市分层负责，
		// stock 周背景不透明，留着会把动态背景整块盖住，这里保持隐藏。
		bgSprite.visible = false;
		PlayState.storyWeek = curWeek;

		CoolUtil.difficulties = CoolUtil.defaultDifficulties.copy();
		var diffStr:String = WeekData.getCurrentWeek().difficulties;
		if(diffStr != null) diffStr = diffStr.trim(); //Fuck you HTML5
		difficultySelectors.visible = unlocked;

		if(diffStr != null && diffStr.length > 0)
		{
			var diffs:Array<String> = diffStr.split(',');
			var i:Int = diffs.length - 1;
			while (i > 0)
			{
				if(diffs[i] != null)
				{
					diffs[i] = diffs[i].trim();
					if(diffs[i].length < 1) diffs.remove(diffs[i]);
				}
				--i;
			}

			if(diffs.length > 0 && diffs[0].length > 0)
			{
				CoolUtil.difficulties = diffs;
			}
		}
		
		if(CoolUtil.difficulties.contains(CoolUtil.defaultDifficulty))
		{
			curDifficulty = Math.round(Math.max(0, CoolUtil.defaultDifficulties.indexOf(CoolUtil.defaultDifficulty)));
		}
		else
		{
			curDifficulty = 0;
		}

		var newPos:Int = CoolUtil.difficulties.indexOf(lastDifficultyName);
		//trace('Pos of ' + lastDifficultyName + ' is ' + newPos);
		if(newPos > -1)
		{
			curDifficulty = newPos;
		}
		updateText();
		syncWeekVideo();
	}

	function weekIsLocked(name:String):Bool {
		var leWeek:WeekData = WeekData.weeksLoaded.get(name);
		return (!leWeek.startUnlocked && leWeek.weekBefore.length > 0 && (!weekCompleted.exists(leWeek.weekBefore) || !weekCompleted.get(leWeek.weekBefore)));
	}

	function updateText()
	{
		var weekArray:Array<String> = loadedWeeks[curWeek].weekCharacters;
		// [AE-iOS] 周数据人物留空时兜底
		if (aeCharsEmpty(weekArray)) weekArray = aeCharsFallback(curWeek);
		for (i in 0...grpWeekCharacters.length) {
			grpWeekCharacters.members[i].changeCharacter(weekArray[i]);
		}

		var leWeek:WeekData = loadedWeeks[curWeek];
		var stringThing:Array<String> = [];
		for (i in 0...leWeek.songs.length) {
			stringThing.push(leWeek.songs[i][0]);
		}

		txtTracklist.text = '';
		for (i in 0...stringThing.length)
		{
			txtTracklist.text += stringThing[i] + '\n';
		}

		txtTracklist.text = txtTracklist.text.toUpperCase();

		txtTracklist.screenCenter(X);
		txtTracklist.x -= FlxG.width * 0.35;

		#if !switch
		intendedScore = Highscore.getWeekScore(loadedWeeks[curWeek].fileName, curDifficulty);
		#end
	}

	// ───────────────────────── [AE-iOS] story 页动态背景 ─────────────────────────

	/**
	 * story 页背景层：bgback 城市夜景 + 顶部链条（mod 素材，1920x1080 等比铺满）。
	 * 素材缺失时回落到主菜单那套城市分层背景，保证不黑屏。
	 */
	function insertAeBackground():Void
	{
		var layers:Array<FlxSprite> = [];
		try { layers.push(coverSprite('bgback')); } catch (e:Dynamic) {}
		try { layers.push(coverSprite('chains')); } catch (e:Dynamic) {}

		var idx:Int = 0;
		for (l in layers)
		{
			if (l == null) continue;
			l.antialiasing = ClientPrefs.globalAntialiasing;
			insert(idx, l);
			idx++;
		}

		if (idx > 0)
		{
			bgInsertIndex = idx;
		}
		else
		{
			// 兜底：主菜单同款分层城市背景
			bgInsertIndex = AECover.insertBgInto(this);
		}
		trace('[AE-iOS] story 背景层数 = ' + bgInsertIndex);
	}

	/// 等比铺满屏幕（cover）并居中
	function coverSprite(key:String):FlxSprite
	{
		var s:FlxSprite = new FlxSprite();
		s.loadGraphic(Paths.image(key));
		if (s.graphic == null) return null;

		var sc:Float = Math.max(FlxG.width / s.width, FlxG.height / s.height);
		if (!(sc > 0) || sc != sc) sc = 1;
		s.scale.set(sc, sc);
		s.updateHitbox();
		s.screenCenter();
		s.scrollFactor.set();
		return s;
	}

	inline function weekVideoPath(idx:Int):String
	{
		return Paths.video('story/MenuVideo' + idx);
	}

	/**
	 * 按当前周切换背景视频。
	 *
	 * 找不到视频（没装模组 / 周数超出视频数量）时直接返回，
	 * 由 AECover 的城市分层背景兜底，不会黑屏。
	 */
	function syncWeekVideo():Void
	{
		#if (MODS_ALLOWED && VIDEOS_ALLOWED)
		var idx:Int = curWeek;
		if (idx < 0) idx = 0;
		var path:String = weekVideoPath(idx);

		if (!FileSystem.exists(path))
		{
			// story9 / story9z 没有对应视频 → 退回最后一个可用视频
			var last:Int = 8;
			while (last > 0 && !FileSystem.exists(weekVideoPath(last))) last--;
			if (!FileSystem.exists(weekVideoPath(last))) return;
			idx = last;
			path = weekVideoPath(idx);
		}

		if (weekVideo == null)
		{
			createWeekVideo();
			if (weekVideo == null) return;
		}
		if (idx == weekVideoIndex) return; // 同一周切难度等操作不用重新载入

		// 循环 + 静音：story 页不该盖住菜单音乐，也不播视频原声
		var options:Array<String> = ['--input-repeat=999999', '--no-audio'];
		var loaded:Bool = false;
		try { loaded = weekVideo.load(path, options); } catch (e:Dynamic) { loaded = false; }

		if (!loaded)
		{
			trace('[AE-iOS] story 背景视频加载失败: ' + path);
			weekVideoIndex = -1;
			return;
		}

		weekVideoIndex = idx;
		// load() 之后解码器还没就绪，延后一拍再 play()（与 VideoHandler 同样的做法）
		new FlxTimer().start(0.001, function(_:FlxTimer)
		{
			if (weekVideo == null || weekVideo.bitmap == null) return;
			// --no-audio 之外再压一层：不跟随 Flixel 音量，直接静音
			weekVideo.autoVolumeHandle = false;
			try { weekVideo.bitmap.volume = 0; } catch (e:Dynamic) {}
			try { weekVideo.play(); } catch (e:Dynamic) {}
			// 预览窗只在选中周后露出（浏览态保持 bgback 静态背景，对齐录屏）
			weekVideo.visible = selectedWeek;
		});
		#end
	}

	#if (MODS_ALLOWED && VIDEOS_ALLOWED)
	function createWeekVideo():Void
	{
		try
		{
			// 不要传 (0, 0)：hxvlc 2.x 是 new(?instance, ?x, ?y)，(0,0) 会被当成 instance
			var vs:hxvlc.flixel.FlxVideoSprite = new hxvlc.flixel.FlxVideoSprite();
			vs.antialiasing = false;
			// 插在 AECover 分层背景之上、周名列表之下
			insert(bgInsertIndex, vs);
			if (vs.bitmap != null)
			{
				vs.bitmap.onFormatSetup.add(function():Void fitWeekVideo(vs));
			}
			weekVideo = vs;
		}
		catch (e:Dynamic)
		{
			trace('[AE-iOS] 创建 story 背景视频失败: ' + e);
			weekVideo = null;
		}
	}

	/// 等比铺满（cover）并居中，多余部分裁到屏幕外；基准用相机视口，不用 FlxG。
	function fitWeekVideo(vs:hxvlc.flixel.FlxVideoSprite):Void
	{
		try
		{
			if (vs.bitmap == null) return;
			var bmd = vs.bitmap.bitmapData;
			if (bmd == null) return;

			var viewW:Float = FlxG.width;
			var viewH:Float = FlxG.height;
			try
			{
				if (vs.cameras != null && vs.cameras.length > 0 && vs.cameras[0] != null)
				{
					viewW = vs.cameras[0].width;
					viewH = vs.cameras[0].height;
				}
			}
			catch (e:Dynamic) {}

			if (viewW <= 0 || viewH <= 0)
			{
				viewW = FlxG.width;
				viewH = FlxG.height;
			}

			// 预览窗几何（对齐录屏：选中周后 gameplay 预览约占屏幕 66% 宽、47% 高，
			// 水平居中、自顶部 9% 起）。背景仍是 bgback 静态图，视频只是预览窗。
			var winX:Float = viewW * 0.17;
			var winY:Float = viewH * 0.09;
			var winW:Float = viewW * 0.66;
			var winH:Float = viewH * 0.47;

			// 不能用 setGraphicSize()：它除以当前 frameWidth，而我们和 hxvlc 的
			// onFormatSetup 回调挂在同一个事件上，顺序不保证，会算出灾难性的放大倍数。
			var sc:Float = Math.max(winW / bmd.width, winH / bmd.height);
			if (!(sc > 0) || sc != sc) sc = 1;

			vs.scale.set(sc, sc);
			vs.updateHitbox();
			vs.x = winX + (winW - vs.width) / 2;
			vs.y = winY + (winH - vs.height) / 2;
			vs.scrollFactor.set(0, 0);

			// 只走 FlxSprite 这条路：内层原生 Bitmap 不受相机/scale 管辖，
			// 会带着偏移叠在画面上，造成「偏右 / 右下被裁」。
			vs.bitmap.visible = false;
		}
		catch (e:Dynamic) {}
	}
	#end

	/**
	 * story 页入场动画：SELECT YOUR VICTIM。
	 *
	 * 素材是 1920x1080 的全屏覆盖图（红字居中），这里等比铺满后淡入，
	 * 停留 2 秒再淡出销毁 —— 对应录屏里进 story 页时一闪而过的标题动画。
	 */
	function showVictimTitle():Void
	{
		try
		{
			var spr:FlxSprite = new FlxSprite();
			spr.loadGraphic(Paths.image('selectyourvictim'));
			if (spr.graphic == null) return;

			var sc:Float = FlxG.width / spr.width;
			if (!(sc > 0) || sc != sc) sc = 1;
			spr.scale.set(sc, sc);
			spr.updateHitbox();
			spr.screenCenter();
			spr.scrollFactor.set();
			spr.antialiasing = ClientPrefs.globalAntialiasing;
			spr.alpha = 0;
			add(spr);
			victimSpr = spr;

			FlxTween.tween(spr, {alpha: 1}, 0.35);
			new FlxTimer().start(2.2, function(_:FlxTimer)
			{
				if (victimSpr == null) return;
				FlxTween.tween(victimSpr, {alpha: 0}, 0.5, {onComplete: function(_:FlxTween)
				{
					if (victimSpr != null)
					{
						remove(victimSpr, true);
						victimSpr = null;
					}
				}});
			});
			trace('[AE-iOS] SELECT YOUR VICTIM 入场动画已播放');
		}
		catch (e:Dynamic)
		{
			victimSpr = null;
		}
	}

	/// [AE-iOS] 右下角数字时钟：num0-9.png 拼接 + 日期小字（录屏里时钟随时间跳动）
	var clockDigits:Array<FlxSprite> = [];
	var clockColons:Array<FlxSprite> = [];
	var clockDateTxt:FlxText = null;
	var clockKey:String = '';
	var clockTimer:Float = 0;

	function initClock():Void
	{
		clockDigits = [];
		clockColons = [];
		var dot:Int = Std.int(FlxG.height * 0.012);
		for (i in 0...4)
		{
			var d:FlxSprite = new FlxSprite();
			d.antialiasing = false;
			add(d);
			clockDigits.push(d);

			if (i == 1)
			{
				for (k in 0...2)
				{
					var c:FlxSprite = new FlxSprite().makeGraphic(dot, dot, FlxColor.WHITE);
					c.antialiasing = false;
					add(c);
					clockColons.push(c);
				}
			}
		}

		clockDateTxt = new FlxText(0, 0, 0, '', Std.int(FlxG.height * 0.038));
		clockDateTxt.setFormat(Paths.font("vcr.ttf"), Std.int(FlxG.height * 0.038), FlxColor.WHITE, RIGHT);
		clockDateTxt.antialiasing = ClientPrefs.globalAntialiasing;
		add(clockDateTxt);
		updateClock();
	}

	function updateClock():Void
	{
		var now:Date = Date.now();
		var hh:String = StringTools.lpad(Std.string(now.getHours()), '0', 2);
		var mm:String = StringTools.lpad(Std.string(now.getMinutes()), '0', 2);
		var key:String = hh + ':' + mm;
		if (key == clockKey) return;
		clockKey = key;

		// 数字图约 94~111 x 119，按高度统一缩放，固定步进排列
		var digitH:Float = FlxG.height * 0.185;
		var sc:Float = digitH / 119.0;
		if (!(sc > 0) || sc != sc) sc = 1;
		var step:Float = digitH * 0.8 + 2;
		var digits:Array<String> = [hh.charAt(0), hh.charAt(1), mm.charAt(0), mm.charAt(1)];

		var x:Float = FlxG.width * 0.78 - step * 4;
		var y:Float = FlxG.height * 0.54 - digitH * 0.5;

		for (i in 0...4)
		{
			var d:FlxSprite = clockDigits[i];
			d.loadGraphic(Paths.image('num' + digits[i]));
			if (d.graphic == null) continue;
			d.scale.set(sc, sc);
			d.updateHitbox();
			d.scrollFactor.set();
			d.x = x + i * step;
			d.y = y;
		}

		// 冒号两枚白点，夹在第 2、3 位数字之间
		var cx:Float = x + 2 * step;
		var gap:Float = FlxG.height * 0.012;
		var cy:Float = y + digitH * 0.5;
		clockColons[0].x = cx - gap * 1.5;
		clockColons[0].y = cy - gap * 2.2;
		clockColons[1].x = cx - gap * 1.5;
		clockColons[1].y = cy + gap * 1.2;
		for (c in clockColons) c.scrollFactor.set();

		// 日期小字（对齐录屏里的 "30 JAN"）
		var months:Array<String> = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
		if (clockDateTxt != null)
		{
			clockDateTxt.text = now.getDate() + ' ' + months[now.getMonth()];
			clockDateTxt.x = FlxG.width * 0.94 - clockDateTxt.width;
			clockDateTxt.y = y - clockDateTxt.height - 4;
			clockDateTxt.scrollFactor.set();
		}
	}

	override function destroy():Void
	{
		#if (MODS_ALLOWED && VIDEOS_ALLOWED)
		if (weekVideo != null)
		{
			try { weekVideo.destroy(); } catch (e:Dynamic) {}
			weekVideo = null;
		}
		#end
		super.destroy();
	}
}
