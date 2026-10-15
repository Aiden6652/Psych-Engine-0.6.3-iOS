package;

/**
 * [AE-iOS] AE 主菜单视觉还原器（「第一天」套）
 *
 * 依据 AE PC 端实机录屏还原第一天主菜单：
 *   - menus/mainmenu/layer1~5.png  分层背景：layer1 夜空 → layer2 城市建筑 → layer3/4/5 悬挂锁链
 *       （layer6 是"腐蚀黑手"层，属第二天以后，第一天不叠）
 *   - menus/mainmenu/floatingBf.png + .xml  左侧漂浮 Boyfriend 动画
 *
 * 关键：AE 这些素材路径都在 images/menus/mainmenu/ 下，经 Paths.image 加载
 * （iOS 走 SUtil.resolveCI 大小写容错）；任意素材缺失都静默跳过该层，绝不抛异常。
 *
 * 注意：旧的 AECover 用的是 mainmenu0~3 + eyemenuglow（"闪眼睛"腐蚀套），
 * 且用 insert(0) 插到 PE 的 menuBG 之下被盖住 —— 本版彻底改为第一天分层素材，
 * 并显式隐藏 PE 默认底（menuBG）。
 */
import flixel.FlxSprite;
import flixel.FlxG;
import MainMenuState;

class AECover
{
	// 第一天背景分层（绘制顺序：先天空、再建筑、最后锁链）
	static var DAY1_LAYERS:Array<String> = [
		'menus/mainmenu/layer1',
		'menus/mainmenu/layer2',
		'menus/mainmenu/layer3',
		'menus/mainmenu/layer4',
		'menus/mainmenu/layer5'
	];

	/**
	 * 在 MainMenuState 上叠加 AE 第一天主菜单视觉。
	 * 背景层按顺序插到最底层，菜单按钮仍在其上（交互不受影响）。
	 */
	public static function apply(state:MainMenuState):Void
	{
		try
		{
			// 1) 藏掉 PE 默认底（menuBG 是 AE 的"眼睛/腐蚀"套，第一天不用）与品红占位
			if (state.menuBG != null)
				state.menuBG.visible = false;
			if (state.magenta != null)
				state.magenta.visible = false;

			// 2) 逐层铺第一天背景（越早插入越靠底：layer1 在最下、layer5 在最上）
			var idx:Int = 0;
			for (name in DAY1_LAYERS)
			{
				var s:FlxSprite = loadImg(name);
				if (s != null)
				{
					coverFull(s);
					s.scrollFactor.set();
					s.antialiasing = ClientPrefs.globalAntialiasing;
					state.insert(idx, s);
					idx++;
				}
			}

			// 3) 左侧漂浮 BF（动画），置于背景之上、按钮之下
			var bf:FlxSprite = loadFloatingBf();
			if (bf != null)
				state.insert(idx, bf);
		}
		catch (e:Dynamic)
		{
			trace('[AE-iOS] AECover.apply failed: ' + e);
		}
	}

	static function loadImg(name:String):FlxSprite
	{
		try
		{
			var s:FlxSprite = new FlxSprite();
			s.loadGraphic(Paths.image(name));
			if (s.graphic == null)
				return null;
			return s;
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}

	static function loadFloatingBf():FlxSprite
	{
		try
		{
			var bf:FlxSprite = new FlxSprite();
			bf.frames = Paths.getSparrowAtlas('menus/mainmenu/floatingBf');
			bf.animation.addByPrefix('float', 'BfFloat', 24, true);
			bf.animation.play('float');
			bf.setGraphicSize(Std.int(FlxG.width * 0.30));
			bf.updateHitbox();
			bf.setPosition(FlxG.width * 0.12, FlxG.height * 0.38);
			bf.scrollFactor.set();
			bf.antialiasing = ClientPrefs.globalAntialiasing;
			return bf;
		}
		catch (e:Dynamic)
		{
			trace('[AE-iOS] floatingBf failed: ' + e);
			return null;
		}
	}

	/** 等比放大铺满屏幕并居中（cover）。 */
	static function coverFull(s:FlxSprite):Void
	{
		if (s == null || s.graphic == null)
			return;
		var sc:Float = Math.max(FlxG.width / s.width, FlxG.height / s.height);
		if (sc > 0 && sc == sc) // 排除 NaN
		{
			s.scale.set(sc, sc);
			s.updateHitbox();
		}
		s.setPosition((FlxG.width - s.width) / 2, (FlxG.height - s.height) / 2);
	}
}
