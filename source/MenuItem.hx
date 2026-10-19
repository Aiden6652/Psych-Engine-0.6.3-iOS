package;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.math.FlxMath;
import flixel.util.FlxColor;

class MenuItem extends FlxSprite
{
	public var targetY:Float = 0;
	public var flashingInt:Int = 0;

	/// [AE-iOS] 列表行距与基准 Y（默认 stock 值；story 页按录屏布局覆写）
	public static var itemSpacing:Float = 120;
	public static var itemBaseY:Float = 480;

	public function new(x:Float, y:Float, weekName:String = '')
	{
		super(x, y);
		// [AE-iOS] 周名图缺失（如 story9 / story9z）时回落到 storymenu/null.png
		var g:FlxGraphic = Paths.image('storymenu/' + weekName);
		if (g == null) g = Paths.image('storymenu/null');
		if (g != null) loadGraphic(g);
		antialiasing = ClientPrefs.globalAntialiasing;
	}

	private var isFlashing:Bool = false;

	public function startFlashing():Void
	{
		isFlashing = true;
	}

	// if it runs at 60fps, fake framerate will be 6
	// if it runs at 144 fps, fake framerate will be like 14, and will update the graphic every 0.016666 * 3 seconds still???
	// so it runs basically every so many seconds, not dependant on framerate??
	// I'm still learning how math works thanks whoever is reading this lol
	var fakeFramerate:Int = Math.round((1 / FlxG.elapsed) / 10);

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		y = FlxMath.lerp(y, (targetY * itemSpacing) + itemBaseY, CoolUtil.boundTo(elapsed * 10.2, 0, 1));

		if (isFlashing)
			flashingInt += 1;

		if (flashingInt % fakeFramerate >= Math.floor(fakeFramerate / 2))
			color = 0xFF33ffff;
		else
			color = FlxColor.WHITE;
	}
}
