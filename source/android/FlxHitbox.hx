package android;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.ui.FlxButton;
import flixel.util.FlxColor;
import openfl.display.BitmapData;

/**
 * [PE-iOS] P-Slice 风格 hitbox —— 4 列「整屏高」触控区（代码绘制，不依赖图集）。
 *
 * 为什么要换掉原来的图集版：
 *   原版 FlxHitbox 用 MobileControls/hitbox*.png 贴图，箭头只占顶部一小块；
 *   而且 hitbox / hitboxnospace / hitboxSHIFT / ShiftHitbox 四套贴图混用时，
 *   会出现「部分列是全高、部分列只有顶部小方块」的错位，手机上很难按。
 *
 * 现在这一版完全用代码画（做法对齐 P-Slice 的 mobile/objects/Hitbox.hx）：
 *   - 每列都是 FlxG.width/4 × 列高 的整块触控区，点哪都触发；
 *   - 每列底部（toporbottom 为 Top 时改为顶部）一条细色带作为视觉提示；
 *   - 按下时整列点亮（透明度取自 ClientPrefs.hitBoxTrans），松开淡出；
 *   - 不再依赖任何 PNG，不会再出现资源缺失 / 贴图错位。
 *
 * 对外接口（buttonLeft/buttonDown/buttonUp/buttonRight/buttonSpace/buttonShift）
 * 与原版完全一致，Controls.setHitBox() 不需要改动。
 */
class FlxHitbox extends FlxSpriteGroup
{
	public var hitbox:FlxSpriteGroup;

	public var buttonLeft:FlxButton;
	public var buttonDown:FlxButton;
	public var buttonUp:FlxButton;
	public var buttonRight:FlxButton;
	public var buttonSpace:FlxButton;
	public var buttonShift:FlxButton;

	public var orgAlpha:Float = 0.75;
	public var orgAntialiasing:Bool = true;

	// 常驻色带（视觉提示，不参与输入）
	var barLeft:FlxSprite;
	var barDown:FlxSprite;
	var barUp:FlxSprite;
	var barRight:FlxSprite;
	var barSpace:FlxSprite;
	var barShift:FlxSprite;

	/// 色带厚度 = 所在区域高度的 3.5%（对齐 P-Slice 的 label 尺寸）
	static inline var BAR_RATIO:Float = 0.035;
	/// 色带常驻透明度
	static inline var BAR_ALPHA:Float = 0.85;

	/// 四个方向的颜色（PE 默认准星色：紫 / 青 / 绿 / 红，与无视频版那四条色带一致）
	static var LANE_COLORS:Array<FlxColor> = [0xFFC24B99, 0xFF00C8FF, 0xFF12FA05, 0xFFF9393F];

	public function new(?alphaAlt:Float = 0.75, ?antialiasingAlt:Bool = true)
	{
		super();

		orgAlpha = alphaAlt;
		orgAntialiasing = antialiasingAlt;

		buttonLeft = new FlxButton(0, 0);
		buttonDown = new FlxButton(0, 0);
		buttonUp = new FlxButton(0, 0);
		buttonRight = new FlxButton(0, 0);
		if (ClientPrefs.hitBoxSpace) buttonSpace = new FlxButton(0, 0);
		if (ClientPrefs.hitBoxShift) buttonShift = new FlxButton(0, 0);

		hitbox = new FlxSpriteGroup();
		hitbox.scrollFactor.set();

		// 需要 space / shift 时，预留一行（占屏幕高 25%，对齐原版 180/720）
		var needStrip:Bool = ClientPrefs.hitBoxSpace || ClientPrefs.hitBoxShift;
		var stripAtTop:Bool = (ClientPrefs.toporbottom == 'Top');
		var stripH:Float = needStrip ? FlxG.height * 0.25 : 0;
		var colW:Float = FlxG.width / 4;
		var colH:Float = FlxG.height - stripH;
		var colY:Float = (needStrip && stripAtTop) ? stripH : 0;

		// 四列：整块触控区 + 底部色带
		hitbox.add(add(buttonLeft = createZone(0 * colW, colY, colW, colH, LANE_COLORS[0])));
		hitbox.add(add(buttonDown = createZone(1 * colW, colY, colW, colH, LANE_COLORS[1])));
		hitbox.add(add(buttonUp = createZone(2 * colW, colY, colW, colH, LANE_COLORS[2])));
		hitbox.add(add(buttonRight = createZone(3 * colW, colY, colW, colH, LANE_COLORS[3])));

		barLeft = add(createBar(0 * colW, colY, colW, colH, LANE_COLORS[0], stripAtTop));
		barDown = add(createBar(1 * colW, colY, colW, colH, LANE_COLORS[1], stripAtTop));
		barUp = add(createBar(2 * colW, colY, colW, colH, LANE_COLORS[2], stripAtTop));
		barRight = add(createBar(3 * colW, colY, colW, colH, LANE_COLORS[3], stripAtTop));

		// 可选：space / shift 那一行
		if (needStrip)
		{
			var stripY:Float = stripAtTop ? 0 : (FlxG.height - stripH);
			var spaceOnLeft:Bool = (ClientPrefs.spacePosition != 'Right');

			if (buttonSpace != null)
			{
				var w:Float = ClientPrefs.hitBoxShift ? (FlxG.width * 0.5) : FlxG.width;
				var x:Float = (ClientPrefs.hitBoxShift && !spaceOnLeft) ? (FlxG.width - w) : 0;
				hitbox.add(add(buttonSpace = createZone(x, stripY, w, stripH, 0xFFFFD700)));
				barSpace = add(createBar(x, stripY, w, stripH, 0xFFFFD700, !stripAtTop));
			}
			if (buttonShift != null)
			{
				var w:Float = ClientPrefs.hitBoxSpace ? (FlxG.width * 0.5) : FlxG.width;
				var x:Float = (ClientPrefs.hitBoxSpace && spaceOnLeft) ? (FlxG.width - w) : 0;
				hitbox.add(add(buttonShift = createZone(x, stripY, w, stripH, 0xFFB76BFF)));
				barShift = add(createBar(x, stripY, w, stripH, 0xFFB76BFF, !stripAtTop));
			}
		}
	}

	/// 透明触控区：整块可点，按下时整块点亮
	function createZone(x:Float, y:Float, w:Float, h:Float, color:FlxColor):FlxButton
	{
		var button = new FlxButton(x, y);
		var fillColor:Int = 0xFF000000 | (color & 0xFFFFFF);
		var bmd:BitmapData = new BitmapData(Std.int(Math.max(1, w)), Std.int(Math.max(1, h)), true, fillColor);
		button.loadGraphic(bmd);
		button.antialiasing = orgAntialiasing;
		button.alpha = 0;

		var pressAlpha:Float = ClientPrefs.hitBoxTrans;
		if (pressAlpha <= 0) pressAlpha = 0.4;

		button.onDown.callback = function()
		{
			FlxTween.cancelTweensOf(button);
			FlxTween.tween(button, {alpha: pressAlpha}, 0.075, {ease: FlxEase.circInOut});
		};
		button.onUp.callback = function()
		{
			FlxTween.cancelTweensOf(button);
			FlxTween.tween(button, {alpha: 0}, 0.1, {ease: FlxEase.circInOut});
		};
		button.onOut.callback = function()
		{
			FlxTween.cancelTweensOf(button);
			FlxTween.tween(button, {alpha: 0}, 0.2, {ease: FlxEase.circInOut});
		};
		return button;
	}

	/// 常驻色带（视觉提示，不参与输入）
	function createBar(x:Float, y:Float, w:Float, h:Float, color:FlxColor, atTop:Bool):FlxSprite
	{
		var barH:Int = Std.int(Math.max(2, h * BAR_RATIO));
		var bar = new FlxSprite(x, atTop ? y : (y + h - barH));
		bar.makeGraphic(Std.int(Math.max(1, w)), barH, 0xFF000000 | (color & 0xFFFFFF), true);
		bar.alpha = BAR_ALPHA;
		bar.scrollFactor.set();
		bar.antialiasing = orgAntialiasing;
		return bar;
	}

	override public function destroy():Void
	{
		super.destroy();

		buttonLeft = null;
		buttonDown = null;
		buttonUp = null;
		buttonRight = null;
		buttonSpace = null;
		buttonShift = null;
		barLeft = null;
		barDown = null;
		barUp = null;
		barRight = null;
		barSpace = null;
		barShift = null;
	}
}
