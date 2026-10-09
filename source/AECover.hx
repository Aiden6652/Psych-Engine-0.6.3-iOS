package;

/**
 * [AE-iOS] AE 主菜单动态还原器
 *
 * 读取**外部资源**（iPad 上 PE 的 mods/ 或 assets/）中的：
 *   data/menuData.json、data/menuPositions.json
 * 并用 AE 真实素材（menus/mainmenu/*）重绘主菜单背景。
 *
 * 关键：必须走 mods 感知的 Paths.*（Paths.getTextFromFile / Paths.image /
 * Paths.getSparrowAtlas），不能用 Assets.getText / Assets.exists ——
 * 后者只读打进包里的资源，裸引擎下永远读不到外部资源。
 *
 * 任何数据/素材缺失都静默降级到 PE 默认菜单，绝不抛异常。
 */
import flixel.FlxSprite;
import flixel.FlxG;
import haxe.Json;
import MainMenuState;

class AECover
{
	public static var menuData:Dynamic = null;
	public static var menuPos:Dynamic = null;
	private static var loaded:Bool = false;

	/** 尝试加载菜单配方（只一次）。任何失败静默忽略。 */
	public static function tryLoad():Void
	{
		if (loaded) return;
		loaded = true;
		menuData = readJson('data/menuData.json');
		menuPos  = readJson('data/menuPositions.json');
	}

	static function readJson(key:String):Dynamic
	{
		try
		{
			var s:String = Paths.getTextFromFile(key);
			if (s != null && s.length > 2) return Json.parse(s);
		}
		catch (e:Dynamic) {}
		return null;
	}

	/** 是否启用 AE 主菜单。useOldMenu=true 或数据缺失 → false（走 PE 默认）。 */
	public static function useAE():Bool
	{
		tryLoad();
		if (menuData == null) return false;
		if (menuData.useOldMenu == true) return false;
		return true;
	}

	static function img(name:String):FlxSprite
	{
		try
		{
			var s:FlxSprite = new FlxSprite();
			s.loadGraphic(Paths.image(name));
			if (s.graphic == null) return null;
			return s;
		}
		catch (e:Dynamic) { return null; }
	}

	/** 等比放大铺满屏幕并居中。 */
	static function fitFull(spr:FlxSprite):Void
	{
		try
		{
			var sc:Float = Math.max(FlxG.width / spr.width, FlxG.height / spr.height);
			if (sc > 0 && sc == sc) // 排除 NaN
			{
				spr.scale.set(sc, sc);
				spr.updateHitbox();
			}
			spr.setPosition((FlxG.width - spr.width) / 2, (FlxG.height - spr.height) / 2);
		}
		catch (e:Dynamic) {}
	}

	/**
	 * 在 MainMenuState 上叠加 AE 主菜单视觉。
	 * 目前恢复：放映机底色 + 光束 + BF 浮动立绘。
	 * （菜单文字/交互、STORY 页、freeplay 电子钟等后续阶段单独还原。）
	 */
	public static function apply(state:MainMenuState):Void
	{
		if (!useAE()) return;

		try
		{
			// 关掉 PE 默认品红底，改用 AE 放映机底色
			if (state.magenta != null) state.magenta.visible = false;

			// 底色：放映机场景
			var bg:FlxSprite = img('menus/mainmenu/right1');
			if (bg != null) { fitFull(bg); state.add(bg); }

			// 光束叠加
			var rays:FlxSprite = img('menus/mainmenu/lightRays');
			if (rays != null) { fitFull(rays); rays.alpha = 0.7; state.add(rays); }

			// BF 浮动立绘
			addFloatingBF(state);
		}
		catch (e:Dynamic)
		{
			trace('[AE-iOS] AECover.apply failed: ' + e);
		}
	}

	static function addFloatingBF(state:MainMenuState):Void
	{
		try
		{
			var spr:FlxSprite = new FlxSprite();
			spr.frames = Paths.getSparrowAtlas('menus/mainmenu/floatingBf');
			if (spr.frames == null) return;
			spr.animation.addByPrefix('float', 'BfFloat', 12, true);
			spr.animation.play('float');
			spr.antialiasing = ClientPrefs.globalAntialiasing;
			spr.scale.set(0.55, 0.55);
			spr.updateHitbox();
			spr.setPosition(FlxG.width * 0.08, FlxG.height * 0.16);
			state.add(spr);
		}
		catch (e:Dynamic) {}
	}
}
