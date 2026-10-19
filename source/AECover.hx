package;

/**
 * [AE-iOS] AE 主菜单视觉还原器（「第一天」套）
 *
 * 依据 AE PC 端实机录屏还原第一天主菜单：
 *   - menus/mainmenu/layer1~5.png  分层背景：layer1 夜空 → layer2 城市建筑 → layer3/4/5 悬挂锁链
 *       （layer6 是"腐蚀黑手"层，属第二天以后，第一天不叠）
 *   - menus/mainmenu/floatingBf.png + .xml  左侧漂浮 Boyfriend 动画
 *
 * ⚠ 重要：这些 PNG 画布很大（4096×2048 等），但**实际画面只占其中一小块，四周是大片透明留白**。
 * 若按整张画布做 cover 缩放，画面会被缩成屏幕中央一小块（之前就是这个 bug）。
 * 因此这里按每层「不透明内容边界」(content bbox) 来缩放定位，让真实画面铺满屏幕。
 */
import flixel.FlxSprite;
import flixel.FlxG;
import MainMenuState;

class AECover
{
	// 第一天背景分层：name -> [canvasW, canvasH, contentL, contentT, contentR, contentB]
	// bbox 由离线 PIL 对 alpha 通道求 getbbox() 得到（见构建期脚本），运行时直接查表，避免大图扫描卡顿。
	static var DAY1_LAYERS:Array<Array<Dynamic>> = [
		['menus/mainmenu/layer1', 4096, 2048,  14,  79, 2438, 1748],
		['menus/mainmenu/layer2', 4096, 2048,  12, 102, 2484, 1455],
		['menus/mainmenu/layer3', 2048, 2048,  22,   0, 1489, 1502],
		['menus/mainmenu/layer4', 1024, 4096,  33,   2,  881, 2599],
		['menus/mainmenu/layer5', 4096, 4096,  42,  19, 2598, 3586]
	];

	public static function apply(state:MainMenuState):Void
	{
		try
		{
			if (state.menuBG != null) state.menuBG.visible = false;
			if (state.magenta != null) state.magenta.visible = false;

			var idx:Int = 0;
			for (l in DAY1_LAYERS)
			{
				var s:FlxSprite = contentCover(cast l[0], cast l[2], cast l[3], cast l[4], cast l[5]);
				if (s != null)
				{
					s.antialiasing = ClientPrefs.globalAntialiasing;
					state.insert(idx, s);
					idx++;
				}
			}

			// 左侧漂浮 BF（动画），置于背景之上、按钮之下
			var bf:FlxSprite = loadFloatingBf();
			if (bf != null) state.insert(idx, bf);
		}
		catch (e:Dynamic)
		{
			trace('[AE-iOS] AECover.apply failed: ' + e);
		}
	}

	/** 按不透明内容边界铺满屏幕（cover）：内容外接矩形等比放大到覆盖全屏并居中。 */
	static function contentCover(name:String, l:Float, t:Float, r:Float, b:Float):FlxSprite
	{
		try
		{
			var s:FlxSprite = new FlxSprite();
			s.loadGraphic(Paths.image(name));
			if (s.graphic == null) return null;

			var cw:Float = r - l;
			var ch:Float = b - t;
			if (cw <= 0 || ch <= 0) return null;

			var sc:Float = Math.max(FlxG.width / cw, FlxG.height / ch);
			if (!(sc > 0) || sc != sc) return null;
			s.scale.set(sc, sc);
			s.updateHitbox();

			// 让内容中心落在屏幕中心
			s.x = FlxG.width * 0.5 - (l + cw * 0.5) * sc;
			s.y = FlxG.height * 0.5 - (t + ch * 0.5) * sc;
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
