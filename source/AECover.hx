package;

/**
 * [AE-iOS] AE 主菜单视觉还原器
 *
 * 用 AE 真实素材重绘主菜单背景：
 *   - mainmenu0~3.png  （AE 动态封面，4 帧循环切换）
 *   - corruptionLogoPINK.png（AE 粉色 logo）
 *   - eyemenuglow.png  （招牌眼睛辉光，呼吸闪烁）
 *
 * 不再依赖闭源的 data/menuData.json（AE 闭源、该文件根本不存在，
 * 旧版 useAE() 因此永远返回 false，整段封面代码从未执行过）。
 *
 * 所有素材经 Paths.image 加载（iOS 走 SUtil.resolveCI 大小写容错）；
 * 任意素材缺失都静默跳过该层，绝不抛异常。
 */
import flixel.FlxSprite;
import flixel.FlxG;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxTweenType;
import flixel.util.FlxTimer;
import MainMenuState;

class AECover
{
	// AE 动态封面帧（磁盘精确大小写）
	static var coverFrames:Array<String> = ['mainmenu0', 'mainmenu1', 'mainmenu2', 'mainmenu3'];
	static var coverIdx:Int = 0;
	static var coverSprite:FlxSprite = null;

	/**
	 * 在 MainMenuState 上叠加 AE 主菜单视觉。
	 * 背景层用 insert(0/1/2) 塞到菜单按钮之下，避免盖住交互。
	 */
	public static function apply(state:MainMenuState):Void
	{
		try
		{
			// 关掉 PE 默认品红底，露出 AE 封面
			if (state.magenta != null)
				state.magenta.visible = false;

			// 1) AE 动态封面背景（mainmenu0~3 循环切换，每 3.2s 一帧）
			var bg:FlxSprite = loadImg(coverFrames[0]);
			if (bg != null)
			{
				fitFull(bg);
				bg.scrollFactor.set();
				coverSprite = bg;
				state.insert(0, bg);

				new FlxTimer().start(3.2, function(t:FlxTimer)
				{
					coverIdx = (coverIdx + 1) % coverFrames.length;
					if (coverSprite != null)
					{
						var g:FlxGraphic = loadImgSafe(coverFrames[coverIdx]);
						if (g != null)
						{
							coverSprite.loadGraphic(g);
							fitFull(coverSprite);
						}
					}
				}, 0);
			}

			// 2) AE logo（corruptionLogoPINK）居中偏上
			var logo:FlxSprite = loadImg('corruptionLogoPINK');
			if (logo != null)
			{
				fitWidth(logo, FlxG.width * 0.62);
				logo.setPosition((FlxG.width - logo.width) / 2, FlxG.height * 0.08);
				logo.scrollFactor.set();
				logo.antialiasing = ClientPrefs.globalAntialiasing;
				state.insert(1, logo);
			}

			// 3) 眼睛辉光（eyemenuglow）招牌叠加 + 呼吸
			var eye:FlxSprite = loadImg('eyemenuglow');
			if (eye != null)
			{
				fitWidth(eye, FlxG.width * 0.92);
				eye.setPosition((FlxG.width - eye.width) / 2, (FlxG.height - eye.height) / 2);
				eye.scrollFactor.set();
				eye.alpha = 0.55;
				state.insert(2, eye);
				FlxTween.tween(eye, {alpha: 0.85}, 1.4, {ease: FlxEase.sineInOut, type: FlxTweenType.PINGPONG});
			}
		}
		catch (e:Dynamic)
		{
			trace('[AE-iOS] AECover.apply failed: ' + e);
		}
	}

	static function loadImg(name:String):FlxSprite
	{
		var s:FlxSprite = new FlxSprite();
		s.loadGraphic(Paths.image(name));
		if (s.graphic == null)
			return null;
		return s;
	}

	static function loadImgSafe(name:String):FlxGraphic
	{
		try
		{
			return Paths.image(name);
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}

	/** 等比放大铺满屏幕并居中。 */
	static function fitFull(spr:FlxSprite):Void
	{
		var sc:Float = Math.max(FlxG.width / spr.width, FlxG.height / spr.height);
		if (sc > 0 && sc == sc) // 排除 NaN
		{
			spr.scale.set(sc, sc);
			spr.updateHitbox();
		}
		spr.setPosition((FlxG.width - spr.width) / 2, (FlxG.height - spr.height) / 2);
	}

	/** 按目标宽度等比缩放（保持比例）。 */
	static function fitWidth(spr:FlxSprite, w:Float):Void
	{
		var sc:Float = w / spr.width;
		if (sc > 0 && sc == sc)
		{
			spr.scale.set(sc, sc);
			spr.updateHitbox();
		}
	}
}
