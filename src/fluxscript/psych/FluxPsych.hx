package fluxscript.psych;

import backend.ClientPrefs;
import backend.Conductor;
import backend.CoolUtil;
import backend.MusicBeatState;
import backend.Paths;
import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.sound.FlxSound;
import flixel.addons.transition.FlxTransitionableState;
import flixel.text.FlxText;
import flixel.text.FlxText.FlxTextAlign;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxTween.FlxTweenType;
import flixel.util.FlxAxes;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import fluxscript.FluxFlixel;
import fluxscript.FluxScript;
import objects.StrumNote;
import psychlua.CustomSubstate;
import psychlua.LuaUtils;
import psychlua.ModchartSprite;
import states.PlayState;
import substates.GameOverSubstate;

using StringTools;

/**
 * FluxScript en Psych Engine 1.0 y sus forks (Flux Engine, P-Slice...).
 *
 * Le pone a un FluxScript lo mismo que tiene un .hx de Psych (game, setVar,
 * debugPrint, Function_Stop...) y casi toda la API de Lua de Psych, con los mismos
 * nombres y argumentos: makeLuaSprite, addLuaSprite, setProperty, doTweenX,
 * runTimer, playSound, makeLuaText... Los tags son los mismos que usan los .lua
 * (MusicBeatState.getVariables()), así que los dos se pueden mezclar.
 *
 * Diferencias con Lua (porque FluxScript sí puede guardar objetos):
 *  - donde va un tag también se puede pasar el objeto: scaleObject(miSprite, 2, 2);
 *  - makeLuaSprite / makeLuaText devuelven el objeto;
 *  - onTweenCompleted, onTimerCompleted y onSoundFinished se llaman en el script
 *    que creó el tween, el timer o el sonido.
 */
class FluxPsych
{
	public static function apply(script:FluxScript):Void
	{
		FluxFlixel.apply(script);
		preset(script);
		properties(script);
		sprites(script);
		texts(script);
		tweensAndTimers(script);
		sounds(script);
		cameras(script);
		song(script);
		other(script);
	}

	// ------------------------------------------------------------------
	// Ayudas
	// ------------------------------------------------------------------

	static inline function variables():Map<String, Dynamic>
		return MusicBeatState.getVariables();

	static inline function game():PlayState
		return (PlayState.instance != null && FlxG.state == PlayState.instance) ? PlayState.instance : null;

	/** Un objeto por su tag/ruta ("bg", "boyfriend.scale", "camHUD") o el objeto mismo. */
	public static function objectOf(target:Dynamic):Dynamic
	{
		if (target == null || !Std.isOfType(target, String))
			return target;
		var path:String = target;
		var split:Array<String> = path.split('.');
		if (split.length == 1)
			return LuaUtils.getObjectDirectly(path);
		return LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length - 1]);
	}

	static function warn(script:FluxScript, text:String):Void
		script.error(text);

	static function colorOf(value:Dynamic):FlxColor
	{
		if (value == null)
			return FlxColor.WHITE;
		if (Std.isOfType(value, String))
			return CoolUtil.colorFromString(value);
		return FlxColor.fromInt(Std.int(value));
	}

	static function cameraOf(value:Dynamic):FlxCamera
	{
		if (value != null && Std.isOfType(value, FlxCamera))
			return value;
		return LuaUtils.cameraFromString(value != null ? Std.string(value) : 'game');
	}

	static function callSafe(script:FluxScript, name:String, args:Array<Dynamic>):Void
	{
		if (script.active)
			script.call(name, args);
	}

	// ------------------------------------------------------------------
	// Lo mismo que un .hx de Psych
	// ------------------------------------------------------------------

	static function preset(script:FluxScript):Void
	{
		script.set('FlxG', FlxG);
		script.set('FlxSprite', FlxSprite);
		script.set('FlxText', FlxText);
		script.set('FlxCamera', FlxCamera);
		script.set('FlxTimer', FlxTimer);
		script.set('FlxTween', FlxTween);
		script.set('FlxEase', FlxEase);
		script.set('FlxMath', flixel.math.FlxMath);
		script.set('PlayState', PlayState);
		script.set('Paths', Paths);
		script.set('Conductor', Conductor);
		script.set('ClientPrefs', ClientPrefs);
		script.set('Character', objects.Character);
		script.set('Note', objects.Note);
		script.set('CustomSubstate', CustomSubstate);
		script.set('Countdown', backend.BaseStage.Countdown);
		#if (!flash && sys)
		script.set('FlxRuntimeShader', flixel.addons.display.FlxRuntimeShader);
		#end
		script.set('ShaderFilter', openfl.filters.ShaderFilter);

		script.set('game', FlxG.state);
		script.set('controls', backend.Controls.instance);
		script.set('buildTarget', LuaUtils.getBuildTarget());
		script.set('Function_Stop', LuaUtils.Function_Stop);
		script.set('Function_Continue', LuaUtils.Function_Continue);
		script.set('Function_StopLua', LuaUtils.Function_StopLua);
		script.set('Function_StopHScript', LuaUtils.Function_StopHScript);
		script.set('Function_StopAll', LuaUtils.Function_StopAll);

		script.set('setVar', function(name:String, value:Dynamic):Dynamic {
			variables().set(name, value);
			return value;
		});
		script.set('getVar', function(name:String):Dynamic return variables().get(name));
		script.set('removeVar', function(name:String):Bool return variables().remove(name));
		script.set('debugPrint', function(text:Dynamic, ?color:Dynamic) {
			var g:PlayState = game();
			if (g != null)
				g.addTextToDebug(Std.string(text), color != null ? colorOf(color) : FlxColor.WHITE);
			else
				trace(text);
		});
		script.set('getModSetting', function(saveTag:String, ?modName:String):Dynamic {
			if (modName == null)
				modName = script.modFolder;
			return modName != null ? LuaUtils.getModSetting(saveTag, modName) : null;
		});

		script.set('keyboardJustPressed', function(name:String):Bool return Reflect.getProperty(FlxG.keys.justPressed, name) == true);
		script.set('keyboardPressed', function(name:String):Bool return Reflect.getProperty(FlxG.keys.pressed, name) == true);
		script.set('keyboardReleased', function(name:String):Bool return Reflect.getProperty(FlxG.keys.justReleased, name) == true);
		var controls = backend.Controls.instance;
		script.set('keyJustPressed', function(?name:String = ''):Bool {
			return switch (name.toLowerCase())
			{
				case 'left': controls.NOTE_LEFT_P;
				case 'down': controls.NOTE_DOWN_P;
				case 'up': controls.NOTE_UP_P;
				case 'right': controls.NOTE_RIGHT_P;
				default: controls.justPressed(name.toLowerCase());
			}
		});
		script.set('keyPressed', function(?name:String = ''):Bool {
			return switch (name.toLowerCase())
			{
				case 'left': controls.NOTE_LEFT;
				case 'down': controls.NOTE_DOWN;
				case 'up': controls.NOTE_UP;
				case 'right': controls.NOTE_RIGHT;
				default: controls.pressed(name.toLowerCase());
			}
		});
		script.set('keyReleased', function(?name:String = ''):Bool {
			return switch (name.toLowerCase())
			{
				case 'left': controls.NOTE_LEFT_R;
				case 'down': controls.NOTE_DOWN_R;
				case 'up': controls.NOTE_UP_R;
				case 'right': controls.NOTE_RIGHT_R;
				default: controls.justReleased(name.toLowerCase());
			}
		});
	}

	// ------------------------------------------------------------------
	// Propiedades (getProperty / setProperty...)
	// ------------------------------------------------------------------

	static function properties(script:FluxScript):Void
	{
		script.set('getProperty', function(path:String, ?allowMaps:Bool = false):Dynamic {
			var split:Array<String> = path.split('.');
			if (split.length == 1)
				return LuaUtils.getObjectDirectly(path, allowMaps);
			return LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split, true, allowMaps), split[split.length - 1], allowMaps);
		});
		script.set('setProperty', function(path:String, value:Dynamic, ?allowMaps:Bool = false):Dynamic {
			var split:Array<String> = path.split('.');
			if (split.length == 1)
			{
				if (variables().exists(path))
					variables().set(path, value);
				else
					LuaUtils.setVarInArray(LuaUtils.getTargetInstance(), path, value, allowMaps);
				return value;
			}
			LuaUtils.setVarInArray(LuaUtils.getPropertyLoop(split, true, allowMaps), split[split.length - 1], value, allowMaps);
			return value;
		});
		script.set('getPropertyFromClass', function(classPath:String, path:String, ?allowMaps:Bool = false):Dynamic {
			var cls:Dynamic = Type.resolveClass(classPath);
			if (cls == null)
			{
				warn(script, 'getPropertyFromClass: no existe la clase $classPath');
				return null;
			}
			var split:Array<String> = path.split('.');
			var obj:Dynamic = cls;
			for (i in 0...split.length - 1)
				obj = LuaUtils.getVarInArray(obj, split[i], allowMaps);
			return LuaUtils.getVarInArray(obj, split[split.length - 1], allowMaps);
		});
		script.set('setPropertyFromClass', function(classPath:String, path:String, value:Dynamic, ?allowMaps:Bool = false):Dynamic {
			var cls:Dynamic = Type.resolveClass(classPath);
			if (cls == null)
			{
				warn(script, 'setPropertyFromClass: no existe la clase $classPath');
				return null;
			}
			var split:Array<String> = path.split('.');
			var obj:Dynamic = cls;
			for (i in 0...split.length - 1)
				obj = LuaUtils.getVarInArray(obj, split[i], allowMaps);
			LuaUtils.setVarInArray(obj, split[split.length - 1], value, allowMaps);
			return value;
		});
		script.set('getPropertyFromGroup', function(group:Dynamic, index:Int, field:String, ?allowMaps:Bool = false):Dynamic {
			var item:Dynamic = groupItem(group, index);
			if (item == null)
				return null;
			var split:Array<String> = field.split('.');
			var obj:Dynamic = item;
			for (i in 0...split.length - 1)
				obj = LuaUtils.getVarInArray(obj, split[i], allowMaps);
			return LuaUtils.getVarInArray(obj, split[split.length - 1], allowMaps);
		});
		script.set('setPropertyFromGroup', function(group:Dynamic, index:Int, field:String, value:Dynamic, ?allowMaps:Bool = false):Dynamic {
			var item:Dynamic = groupItem(group, index);
			if (item == null)
				return null;
			var split:Array<String> = field.split('.');
			var obj:Dynamic = item;
			for (i in 0...split.length - 1)
				obj = LuaUtils.getVarInArray(obj, split[i], allowMaps);
			LuaUtils.setVarInArray(obj, split[split.length - 1], value, allowMaps);
			return value;
		});
		script.set('callMethod', function(path:String, ?args:Array<Dynamic>):Dynamic {
			var split:Array<String> = path.split('.');
			var owner:Dynamic = split.length == 1 ? LuaUtils.getTargetInstance() : LuaUtils.getPropertyLoop(split, true);
			var fn:Dynamic = LuaUtils.getVarInArray(owner, split[split.length - 1]);
			if (fn == null || !Reflect.isFunction(fn))
			{
				warn(script, 'callMethod: no existe la función $path');
				return null;
			}
			return Reflect.callMethod(owner, fn, args != null ? args : []);
		});
		script.set('callMethodFromClass', function(classPath:String, path:String, ?args:Array<Dynamic>):Dynamic {
			var obj:Dynamic = Type.resolveClass(classPath);
			if (obj == null)
			{
				warn(script, 'callMethodFromClass: no existe la clase $classPath');
				return null;
			}
			var split:Array<String> = path.split('.');
			for (i in 0...split.length - 1)
				obj = LuaUtils.getVarInArray(obj, split[i]);
			var fn:Dynamic = LuaUtils.getVarInArray(obj, split[split.length - 1]);
			return (fn != null && Reflect.isFunction(fn)) ? Reflect.callMethod(obj, fn, args != null ? args : []) : null;
		});
		script.set('getObjectOrder', function(target:Dynamic):Int {
			var obj:Dynamic = objectOf(target);
			var instance:Dynamic = LuaUtils.getTargetInstance();
			return obj != null ? instance.members.indexOf(obj) : -1;
		});
		script.set('setObjectOrder', function(target:Dynamic, position:Int):Bool {
			var obj:FlxBasic = objectOf(target);
			if (obj == null)
				return false;
			var instance:Dynamic = LuaUtils.getTargetInstance();
			instance.remove(obj, true);
			instance.insert(position, obj);
			return true;
		});
	}

	static function groupItem(group:Dynamic, index:Int):Dynamic
	{
		var obj:Dynamic = objectOf(group);
		if (obj == null)
			return null;
		if (Std.isOfType(obj, Array))
			return (obj : Array<Dynamic>)[index];
		var members:Array<Dynamic> = Reflect.getProperty(obj, 'members');
		return members != null ? members[index] : null;
	}

	// ------------------------------------------------------------------
	// Sprites
	// ------------------------------------------------------------------

	static function sprites(script:FluxScript):Void
	{
		script.set('makeLuaSprite', function(tag:String, ?image:String, ?x:Float = 0, ?y:Float = 0):ModchartSprite {
			tag = tag.replace('.', '');
			LuaUtils.destroyObject(tag);
			var sprite:ModchartSprite = new ModchartSprite(x, y);
			if (image != null && image.length > 0)
				sprite.loadGraphic(Paths.image(image));
			variables().set(tag, sprite);
			sprite.active = true;
			return sprite;
		});
		script.set('makeAnimatedLuaSprite', function(tag:String, ?image:String, ?x:Float = 0, ?y:Float = 0, ?spriteType:String = 'auto'):ModchartSprite {
			tag = tag.replace('.', '');
			LuaUtils.destroyObject(tag);
			var sprite:ModchartSprite = new ModchartSprite(x, y);
			if (image != null && image.length > 0)
				LuaUtils.loadFrames(sprite, image, spriteType);
			variables().set(tag, sprite);
			return sprite;
		});
		script.set('makeGraphic', function(target:Dynamic, ?width:Int = 256, ?height:Int = 256, ?color:Dynamic = 'FFFFFF') {
			var sprite:FlxSprite = objectOf(target);
			if (sprite != null)
				sprite.makeGraphic(width, height, colorOf(color));
		});
		script.set('addLuaSprite', function(target:Dynamic, ?inFront:Bool = false) {
			var sprite:FlxSprite = objectOf(target);
			if (sprite == null)
				return;
			addToGame(sprite, inFront);
		});
		script.set('removeLuaSprite', function(target:Dynamic, ?destroy:Bool = true) {
			var sprite:FlxBasic = objectOf(target);
			if (sprite == null)
				return;
			LuaUtils.getTargetInstance().remove(sprite, true);
			if (destroy)
			{
				if (Std.isOfType(target, String))
					variables().remove(target);
				sprite.destroy();
			}
		});
		script.set('luaSpriteExists', function(tag:String):Bool return Std.isOfType(variables().get(tag), FlxSprite));

		script.set('addAnimationByPrefix', function(target:Dynamic, name:String, prefix:String, ?fps:Float = 24, ?loop:Bool = true):Bool {
			var sprite:FlxSprite = objectOf(target);
			if (sprite == null || sprite.animation == null)
				return false;
			sprite.animation.addByPrefix(name, prefix, fps, loop);
			if (sprite.animation.curAnim == null)
				playOn(sprite, name, true);
			return true;
		});
		script.set('addAnimationByIndices', function(target:Dynamic, name:String, prefix:String, indices:Dynamic, ?fps:Float = 24, ?loop:Bool = false):Bool {
			return addByIndices(target, name, prefix, indices, fps, loop);
		});
		script.set('addAnimation', function(target:Dynamic, name:String, frames:Dynamic, ?fps:Float = 24, ?loop:Bool = true):Bool {
			return addByIndices(target, name, null, frames, fps, loop);
		});
		script.set('playAnim', function(target:Dynamic, name:String, ?forced:Bool = false, ?reverse:Bool = false, ?startFrame:Int = 0):Bool {
			var obj:Dynamic = objectOf(target);
			if (obj == null)
				return false;
			if (Std.isOfType(obj, objects.Character))
				(obj : objects.Character).playAnim(name, forced, reverse, startFrame);
			else if (Reflect.getProperty(obj, 'playAnim') != null)
				obj.playAnim(name, forced, reverse, startFrame);
			else if (Reflect.getProperty(obj, 'animation') != null)
				(obj : FlxSprite).animation.play(name, forced, reverse, startFrame);
			else
				return false;
			return true;
		});
		script.set('addOffset', function(target:Dynamic, anim:String, x:Float, y:Float):Bool {
			var obj:Dynamic = objectOf(target);
			if (obj == null || Reflect.getProperty(obj, 'addOffset') == null)
				return false;
			obj.addOffset(anim, x, y);
			return true;
		});
		script.set('scaleObject', function(target:Dynamic, x:Float, y:Float, ?updateHitbox:Bool = true) {
			var sprite:FlxSprite = objectOf(target);
			if (sprite == null)
			{
				warn(script, 'scaleObject: no existe "$target"');
				return;
			}
			sprite.scale.set(x, y);
			if (updateHitbox)
				sprite.updateHitbox();
		});
		script.set('setGraphicSize', function(target:Dynamic, x:Float, ?y:Float = 0, ?updateHitbox:Bool = true) {
			var sprite:FlxSprite = objectOf(target);
			if (sprite == null)
			{
				warn(script, 'setGraphicSize: no existe "$target"');
				return;
			}
			sprite.setGraphicSize(x, y);
			if (updateHitbox)
				sprite.updateHitbox();
		});
		script.set('updateHitbox', function(target:Dynamic) {
			var sprite:FlxSprite = objectOf(target);
			if (sprite != null)
				sprite.updateHitbox();
		});
		script.set('setScrollFactor', function(target:Dynamic, x:Float, y:Float) {
			var obj:FlxObject = objectOf(target);
			if (obj != null)
				obj.scrollFactor.set(x, y);
		});
		script.set('setObjectCamera', function(target:Dynamic, ?camera:Dynamic = 'game'):Bool {
			var obj:FlxBasic = objectOf(target);
			if (obj == null)
				return false;
			obj.cameras = [cameraOf(camera)];
			return true;
		});
		script.set('setBlendMode', function(target:Dynamic, ?blend:String = ''):Bool {
			var sprite:FlxSprite = objectOf(target);
			if (sprite == null)
				return false;
			sprite.blend = LuaUtils.blendModeFromString(blend);
			return true;
		});
		script.set('screenCenter', function(target:Dynamic, ?pos:String = 'xy') {
			var obj:FlxObject = objectOf(target);
			if (obj == null)
				return;
			switch (pos.trim().toLowerCase())
			{
				case 'x':
					obj.screenCenter(FlxAxes.X);
				case 'y':
					obj.screenCenter(FlxAxes.Y);
				default:
					obj.screenCenter(FlxAxes.XY);
			}
		});
		script.set('objectsOverlap', function(a:Dynamic, b:Dynamic):Bool {
			var objA:FlxBasic = objectOf(a);
			var objB:FlxBasic = objectOf(b);
			return objA != null && objB != null && FlxG.overlap(objA, objB);
		});
		script.set('getMidpointX', function(target:Dynamic):Float {
			var obj:FlxObject = objectOf(target);
			return obj != null ? obj.getMidpoint().x : 0;
		});
		script.set('getMidpointY', function(target:Dynamic):Float {
			var obj:FlxObject = objectOf(target);
			return obj != null ? obj.getMidpoint().y : 0;
		});
		script.set('getGraphicMidpointX', function(target:Dynamic):Float {
			var sprite:FlxSprite = objectOf(target);
			return sprite != null ? sprite.getGraphicMidpoint().x : 0;
		});
		script.set('getGraphicMidpointY', function(target:Dynamic):Float {
			var sprite:FlxSprite = objectOf(target);
			return sprite != null ? sprite.getGraphicMidpoint().y : 0;
		});
		script.set('getScreenPositionX', function(target:Dynamic, ?camera:Dynamic = 'game'):Float {
			var obj:FlxObject = objectOf(target);
			return obj != null ? obj.getScreenPosition(cameraOf(camera)).x : 0;
		});
		script.set('getScreenPositionY', function(target:Dynamic, ?camera:Dynamic = 'game'):Float {
			var obj:FlxObject = objectOf(target);
			return obj != null ? obj.getScreenPosition(cameraOf(camera)).y : 0;
		});
	}

	/** addLuaSprite de Psych: adelante de todo o atrás de los personajes. */
	public static function addToGame(sprite:FlxBasic, inFront:Bool):Void
	{
		var instance:Dynamic = LuaUtils.getTargetInstance();
		var g:PlayState = PlayState.instance;
		if (inFront || g == null || FlxG.state != g)
			instance.add(sprite);
		else if (!g.isDead)
			instance.insert(instance.members.indexOf(LuaUtils.getLowestCharacterGroup()), sprite);
		else
			GameOverSubstate.instance.insert(GameOverSubstate.instance.members.indexOf(GameOverSubstate.instance.boyfriend), sprite);
	}

	static function playOn(sprite:Dynamic, name:String, forced:Bool):Void
	{
		if (Reflect.getProperty(sprite, 'playAnim') != null)
			sprite.playAnim(name, forced);
		else
			sprite.animation.play(name, forced);
	}

	static function addByIndices(target:Dynamic, name:String, prefix:String, indices:Dynamic, fps:Float, loop:Bool):Bool
	{
		var sprite:FlxSprite = objectOf(target);
		if (sprite == null || sprite.animation == null)
			return false;
		var list:Array<Int> = [0];
		if (indices != null)
		{
			if (Std.isOfType(indices, String))
				list = [for (part in Std.string(indices).trim().split(',')) Std.parseInt(part.trim())];
			else
				list = [for (value in (indices : Array<Dynamic>)) Std.int(value)];
		}
		if (prefix != null)
			sprite.animation.addByIndices(name, prefix, list, '', fps, loop);
		else
			sprite.animation.add(name, list, fps, loop);
		if (sprite.animation.curAnim == null)
			playOn(sprite, name, true);
		return true;
	}

	// ------------------------------------------------------------------
	// Textos
	// ------------------------------------------------------------------

	static function texts(script:FluxScript):Void
	{
		script.set('makeLuaText', function(tag:String, ?text:String = '', ?width:Int = 0, ?x:Float = 0, ?y:Float = 0):FlxText {
			tag = tag.replace('.', '');
			LuaUtils.destroyObject(tag);
			var txt:FlxText = new FlxText(x, y, width, text, 16);
			txt.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			var g:PlayState = game();
			if (g != null)
				txt.cameras = [g.camHUD];
			txt.scrollFactor.set();
			txt.borderSize = 2;
			variables().set(tag, txt);
			return txt;
		});
		script.set('addLuaText', function(target:Dynamic) {
			var txt:FlxText = objectOf(target);
			if (txt != null)
				LuaUtils.getTargetInstance().add(txt);
		});
		script.set('removeLuaText', function(target:Dynamic, ?destroy:Bool = true) {
			var txt:FlxText = objectOf(target);
			if (txt == null)
				return;
			LuaUtils.getTargetInstance().remove(txt, true);
			if (destroy)
			{
				if (Std.isOfType(target, String))
					variables().remove(target);
				txt.destroy();
			}
		});
		script.set('luaTextExists', function(tag:String):Bool return Std.isOfType(variables().get(tag), FlxText));
		script.set('setTextString', function(target:Dynamic, text:String) {
			var txt:FlxText = objectOf(target);
			if (txt != null)
				txt.text = text;
		});
		script.set('getTextString', function(target:Dynamic):String {
			var txt:FlxText = objectOf(target);
			return txt != null ? txt.text : null;
		});
		script.set('setTextSize', function(target:Dynamic, size:Int) {
			var txt:FlxText = objectOf(target);
			if (txt != null)
				txt.size = size;
		});
		script.set('setTextWidth', function(target:Dynamic, width:Float) {
			var txt:FlxText = objectOf(target);
			if (txt != null)
				txt.fieldWidth = width;
		});
		script.set('setTextColor', function(target:Dynamic, color:Dynamic) {
			var txt:FlxText = objectOf(target);
			if (txt != null)
				txt.color = colorOf(color);
		});
		script.set('setTextFont', function(target:Dynamic, font:String) {
			var txt:FlxText = objectOf(target);
			if (txt != null)
				txt.font = Paths.font(font);
		});
		script.set('setTextBorder', function(target:Dynamic, size:Float, ?color:Dynamic = 'FF000000', ?style:String = 'outline') {
			var txt:FlxText = objectOf(target);
			if (txt == null)
				return;
			txt.borderSize = size;
			txt.borderColor = colorOf(color);
			txt.borderStyle = switch (style.toLowerCase().trim())
			{
				case 'shadow': FlxTextBorderStyle.SHADOW;
				case 'outline_fast' | 'outlinefast': FlxTextBorderStyle.OUTLINE_FAST;
				case 'none': FlxTextBorderStyle.NONE;
				default: FlxTextBorderStyle.OUTLINE;
			}
		});
		script.set('setTextAlignment', function(target:Dynamic, ?alignment:String = 'left') {
			var txt:FlxText = objectOf(target);
			if (txt == null)
				return;
			txt.alignment = switch (alignment.trim().toLowerCase())
			{
				case 'right': FlxTextAlign.RIGHT;
				case 'center': FlxTextAlign.CENTER;
				case 'justify': FlxTextAlign.JUSTIFY;
				default: FlxTextAlign.LEFT;
			}
		});
	}

	// ------------------------------------------------------------------
	// Tweens y timers
	// ------------------------------------------------------------------

	static function tweensAndTimers(script:FluxScript):Void
	{
		function tweenTo(tag:String, vars:Dynamic, values:Dynamic, duration:Float, ease:String, func:String):String
		{
			var target:Dynamic = Std.isOfType(vars, String) ? LuaUtils.tweenPrepare(tag, vars) : vars;
			if (!Std.isOfType(vars, String) && tag != null)
				LuaUtils.cancelTween(tag);
			if (target == null)
			{
				warn(script, '$func: no existe "$vars"');
				return null;
			}
			var options:Dynamic = {ease: LuaUtils.getTweenEaseByString(ease)};
			if (tag == null)
			{
				FlxTween.tween(target, values, duration, options);
				return null;
			}
			var key:String = LuaUtils.formatVariable('tween_$tag');
			var varsName:String = Std.isOfType(vars, String) ? vars : null;
			options.onComplete = function(_) {
				variables().remove(key);
				callSafe(script, 'onTweenCompleted', [tag, varsName]);
			};
			variables().set(key, FlxTween.tween(target, values, duration, options));
			return key;
		}

		script.set('doTweenX', function(tag:String, vars:Dynamic, value:Dynamic, duration:Float, ?ease:String = 'linear')
			return tweenTo(tag, vars, {x: value}, duration, ease, 'doTweenX'));
		script.set('doTweenY', function(tag:String, vars:Dynamic, value:Dynamic, duration:Float, ?ease:String = 'linear')
			return tweenTo(tag, vars, {y: value}, duration, ease, 'doTweenY'));
		script.set('doTweenAngle', function(tag:String, vars:Dynamic, value:Dynamic, duration:Float, ?ease:String = 'linear')
			return tweenTo(tag, vars, {angle: value}, duration, ease, 'doTweenAngle'));
		script.set('doTweenAlpha', function(tag:String, vars:Dynamic, value:Dynamic, duration:Float, ?ease:String = 'linear')
			return tweenTo(tag, vars, {alpha: value}, duration, ease, 'doTweenAlpha'));
		script.set('doTweenZoom', function(tag:String, camera:Dynamic, value:Dynamic, duration:Float, ?ease:String = 'linear')
			return tweenTo(tag, cameraOf(camera), {zoom: value}, duration, ease, 'doTweenZoom'));
		script.set('doTweenColor', function(tag:String, vars:Dynamic, targetColor:Dynamic, duration:Float, ?ease:String = 'linear'):String {
			var target:Dynamic = Std.isOfType(vars, String) ? LuaUtils.tweenPrepare(tag, vars) : vars;
			if (target == null)
			{
				warn(script, 'doTweenColor: no existe "$vars"');
				return null;
			}
			var current:FlxColor = target.color;
			current.alphaFloat = target.alpha;
			var options:Dynamic = {ease: LuaUtils.getTweenEaseByString(ease)};
			if (tag == null)
			{
				FlxTween.color(target, duration, current, colorOf(targetColor), options);
				return null;
			}
			var key:String = LuaUtils.formatVariable('tween_$tag');
			options.onComplete = function(_) {
				variables().remove(key);
				callSafe(script, 'onTweenCompleted', [tag, Std.isOfType(vars, String) ? vars : null]);
			};
			variables().set(key, FlxTween.color(target, duration, current, colorOf(targetColor), options));
			return key;
		});
		script.set('startTween', function(tag:String, vars:Dynamic, values:Dynamic, duration:Float, ?options:Dynamic):String {
			var target:Dynamic = Std.isOfType(vars, String) ? LuaUtils.tweenPrepare(tag, vars) : vars;
			if (target == null || values == null)
			{
				warn(script, 'startTween: no existe "$vars" o faltan los valores');
				return null;
			}
			var opts:Dynamic = LuaUtils.getLuaTween(options);
			var key:String = tag != null ? LuaUtils.formatVariable('tween_$tag') : null;
			var varsName:String = Std.isOfType(vars, String) ? vars : null;
			var tweenOptions:Dynamic = {};
			if (opts != null)
			{
				tweenOptions.type = opts.type;
				tweenOptions.ease = opts.ease;
				tweenOptions.startDelay = opts.startDelay;
				tweenOptions.loopDelay = opts.loopDelay;
				tweenOptions.onUpdate = function(_) if (opts.onUpdate != null) callSafe(script, opts.onUpdate, [tag, varsName]);
				tweenOptions.onStart = function(_) if (opts.onStart != null) callSafe(script, opts.onStart, [tag, varsName]);
			}
			tweenOptions.onComplete = function(twn:FlxTween) {
				if (key != null && (twn.type == FlxTweenType.ONESHOT || twn.type == FlxTweenType.BACKWARD))
					variables().remove(key);
				if (opts != null && opts.onComplete != null)
					callSafe(script, opts.onComplete, [tag, varsName]);
			};
			var tween:FlxTween = FlxTween.tween(target, values, duration, tweenOptions);
			if (key != null)
				variables().set(key, tween);
			return key;
		});
		script.set('cancelTween', function(tag:String) LuaUtils.cancelTween(tag));

		function noteTween(tag:String, note:Int, values:Dynamic, duration:Float, ease:String):String
		{
			var g:PlayState = game();
			if (g == null)
				return null;
			var strum:StrumNote = g.strumLineNotes.members[note % g.strumLineNotes.length];
			if (strum == null)
				return null;
			return tweenTo(tag, strum, values, duration, ease, 'noteTween');
		}
		script.set('noteTweenX', function(tag:String, note:Int, value:Dynamic, duration:Float, ?ease:String = 'linear')
			return noteTween(tag, note, {x: value}, duration, ease));
		script.set('noteTweenY', function(tag:String, note:Int, value:Dynamic, duration:Float, ?ease:String = 'linear')
			return noteTween(tag, note, {y: value}, duration, ease));
		script.set('noteTweenAngle', function(tag:String, note:Int, value:Dynamic, duration:Float, ?ease:String = 'linear')
			return noteTween(tag, note, {angle: value}, duration, ease));
		script.set('noteTweenAlpha', function(tag:String, note:Int, value:Dynamic, duration:Float, ?ease:String = 'linear')
			return noteTween(tag, note, {alpha: value}, duration, ease));
		script.set('noteTweenDirection', function(tag:String, note:Int, value:Dynamic, duration:Float, ?ease:String = 'linear')
			return noteTween(tag, note, {direction: value}, duration, ease));

		script.set('runTimer', function(tag:String, ?time:Float = 1, ?loops:Int = 1):String {
			LuaUtils.cancelTimer(tag);
			var key:String = LuaUtils.formatVariable('timer_$tag');
			variables().set(key, new FlxTimer().start(time, function(tmr:FlxTimer) {
				if (tmr.finished)
					variables().remove(key);
				callSafe(script, 'onTimerCompleted', [tag, tmr.loops, tmr.loopsLeft]);
			}, loops));
			return key;
		});
		script.set('cancelTimer', function(tag:String) LuaUtils.cancelTimer(tag));
	}

	// ------------------------------------------------------------------
	// Sonido
	// ------------------------------------------------------------------

	static function sounds(script:FluxScript):Void
	{
		function soundOf(tag:String):FlxSound
		{
			var sound:Dynamic = variables().get('sound_${LuaUtils.formatVariable(tag)}');
			return Std.isOfType(sound, FlxSound) ? sound : null;
		}

		// playSound(nombre, volumen, tag, loop) como en Lua, o playSound(nombre, volumen, alTerminar)
		script.set('playSound', function(name:String, ?volume:Float = 1, ?tagOrCallback:Dynamic, ?loop:Bool = false):FlxSound {
			var callback:Dynamic = (tagOrCallback != null && Reflect.isFunction(tagOrCallback)) ? tagOrCallback : null;
			var tag:String = (tagOrCallback != null && Std.isOfType(tagOrCallback, String)) ? tagOrCallback : null;
			if (tag == null || tag.length == 0)
			{
				return FlxG.sound.play(Paths.sound(name), volume, loop, null, true, callback != null ? function() {
					try
						Reflect.callMethod(null, callback, [])
					catch (e:Dynamic)
						script.error('Error en playSound: ' + FluxScript.errorText(e));
				} : null);
			}
			var key:String = 'sound_${LuaUtils.formatVariable(tag)}';
			var old:FlxSound = variables().get(key);
			if (old != null)
				old.stop();
			var sound:FlxSound = FlxG.sound.play(Paths.sound(name), volume, loop, null, true, function() {
				if (!loop)
					variables().remove(key);
				callSafe(script, 'onSoundFinished', [tag]);
			});
			variables().set(key, sound);
			return sound;
		});
		script.set('playMusic', function(name:String, ?volume:Float = 1, ?loop:Bool = false) FlxG.sound.playMusic(Paths.music(name), volume, loop));
		script.set('stopSound', function(?tag:String) {
			if (tag == null || tag.length == 0)
			{
				if (FlxG.sound.music != null)
					FlxG.sound.music.stop();
				return;
			}
			var sound:FlxSound = soundOf(tag);
			if (sound != null)
			{
				sound.stop();
				variables().remove('sound_${LuaUtils.formatVariable(tag)}');
			}
		});
		script.set('pauseSound', function(?tag:String) {
			var sound:FlxSound = (tag == null || tag.length == 0) ? FlxG.sound.music : soundOf(tag);
			if (sound != null)
				sound.pause();
		});
		script.set('resumeSound', function(?tag:String) {
			var sound:FlxSound = (tag == null || tag.length == 0) ? FlxG.sound.music : soundOf(tag);
			if (sound != null)
				sound.play();
		});
		script.set('soundFadeIn', function(?tag:String, duration:Float, ?from:Float = 0, ?to:Float = 1) {
			var sound:FlxSound = (tag == null || tag.length == 0) ? FlxG.sound.music : soundOf(tag);
			if (sound != null)
				sound.fadeIn(duration, from, to);
		});
		script.set('soundFadeOut', function(?tag:String, duration:Float, ?to:Float = 0) {
			var sound:FlxSound = (tag == null || tag.length == 0) ? FlxG.sound.music : soundOf(tag);
			if (sound != null)
				sound.fadeOut(duration, to);
		});
		script.set('setSoundVolume', function(?tag:String, value:Float) {
			var sound:FlxSound = (tag == null || tag.length == 0) ? FlxG.sound.music : soundOf(tag);
			if (sound != null)
				sound.volume = value;
		});
		script.set('getSoundVolume', function(?tag:String):Float {
			var sound:FlxSound = (tag == null || tag.length == 0) ? FlxG.sound.music : soundOf(tag);
			return sound != null ? sound.volume : 0;
		});
		script.set('setSoundTime', function(?tag:String, value:Float) {
			var sound:FlxSound = (tag == null || tag.length == 0) ? FlxG.sound.music : soundOf(tag);
			if (sound != null)
				sound.time = value;
		});
		script.set('getSoundTime', function(?tag:String):Float {
			var sound:FlxSound = (tag == null || tag.length == 0) ? FlxG.sound.music : soundOf(tag);
			return sound != null ? sound.time : 0;
		});
		script.set('luaSoundExists', function(tag:String):Bool return soundOf(tag) != null);
		script.set('precacheImage', function(name:String) Paths.image(name));
		script.set('precacheSound', function(name:String) Paths.sound(name));
		script.set('precacheMusic', function(name:String) Paths.music(name));
	}

	// ------------------------------------------------------------------
	// Cámaras
	// ------------------------------------------------------------------

	static function cameras(script:FluxScript):Void
	{
		script.set('getCamera', function(?name:Dynamic = 'game'):FlxCamera return cameraOf(name));
		script.set('cameraShake', function(camera:Dynamic, intensity:Float, duration:Float) {
			var cam:FlxCamera = cameraOf(camera);
			if (cam != null)
				cam.shake(intensity, duration);
		});
		script.set('cameraFlash', function(camera:Dynamic, ?color:Dynamic = 'FFFFFF', ?duration:Float = 0.5, ?forced:Bool = false) {
			var cam:FlxCamera = cameraOf(camera);
			if (cam != null)
				cam.flash(colorOf(color), duration, null, forced);
		});
		script.set('cameraFade', function(camera:Dynamic, ?color:Dynamic = 'FF000000', ?duration:Float = 0.5, ?forced:Bool = false, ?fadeOut:Bool = false) {
			var cam:FlxCamera = cameraOf(camera);
			if (cam != null)
				cam.fade(colorOf(color), duration, fadeOut, null, forced);
		});
		script.set('cameraSetTarget', function(target:String):Bool {
			var g:PlayState = game();
			if (g == null)
				return false;
			switch (target.trim().toLowerCase())
			{
				case 'gf' | 'girlfriend':
					g.moveCameraToGirlfriend();
				case 'dad' | 'opponent':
					g.moveCamera(true);
				default:
					g.moveCamera(false);
			}
			return true;
		});
	}

	// ------------------------------------------------------------------
	// La canción
	// ------------------------------------------------------------------

	static function song(script:FluxScript):Void
	{
		script.set('characterPlayAnim', function(character:String, anim:String, ?forced:Bool = false) {
			var c:objects.Character = characterOf(character);
			if (c != null && c.hasAnimation(anim))
				c.playAnim(anim, forced);
		});
		script.set('characterDance', function(character:String) {
			var c:objects.Character = characterOf(character);
			if (c != null)
				c.dance();
		});
		script.set('startCountdown', function() {
			var g:PlayState = game();
			if (g != null)
				g.startCountdown();
		});
		script.set('endSong', function() {
			var g:PlayState = game();
			if (g != null)
			{
				g.KillNotes();
				g.endSong();
			}
		});
		script.set('restartSong', function(?skipTransition:Bool = false) {
			var g:PlayState = game();
			if (g == null)
				return;
			g.persistentUpdate = false;
			FlxG.camera.followLerp = 0;
			substates.PauseSubState.restartSong(skipTransition);
		});
		script.set('exitSong', function(?skipTransition:Bool = false) {
			var g:PlayState = game();
			if (g == null)
				return;
			if (skipTransition)
			{
				FlxTransitionableState.skipNextTransIn = true;
				FlxTransitionableState.skipNextTransOut = true;
			}
			if (PlayState.isStoryMode)
				MusicBeatState.switchState(new states.StoryMenuState());
			else
				MusicBeatState.switchState(new states.FreeplayState());
			FlxG.sound.playMusic(Paths.music('freakyMenu'));
			PlayState.changedDifficulty = false;
			PlayState.chartingMode = false;
			g.transitioning = true;
			FlxG.camera.followLerp = 0;
			backend.Mods.loadTopMod();
		});
		script.set('getSongPosition', function():Float return Conductor.songPosition);

		script.set('addScore', function(?value:Int = 0) withGame(g -> g.songScore += value, true));
		script.set('addMisses', function(?value:Int = 0) withGame(g -> g.songMisses += value, true));
		script.set('addHits', function(?value:Int = 0) withGame(g -> g.songHits += value, true));
		script.set('setScore', function(?value:Int = 0) withGame(g -> g.songScore = value, true));
		script.set('setMisses', function(?value:Int = 0) withGame(g -> g.songMisses = value, true));
		script.set('setHits', function(?value:Int = 0) withGame(g -> g.songHits = value, true));
		script.set('setHealth', function(?value:Float = 1) withGame(g -> g.health = value, false));
		script.set('addHealth', function(?value:Float = 0) withGame(g -> g.health += value, false));
		script.set('getHealth', function():Float return game() != null ? game().health : 0);

		script.set('setHealthBarColors', function(?left:Dynamic, ?right:Dynamic) {
			var g:PlayState = game();
			if (g != null)
				g.healthBar.setColors(left != null && left != '' ? colorOf(left) : null, right != null && right != '' ? colorOf(right) : null);
		});
		script.set('setTimeBarColors', function(?left:Dynamic, ?right:Dynamic) {
			var g:PlayState = game();
			if (g != null)
				g.timeBar.setColors(left != null && left != '' ? colorOf(left) : null, right != null && right != '' ? colorOf(right) : null);
		});
		script.set('triggerEvent', function(name:String, ?value1:Dynamic = '', ?value2:Dynamic = '') {
			var g:PlayState = game();
			if (g != null)
				g.triggerEvent(name, Std.string(value1), Std.string(value2), Conductor.songPosition);
		});
	}

	static function characterOf(name:String):objects.Character
	{
		var g:PlayState = PlayState.instance;
		if (g == null || name == null)
			return null;
		return switch (name.toLowerCase())
		{
			case 'dad' | 'opponent': g.dad;
			case 'gf' | 'girlfriend': g.gf;
			default: g.boyfriend;
		}
	}

	static function withGame(fn:PlayState->Void, recalculate:Bool):Void
	{
		var g:PlayState = game();
		if (g == null)
			return;
		fn(g);
		if (recalculate)
			g.RecalculateRating();
	}

	// ------------------------------------------------------------------
	// Otros
	// ------------------------------------------------------------------

	static function other(script:FluxScript):Void
	{
		script.set('getColorFromHex', function(color:String):Int return CoolUtil.colorFromString(color));
		script.set('getRandomInt', function(?min:Int = 0, ?max:Int = 100, ?exclude:Dynamic):Int {
			var excluded:Array<Int> = [];
			if (exclude != null)
			{
				if (Std.isOfType(exclude, String))
				{
					for (part in Std.string(exclude).split(','))
						if (part.trim().length > 0)
							excluded.push(Std.parseInt(part.trim()));
				}
				else
					excluded = exclude;
			}
			return FlxG.random.int(min, max, excluded);
		});
		script.set('getRandomFloat', function(?min:Float = 0, ?max:Float = 1):Float return FlxG.random.float(min, max));
		script.set('getRandomBool', function(?chance:Float = 50):Bool return FlxG.random.bool(chance));
		script.set('close', function() script.close());
	}
}
