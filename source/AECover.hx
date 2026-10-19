package;

/**
 * [AE-iOS] AE 主菜单 / Story 页共用的「第一天」背景绘制。
 *
 * menus/mainmenu/layer1~5.png 分层背景：layer1 夜空 → layer2 城市建筑 → layer3/4/5 悬挂锁链
 * （layer6 是"腐蚀黑手"层，属第二天以后，第一天不叠）
 *
 * ⚠ 这些 PNG 画布很大（4096×2048 等），实际画面只占其中一块、四周是大片透明留白。
 * 若按整张画布 cover，画面会被缩成屏幕中央一小块。故按每层「不透明内容边界」(bbox) 缩放定位。
 */
import flixel.FlxSprite;
import flixel.FlxG;
import flixel.FlxGroup;
import MainMenuState;

class AECover
{
	private typedef LayerDef = { name:String, l:Float, t:Float, r:Float, b:Float };

	// bbox 由离线 PIL 对 alpha 通道 getbbox() 得到
	static var DAY1_LAYERS:Array<LayerDef> = [
		{ name: 'menus/mainmenu/layer1', l: 14, t: 79, r: 2438, b: 1748 },
		{ name: 'menus/mainmenu/layer2', l: 12, t: 102, r: 2484, b: 1455 },
		{ name: 'menus/mainmenu/layer3', l: 22, t: 0, r: 1489, b: 1502 },
		{ name: 'menus/mainmenu/layer4', l: 33, t: 2, r: 881, b: 2599 },
		{ name: 'menus/mainmenu/layer5', l: 42, t: 19, r: 2598, b: 3586 }
	];

	public static function apply(state:MainMenuState):Void
	{
		try
		{
			if (state.menuBG != null) state.menuBG.visible = false;
			if (state.magenta != null) state.magenta.visible = false;

			var idx:Int = insertBgInto(state);

			var bf:FlxSprite = loadFloatingBf();
			if (bf != null) state.insert(idx, bf);
		}
		catch (e:Dynamic)
		{
			trace('[AE-iOS] AECover.apply failed: ' + e);
		}
	}

	/** 把第一天分层背景插到目标容器最底层，返回下一个可用索引。 */
	public static function insertBgInto(target:FlxGroup):Int
	{
		var idx:Int = 0;
		for (l in DAY1_LAYERS)
		{
			var s:FlxSprite = contentCover(l);
			if (s != null)
			{
				s.antialiasing = ClientPrefs.globalAntialiasing;
				target.insert(idx, s);
				idx++;
			}
		}
		return idx;
	}

	/** 按不透明内容边界铺满屏幕（cover）。 */
	static function contentCover(l:LayerDef):FlxSprite
	{
		try
		{
			var s:FlxSprite = new FlxSprite();
			s.loadGraphic(Paths.image(l.name));
			if (s.graphic == null) return null;

			var cw:Float = l.r - l.l;
			var ch:Float = l.b - l.t;
			if (cw <= 0 || ch <= 0) return null;

			var sc:Float = Math.max(FlxG.width / cw, FlxG.height / ch);
			if (!(sc > 0) || sc != sc) return null;
			s.scale.set(sc, sc);
			s.updateHitbox();

			s.x = FlxG.width * 0.5 - (l.l + cw * 0.5) * sc;
			s.y = FlxG.height * 0.5 - (l.t + ch * 0.5) * sc;
			s.scrollFactor.set();
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
}
