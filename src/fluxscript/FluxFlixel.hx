package fluxscript;

import flixel.FlxG;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxAxes;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;

using StringTools;

/**
 * Lo de Flixel que FluxScript agrega a un script:
 *  - `FlxColor` (es un abstract: aquí es la clase FluxColor), `FlxPoint`, y los
 *    valores de FlxAxes, FlxTextAlign, FlxTweenType y BlendMode.
 *  - `wait(segundos, función)` y `every(segundos, función)` (devuelven el FlxTimer;
 *    `every` sigue hasta que la función devuelva false o se cancele el timer).
 *  - `color('#FF0066')` / `color(0xFFFF0066)`.
 *  - Las esperas de `task` (task.wait, task.delay...) con FlxTimer: se pausan con el
 *    juego como los timers de Psych. Las de los scripts `persistent` (globales) siguen
 *    aunque cambie el estado. Los módulos de require se vuelven a cargar en cada estado.
 *  - Lo del preset de los .hxs (si el engine no lo puso ya): makeText, makeSprite,
 *    addAnim, playAnim, screenCenter, tween, tweenColor, cancelTweens, timer, lerp,
 *    clamp, randomInt, randomFloat, randomBool y el mouse (mouseX, mouseClicked...).
 */
class FluxFlixel
{
	static var registered:Bool = false;

	public static function apply(script:FluxScript):Void
		script.usePreset('FluxFlixel', setup);

	static function setup(script:FluxScript):Void
	{
		register();

		script.set('FlxColor', FluxColor);
		script.set('wait', function(seconds:Float, ?fn:Dynamic):FlxTimer {
			if (fn == null) // wait(segundos) solo (sin función) espera dentro de una función: lo arma FluxAsync
				return null;
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

		hxs(script);
	}

	/** Los abstracts de Flixel/OpenFL con un valor que sí existe al correr el script, y las esperas de task. */
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

		// task.wait / task.delay con FlxTimer (se pausan con el juego y se borran al cambiar de
		// estado); los de los scripts globales siguen en la lista propia, que avanza en cada frame
		FluxTasks.startTimer = function(seconds:Float, callback:Void->Void, persistent:Bool):Dynamic {
			if (persistent)
				return FluxTasks.startOwnTimer(seconds, callback);
			return new FlxTimer().start(seconds, function(_) callback());
		};
		FlxG.signals.postUpdate.add(updateOwnTimers);
		FlxG.signals.preStateSwitch.add(clearModules);
	}

	static function updateOwnTimers():Void
		FluxTasks.update(FlxG.elapsed);

	static function clearModules():Void
		FluxLib.clearModules(false);

	static inline function callSafe(script:FluxScript, where:String, fn:Dynamic, args:Array<Dynamic>):Dynamic
		return script.callSafe(fn, args, where);

	// ------------------------------------------------------------------
	// El preset de los .hxs (solo lo que el engine no puso)
	// ------------------------------------------------------------------

	static function hxs(script:FluxScript):Void
	{
		script.setDefault('makeSprite', function(?x:Float = 0, ?y:Float = 0, ?image:String):FlxSprite {
			return (image != null && image.length > 0) ? new FlxSprite(x, y, image) : new FlxSprite(x, y);
		});
		script.setDefault('makeText', function(?x:Float = 0, ?y:Float = 0, ?width:Float = 0, ?text:String = '', ?size:Int = 24):FlxText {
			var txt:FlxText = new FlxText(x, y, width, text, size);
			txt.setBorderStyle(flixel.text.FlxText.FlxTextBorderStyle.OUTLINE, FlxColor.BLACK, 1.25);
			return txt;
		});
		script.setDefault('addAnim', function(sprite:FlxSprite, name:String, prefix:String, ?fps:Float = 24, ?loop:Bool = true, ?indices:Dynamic) {
			if (sprite == null || sprite.animation == null)
				return;
			if (indices != null)
				sprite.animation.addByIndices(name, prefix, indicesOf(indices), '', fps, loop);
			else
				sprite.animation.addByPrefix(name, prefix, fps, loop);
		});
		script.setDefault('playAnim', function(object:Dynamic, name:String, ?forced:Bool = false, ?reverse:Bool = false, ?startFrame:Int = 0):Bool {
			if (object == null)
				return false;
			var play:Dynamic = Reflect.getProperty(object, 'playAnim');
			if (play != null && Reflect.isFunction(play))
				Reflect.callMethod(object, play, [name, forced, reverse, startFrame]);
			else if (Std.isOfType(object, FlxSprite) && (object : FlxSprite).animation != null)
				(object : FlxSprite).animation.play(name, forced, reverse, startFrame);
			else
				return false;
			return true;
		});
		script.setDefault('screenCenter', function(object:FlxObject, ?axes:String = 'xy') {
			if (object != null)
				object.screenCenter(switch (axes.trim().toLowerCase())
				{
					case 'x': FlxAxes.X;
					case 'y': FlxAxes.Y;
					default: FlxAxes.XY;
				});
		});

		script.setDefault('tween', function(object:Dynamic, values:Dynamic, duration:Float, ?ease:Dynamic, ?onComplete:Dynamic):FlxTween {
			if (object == null || values == null)
				return null;
			return FlxTween.tween(object, values, duration, {ease: easeOf(ease), onComplete: completeOf(script, onComplete, 'tween')});
		});
		script.setDefault('tweenColor', function(object:FlxSprite, duration:Float, from:Dynamic, to:Dynamic, ?ease:Dynamic, ?onComplete:Dynamic):FlxTween {
			if (object == null)
				return null;
			return FlxTween.color(object, duration, colorOf(from), colorOf(to), {ease: easeOf(ease), onComplete: completeOf(script, onComplete, 'tweenColor')});
		});
		script.setDefault('cancelTweens', function(object:Dynamic) {
			if (object != null)
				FlxTween.cancelTweensOf(object);
		});
		script.setDefault('timer', function(seconds:Float, fn:Dynamic, ?loops:Int = 1):FlxTimer {
			return new FlxTimer().start(seconds, function(t:FlxTimer) callSafe(script, 'timer', fn, [t]), loops);
		});

		script.setDefault('lerp', function(a:Float, b:Float, ratio:Float):Float return FlxMath.lerp(a, b, ratio));
		script.setDefault('clamp', function(value:Float, min:Float, max:Float):Float return FlxMath.bound(value, min, max));
		script.setDefault('randomInt', function(?min:Int = 0, ?max:Int = 100):Int return FlxG.random.int(min, max));
		script.setDefault('randomFloat', function(?min:Float = 0, ?max:Float = 1):Float return FlxG.random.float(min, max));
		script.setDefault('randomBool', function(?chance:Float = 50):Bool return FlxG.random.bool(chance));

		#if FLX_MOUSE
		script.setDefault('mouseX', function():Float return FlxG.mouse.screenX);
		script.setDefault('mouseY', function():Float return FlxG.mouse.screenY);
		script.setDefault('mouseClicked', function(?button:String = 'left'):Bool {
			return switch (button.trim().toLowerCase())
			{
				case 'right': FlxG.mouse.justPressedRight;
				case 'middle': FlxG.mouse.justPressedMiddle;
				default: FlxG.mouse.justPressed;
			}
		});
		script.setDefault('mousePressed', function(?button:String = 'left'):Bool {
			return switch (button.trim().toLowerCase())
			{
				case 'right': FlxG.mouse.pressedRight;
				case 'middle': FlxG.mouse.pressedMiddle;
				default: FlxG.mouse.pressed;
			}
		});
		script.setDefault('mouseReleased', function(?button:String = 'left'):Bool {
			return switch (button.trim().toLowerCase())
			{
				case 'right': FlxG.mouse.justReleasedRight;
				case 'middle': FlxG.mouse.justReleasedMiddle;
				default: FlxG.mouse.justReleased;
			}
		});
		script.setDefault('mouseOverlaps', function(object:FlxObject, ?camera:flixel.FlxCamera):Bool {
			return object != null && FlxG.mouse.overlaps(object, camera);
		});
		#end
	}

	/** [0, 1, 2] o "0,1,2". */
	public static function indicesOf(value:Dynamic):Array<Int>
	{
		if (value == null)
			return [0];
		if (Std.isOfType(value, String))
			return [for (part in Std.string(value).trim().split(',')) if (part.trim().length > 0) Std.parseInt(part.trim())];
		return [for (v in (value : Array<Dynamic>)) Std.int(v)];
	}

	static function colorOf(value:Dynamic):FlxColor
	{
		if (value == null)
			return FlxColor.WHITE;
		if (Std.isOfType(value, String))
		{
			var parsed:Null<FlxColor> = FlxColor.fromString(Std.string(value));
			return parsed != null ? parsed : FlxColor.WHITE;
		}
		return FlxColor.fromInt(Std.int(value));
	}

	static function completeOf(script:FluxScript, fn:Dynamic, where:String):FlxTween->Void
	{
		if (fn == null || !Reflect.isFunction(fn))
			return null;
		return function(twn:FlxTween) callSafe(script, where, fn, [twn]);
	}

	/** La función de FlxEase por nombre ('quadOut', 'backInOut'...), o la función misma. */
	public static function easeOf(ease:Dynamic):Float->Float
	{
		if (ease == null)
			return FlxEase.linear;
		if (Reflect.isFunction(ease))
			return ease;
		return switch (Std.string(ease).trim().toLowerCase())
		{
			case 'quadin': FlxEase.quadIn;
			case 'quadout': FlxEase.quadOut;
			case 'quadinout': FlxEase.quadInOut;
			case 'cubein': FlxEase.cubeIn;
			case 'cubeout': FlxEase.cubeOut;
			case 'cubeinout': FlxEase.cubeInOut;
			case 'quartin': FlxEase.quartIn;
			case 'quartout': FlxEase.quartOut;
			case 'quartinout': FlxEase.quartInOut;
			case 'quintin': FlxEase.quintIn;
			case 'quintout': FlxEase.quintOut;
			case 'quintinout': FlxEase.quintInOut;
			case 'smoothstepin': FlxEase.smoothStepIn;
			case 'smoothstepout': FlxEase.smoothStepOut;
			case 'smoothstepinout': FlxEase.smoothStepInOut;
			case 'smootherstepin': FlxEase.smootherStepIn;
			case 'smootherstepout': FlxEase.smootherStepOut;
			case 'smootherstepinout': FlxEase.smootherStepInOut;
			case 'sinein': FlxEase.sineIn;
			case 'sineout': FlxEase.sineOut;
			case 'sineinout': FlxEase.sineInOut;
			case 'bouncein': FlxEase.bounceIn;
			case 'bounceout': FlxEase.bounceOut;
			case 'bounceinout': FlxEase.bounceInOut;
			case 'circin': FlxEase.circIn;
			case 'circout': FlxEase.circOut;
			case 'circinout': FlxEase.circInOut;
			case 'expoin': FlxEase.expoIn;
			case 'expoout': FlxEase.expoOut;
			case 'expoinout': FlxEase.expoInOut;
			case 'backin': FlxEase.backIn;
			case 'backout': FlxEase.backOut;
			case 'backinout': FlxEase.backInOut;
			case 'elasticin': FlxEase.elasticIn;
			case 'elasticout': FlxEase.elasticOut;
			case 'elasticinout': FlxEase.elasticInOut;
			default: FlxEase.linear;
		}
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
