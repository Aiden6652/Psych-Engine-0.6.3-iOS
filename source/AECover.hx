package;

/**
 * AE (APlayer's Engine) 动态封面 / 主菜单分层渲染器
 * 数据驱动：读取 assets/data/menuData.json + menuPositions.json，
 * 按坐标合成各图层。数据或素材缺失时静默回退到 PE 默认菜单，绝不抛异常。
 *
 * 注：AE 原版这些逻辑在闭源 exe 里（SoftCodeMenu）。此处为在 PE 框架上的
 * 视觉还原，图层命名/坐标沿用 menuPositions.json 的编辑器数据。
 */
import flixel.FlxSprite;
import flixel.FlxG;
import openfl.utils.Assets;
import haxe.Json;
import MainMenuState;

class AECover
{
	public static var menuData:Dynamic = null;
	public static var menuPos:Dynamic = null;
	private static var loaded:Bool = false;

	/** 尝试加载菜单数据（只加载一次）。任何失败都静默忽略。 */
	public static function tryLoad():Void
	{
		if (loaded) return;
		loaded = true;
		try
		{
			var d:String = Assets.getText('assets/data/menuData.json');
			var p:String = Assets.getText('assets/data/menuPositions.json');
			if (d != null && d.length > 2) menuData = Json.parse(d);
			if (p != null && p.length > 2) menuPos = Json.parse(p);
		}
		catch (e:Dynamic)
		{
			menuData = null;
			menuPos = null;
		}
	}

	/** 是否启用 AE 动态封面。useOldMenu=true 或数据缺失则返回 false。 */
	public static function useAE():Bool
	{
		tryLoad();
		if (menuData == null) return false;
		if (menuData.useOldMenu == true) return false;
		return true;
	}

	static function pos(key:String):Array<Float>
	{
		if (menuPos == null) return null;
		var v:Dynamic = Reflect.field(menuPos, key);
		if (v == null) return null;
		var arr:Array<Float> = [cast v[0], cast v[1]];
		return arr;
	}

	/** menuPositions 里 [-3.7,-3.7] 这类异常值是「自动居中/全屏」哨兵。 */
	static function isCentered(p:Array<Float>):Bool
	{
		return p != null && (p[0] <= -3.0 || p[1] <= -3.0);
	}

	static function safeImage(name:String):FlxSprite
	{
		try
		{
			if (!Assets.exists('assets/images/${name}.png')) return null;
			var s:FlxSprite = new FlxSprite().loadGraphic(Paths.image(name));
			if (s.graphic == null) return null;
			return s;
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}

	static function place(spr:FlxSprite, key:String):Void
	{
		var p = pos(key);
		if (p == null || isCentered(p))
		{
			spr.setGraphicSize(FlxG.width, FlxG.height);
			spr.updateHitbox();
			spr.setPosition(0, 0);
		}
		else
		{
			spr.setPosition(p[0], p[1]);
		}
	}

	/**
	 * 在 MainMenuState 上叠加 AE 动态封面。
	 * 会隐藏 PE 默认菜单项，使封面成为主视觉（菜单项交互模块后续单独还原）。
	 */
	public static function apply(state:MainMenuState):Void
	{
		if (!useAE()) return;

		try
		{
			if (state.magenta != null) state.magenta.visible = false;
			if (state.menuItems != null) state.menuItems.visible = false;

			// 黑底
			var black:FlxSprite = safeImage('black_HM');
			if (black != null)
			{
				black.setGraphicSize(FlxG.width, FlxG.height);
				black.updateHitbox();
				black.setPosition(0, 0);
				black.alpha = 0.85;
				state.add(black);
			}

			// 水面动画（视频层）；失败则退化为静态蓝底
			var waterOK:Bool = false;
			#if VIDEOS_ALLOWED
			try
			{
				var vid:hxvlc.flixel.FlxVideoSprite = new hxvlc.flixel.FlxVideoSprite();
				vid.antialiasing = ClientPrefs.globalAntialiasing;
				vid.scrollFactor.set(0, 0);
				var filepath:String = Paths.video('water');
				var inMods:String = Paths.modFolders('videos/water.mp4');
				#if sys
				if (!sys.io.FileSystem.exists(filepath) && sys.io.FileSystem.exists(inMods)) filepath = inMods;
				#end
				vid.load(filepath, ['--input-repeat=999999']);
				if (vid.bitmap != null)
				{
					vid.bitmap.onFormatSetup.add(function():Void
					{
						var bmd = vid.bitmap.bitmapData;
						if (bmd != null && bmd.width > 1 && bmd.height > 1)
						{
							var sc:Float = Math.min(FlxG.width / bmd.width, FlxG.height / bmd.height);
							if (sc > 0 && sc == sc) { vid.scale.set(sc, sc); vid.updateHitbox(); }
						}
					});
				}
				try { vid.play(); } catch (e:Dynamic) {}
				state.add(vid);
				waterOK = true;
			}
			catch (e:Dynamic) { waterOK = false; }
			#end
			if (!waterOK)
			{
				var wb:FlxSprite = safeImage('menuBGBlue');
				if (wb != null)
				{
					wb.setGraphicSize(FlxG.width, FlxG.height);
					wb.updateHitbox();
					wb.setPosition(0, 0);
					state.add(wb);
				}
			}

			// 大图（menuArt）
			var art:FlxSprite = safeImage('menuArtBySarasacuni');
			if (art != null) { place(art, 'menuArt_position'); state.add(art); }

			// 眼睛发光（menuEyes / EYE）
			var eyes:FlxSprite = safeImage('eyemenuglow');
			if (eyes != null) { place(eyes, 'menuEyes_position'); state.add(eyes); }

			// BF
			var bf:FlxSprite = safeImage('menuBF');
			if (bf != null) { place(bf, 'BF_position'); state.add(bf); }

			// SoulBF
			var sbf:FlxSprite = safeImage('freeplaySOUL');
			if (sbf != null) { place(sbf, 'SoulBF_position'); state.add(sbf); }

			// logo（corruptionLogoPINK）
			var logo:FlxSprite = safeImage('corruptionLogoPINK');
			if (logo != null) { place(logo, 'logo_position'); state.add(logo); }

			// ENTER 提示
			var enter:FlxSprite = safeImage('titleEnter');
			if (enter != null) { place(enter, 'enterReal_position'); state.add(enter); }

			// playable 文本
			var pl:FlxSprite = safeImage('playable');
			if (pl != null) { place(pl, 'playableTxt_position'); state.add(pl); }
		}
		catch (e:Dynamic)
		{
			trace('AECover.apply failed: ' + e);
		}
	}
}
