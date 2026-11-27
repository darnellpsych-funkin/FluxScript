package fluxscript;

import flixel.FlxG;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;

/**
 * Lo de Flixel que FluxScript agrega a un script:
 *  - `FlxColor` (es un abstract: aquí es la clase FluxColor), `FlxPoint`, y los
 *    valores de FlxAxes, FlxTextAlign, FlxTweenType y BlendMode.
 *  - `wait(segundos, función)` y `every(segundos, función)` (devuelven el FlxTimer;
 *    `every` sigue hasta que la función devuelva false o se cancele el timer).
 *  - `color('#FF0066')` / `color(0xFFFF0066)`.
 */
class FluxFlixel
{
	static var registered:Bool = false;

	public static function apply(script:FluxScript):Void
	{
		register();

		script.set('FlxColor', FluxColor);
		script.set('wait', function(seconds:Float, fn:Dynamic):FlxTimer {
			return new FlxTimer().start(seconds, function(_) callSafe(script, 'wait', fn, []));
		});
		script.set('every', function(seconds:Float, fn:Dynamic):FlxTimer {
			var timer:FlxTimer = new FlxTimer();
			timer.start(seconds, function(t:FlxTimer) {
				if (callSafe(script, 'every', fn, [t]) == false)
					t.cancel();
			}, 0);
			return timer;
		});
		script.set('color', function(value:Dynamic):Int {
			if (value == null)
				return FlxColor.WHITE;
			if (Std.isOfType(value, String))
			{
				var parsed:Null<FlxColor> = FlxColor.fromString(Std.string(value));
				return parsed != null ? parsed : FlxColor.WHITE;
			}
			return Std.int(value);
		});
	}

	/** Los abstracts de Flixel/OpenFL con un valor que sí existe al correr el script. */
	public static function register():Void
	{
		if (registered)
			return;
		registered = true;
		for (name in ['FlxColor', 'flixel.util.FlxColor'])
			FluxClasses.alias(name, FluxColor);
		for (name in ['FlxPoint', 'flixel.math.FlxPoint'])
			FluxClasses.alias(name, flixel.math.FlxPoint.FlxBasePoint);
		for (name in ['FlxAxes', 'flixel.util.FlxAxes'])
			FluxClasses.alias(name, {X: flixel.util.FlxAxes.X, Y: flixel.util.FlxAxes.Y, XY: flixel.util.FlxAxes.XY, NONE: flixel.util.FlxAxes.NONE});
		for (name in ['FlxTextAlign', 'flixel.text.FlxTextAlign', 'flixel.text.FlxText.FlxTextAlign'])
			FluxClasses.alias(name, {LEFT: 'left', CENTER: 'center', RIGHT: 'right', JUSTIFY: 'justify'});
		for (name in ['FlxTweenType', 'flixel.tweens.FlxTweenType', 'flixel.tweens.FlxTween.FlxTweenType'])
			FluxClasses.alias(name, {
				PERSIST: flixel.tweens.FlxTween.FlxTweenType.PERSIST,
				LOOPING: flixel.tweens.FlxTween.FlxTweenType.LOOPING,
				PINGPONG: flixel.tweens.FlxTween.FlxTweenType.PINGPONG,
				ONESHOT: flixel.tweens.FlxTween.FlxTweenType.ONESHOT,
				BACKWARD: flixel.tweens.FlxTween.FlxTweenType.BACKWARD
			});
		for (name in ['BlendMode', 'openfl.display.BlendMode'])
			FluxClasses.alias(name, {
				ADD: openfl.display.BlendMode.ADD,
				ALPHA: openfl.display.BlendMode.ALPHA,
				DARKEN: openfl.display.BlendMode.DARKEN,
				DIFFERENCE: openfl.display.BlendMode.DIFFERENCE,
				ERASE: openfl.display.BlendMode.ERASE,
				HARDLIGHT: openfl.display.BlendMode.HARDLIGHT,
				INVERT: openfl.display.BlendMode.INVERT,
				LAYER: openfl.display.BlendMode.LAYER,
				LIGHTEN: openfl.display.BlendMode.LIGHTEN,
				MULTIPLY: openfl.display.BlendMode.MULTIPLY,
				NORMAL: openfl.display.BlendMode.NORMAL,
				OVERLAY: openfl.display.BlendMode.OVERLAY,
				SCREEN: openfl.display.BlendMode.SCREEN,
				SHADER: openfl.display.BlendMode.SHADER,
				SUBTRACT: openfl.display.BlendMode.SUBTRACT
			});
	}

	static function callSafe(script:FluxScript, where:String, fn:Dynamic, args:Array<Dynamic>):Dynamic
	{
		if (fn == null || !script.active)
			return null;
		try
		{
			return Reflect.callMethod(null, fn, args);
		}
		catch (e:Dynamic)
		{
			script.error('Error en $where: ' + FluxScript.errorText(e));
		}
		return null;
	}
}

/** FlxColor para los scripts (FlxColor es un abstract y no existe al correr el script). */
@:keep
class FluxColor
{
	public static var TRANSPARENT(default, null):Int = FlxColor.TRANSPARENT;
	public static var WHITE(default, null):Int = FlxColor.WHITE;
	public static var GRAY(default, null):Int = FlxColor.GRAY;
	public static var BLACK(default, null):Int = FlxColor.BLACK;
	public static var GREEN(default, null):Int = FlxColor.GREEN;
	public static var LIME(default, null):Int = FlxColor.LIME;
	public static var YELLOW(default, null):Int = FlxColor.YELLOW;
	public static var ORANGE(default, null):Int = FlxColor.ORANGE;
	public static var RED(default, null):Int = FlxColor.RED;
	public static var PURPLE(default, null):Int = FlxColor.PURPLE;
	public static var BLUE(default, null):Int = FlxColor.BLUE;
	public static var BROWN(default, null):Int = FlxColor.BROWN;
	public static var PINK(default, null):Int = FlxColor.PINK;
	public static var MAGENTA(default, null):Int = FlxColor.MAGENTA;
	public static var CYAN(default, null):Int = FlxColor.CYAN;

	public static function fromInt(value:Int):Int
		return FlxColor.fromInt(value);

	public static function fromRGB(red:Int, green:Int, blue:Int, alpha:Int = 255):Int
		return FlxColor.fromRGB(red, green, blue, alpha);

	public static function fromRGBFloat(red:Float, green:Float, blue:Float, alpha:Float = 1):Int
		return FlxColor.fromRGBFloat(red, green, blue, alpha);

	public static function fromCMYK(cyan:Float, magenta:Float, yellow:Float, black:Float, alpha:Float = 1):Int
		return FlxColor.fromCMYK(cyan, magenta, yellow, black, alpha);

	public static function fromHSB(hue:Float, saturation:Float, brightness:Float, alpha:Float = 1):Int
		return FlxColor.fromHSB(hue, saturation, brightness, alpha);

	public static function fromHSL(hue:Float, saturation:Float, lightness:Float, alpha:Float = 1):Int
		return FlxColor.fromHSL(hue, saturation, lightness, alpha);

	public static function fromString(text:String):Int
	{
		var parsed:Null<FlxColor> = FlxColor.fromString(text);
		return parsed != null ? parsed : FlxColor.WHITE;
	}

	/** Mezcla dos colores (factor 0 = el primero, 1 = el segundo). */
	public static function interpolate(color1:Int, color2:Int, factor:Float = 0.5):Int
		return FlxColor.interpolate(color1, color2, factor);

	public static function getRed(color:Int):Int
		return (color : FlxColor).red;

	public static function getGreen(color:Int):Int
		return (color : FlxColor).green;

	public static function getBlue(color:Int):Int
		return (color : FlxColor).blue;

	public static function getAlpha(color:Int):Int
		return (color : FlxColor).alpha;
}
