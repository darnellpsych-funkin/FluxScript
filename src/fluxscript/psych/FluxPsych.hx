package fluxscript.psych;

import backend.ClientPrefs;
import backend.Conductor;
import backend.CoolUtil;
import backend.Highscore;
import backend.Mods;
import backend.MusicBeatState;
import backend.Paths;
import backend.Song;
import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.sound.FlxSound;
import flixel.addons.transition.FlxTransitionableState;
import flixel.input.gamepad.FlxGamepad;
import flixel.input.gamepad.FlxGamepadInputID;
import flixel.text.FlxText;
import flixel.text.FlxText.FlxTextAlign;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxTween.FlxTweenType;
import flixel.util.FlxAxes;
import flixel.util.FlxColor;
import flixel.util.FlxSave;
import flixel.util.FlxTimer;
import fluxscript.FluxClasses;
import fluxscript.FluxFlixel;
import fluxscript.FluxScript;
import objects.StrumNote;
import openfl.utils.AssetType;
import openfl.utils.Assets;
import psychlua.CustomSubstate;
import psychlua.LuaUtils;
import psychlua.ModchartSprite;
import states.LoadingState;
import states.PlayState;
import substates.GameOverSubstate;
#if (!flash && sys)
import flixel.addons.display.FlxRuntimeShader;
#end
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/**
 * FluxScript en Psych Engine 1.0 y sus forks (Flux Engine, P-Slice...).
 *
 * Le pone a un FluxScript lo mismo que tiene un .hx de Psych (game, setVar,
 * debugPrint, Function_Stop...) y la API de Lua de Psych, con los mismos nombres y
 * argumentos: makeLuaSprite, addLuaSprite, setProperty, doTweenX, runTimer,
 * playSound, makeLuaText, setShaderFloat, initSaveData, addLuaScript... Los tags son
 * los mismos que usan los .lua (MusicBeatState.getVariables()), así que los dos se
 * pueden mezclar. También el preset de los .hxs de Psych (makeSprite, makeText,
 * switchState...) si el engine no puso el suyo, y busca en los mods los archivos de
 * require, importScript, fileExists y readFile.
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
		script.usePreset('FluxPsych', setup);

	static function setup(script:FluxScript):Void
	{
		register();
		hxs(script); // antes que FluxFlixel: así sus makeText/makeSprite son los de Psych
		FluxFlixel.apply(script);
		preset(script);
		properties(script);
		sprites(script);
		groups(script);
		texts(script);
		tweensAndTimers(script);
		sounds(script);
		cameras(script);
		song(script);
		input(script);
		saves(script);
		files(script);
		shaderApi(script);
		scripts(script);
		reflection(script);
		other(script);
		deprecated(script);
	}

	static var registered:Bool = false;

	/** Lo que se hace una sola vez: buscar los archivos en los mods y los `import` de otros engines. */
	static function register():Void
	{
		if (registered)
			return;
		registered = true;

		// require, importScript, fileExists y readFile: al lado del script, en los mods y en assets
		var previous:(String, ?FluxScript) -> String = FluxScript.findFile;
		FluxScript.findFile = function(path:String, ?from:FluxScript):String {
			var found:String = FluxScript.findLocalFile(path, from);
			if (found == null)
				found = findInMods(path, from != null ? from.modFolder : null);
			return found != null ? found : previous(path, from);
		};

		// los `import` de Codename y V-Slice usan su equivalente de Psych (si el engine no puso otra cosa)
		if (FluxClasses.resolver == null)
			FluxClasses.resolver = resolveImport;

		var defines:Map<String, Dynamic> = FluxScript.defines;
		if (!defines.exists('PSYCH'))
			defines.set('PSYCH', true);
		#if LUA_ALLOWED defines.set('LUA_ALLOWED', true); #end
		#if MODS_ALLOWED defines.set('MODS_ALLOWED', true); #end
		#if VIDEOS_ALLOWED defines.set('VIDEOS_ALLOWED', true); #end
	}

	/** Un archivo de los mods (el del script, el actual y los globales) o de assets. */
	public static function findInMods(path:String, ?modFolder:String):String
	{
		if (path == null || path.length == 0)
			return null;
		#if sys
		#if MODS_ALLOWED
		var modded:String = Paths.modFolders(path);
		if (FileSystem.exists(modded) && !FileSystem.isDirectory(modded))
			return modded;
		if (modFolder != null && modFolder.length > 0)
		{
			var own:String = Paths.mods('$modFolder/$path');
			if (FileSystem.exists(own) && !FileSystem.isDirectory(own))
				return own;
		}
		#end
		var shared:String = Paths.getSharedPath(path);
		if (FileSystem.exists(shared) && !FileSystem.isDirectory(shared))
			return shared;
		if (FileSystem.exists('assets/$path') && !FileSystem.isDirectory('assets/$path'))
			return 'assets/$path';
		#end
		return null;
	}

	/** El equivalente en Psych de las clases de Codename Engine y V-Slice (para los `import`). */
	public static function resolveImport(path:String):Dynamic
	{
		return switch (path)
		{
			case 'funkin.game.PlayState' | 'funkin.play.PlayState': PlayState;
			case 'funkin.backend.assets.Paths' | 'funkin.Paths': Paths;
			case 'funkin.backend.system.Conductor' | 'funkin.Conductor': Conductor;
			case 'funkin.backend.utils.CoolUtil' | 'funkin.util.CoolUtil': CoolUtil;
			case 'funkin.game.Character' | 'funkin.play.character.BaseCharacter': objects.Character;
			case 'funkin.game.HealthIcon' | 'funkin.play.components.HealthIcon': objects.HealthIcon;
			case 'funkin.game.Note' | 'funkin.play.notes.NoteSprite': objects.Note;
			case 'funkin.game.Strum' | 'funkin.play.notes.StrumlineNote': objects.StrumNote;
			case 'funkin.backend.MusicBeatState' | 'funkin.ui.MusicBeatState': MusicBeatState;
			case 'funkin.backend.MusicBeatSubstate' | 'funkin.ui.MusicBeatSubState': backend.MusicBeatSubstate;
			case 'funkin.backend.FunkinSprite' | 'funkin.graphics.FunkinSprite': FlxSprite;
			case 'funkin.backend.FunkinText': FlxText;
			case 'funkin.menus.MainMenuState' | 'funkin.ui.mainmenu.MainMenuState': states.MainMenuState;
			case 'funkin.menus.FreeplayState' | 'funkin.ui.freeplay.FreeplayState': states.FreeplayState;
			case 'funkin.menus.StoryMenuState' | 'funkin.ui.story.StoryMenuState': states.StoryMenuState;
			case 'funkin.menus.TitleState' | 'funkin.ui.title.TitleState': states.TitleState;
			case 'funkin.options.OptionsMenu' | 'funkin.ui.options.OptionsState': options.OptionsState;
			case 'funkin.backend.system.Controls': backend.Controls;
			default: null;
		}
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

	/** Una cámara por nombre ('game', 'hud', 'other', o un tag) o la cámara misma. Fuera de la canción, FlxG.camera. */
	static function cameraOf(value:Dynamic):FlxCamera
	{
		if (value != null && Std.isOfType(value, FlxCamera))
			return value;
		var name:String = value != null ? Std.string(value) : 'game';
		if (game() != null)
			return LuaUtils.cameraFromString(name);
		var tagged:Dynamic = variables().get(name);
		return Std.isOfType(tagged, FlxCamera) ? tagged : FlxG.camera;
	}

	static function callSafe(script:FluxScript, name:String, args:Array<Dynamic>):Void
	{
		if (script.active)
			script.call(name, args);
	}

	/** El grupo o la lista de un tag o un nombre ("notes", "boyfriendGroup"...), o el grupo mismo. */
	static function groupOf(target:Dynamic):Dynamic
	{
		if (target == null || !Std.isOfType(target, String))
			return target;
		var found:Dynamic = objectOf(target);
		if (found == null)
			found = Reflect.getProperty(LuaUtils.getTargetInstance(), target);
		return found;
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
		script.set('ErrorHandledRuntimeShader', shaders.ErrorHandledShader.ErrorHandledRuntimeShader);
		#end
		script.set('ShaderFilter', openfl.filters.ShaderFilter);
		script.set('PsychCamera', backend.PsychCamera);
		script.set('Alphabet', objects.Alphabet);
		#if ACHIEVEMENTS_ALLOWED
		script.set('Achievements', backend.Achievements);
		#end
		#if flxanimate
		script.set('FlxAnimate', flxanimate.PsychFlxAnimate);
		#end
		#if sys
		script.set('File', File);
		script.set('FileSystem', FileSystem);
		#end

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
		script.set('setProperty', function(path:String, value:Dynamic, ?allowMaps:Bool = false, ?allowInstances:Bool = false):Dynamic {
			if (allowInstances)
				value = parseInstances(value);
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
		script.set('setPropertyFromClass', function(classPath:String, path:String, value:Dynamic, ?allowMaps:Bool = false, ?allowInstances:Bool = false):Dynamic {
			if (allowInstances)
				value = parseInstances(value);
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
		script.set('setPropertyFromGroup', function(group:Dynamic, index:Int, field:String, value:Dynamic, ?allowMaps:Bool = false, ?allowInstances:Bool = false):Dynamic {
			if (allowInstances)
				value = parseInstances(value);
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
			return Reflect.callMethod(owner, fn, args != null ? parseInstances(args) : []);
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
			return (fn != null && Reflect.isFunction(fn)) ? Reflect.callMethod(obj, fn, args != null ? parseInstances(args) : []) : null;
		});
		// getObjectOrder(objeto, ?grupo) / setObjectOrder(objeto, posición, ?grupo), como en Lua
		script.set('getObjectOrder', function(target:Dynamic, ?group:Dynamic):Int {
			var obj:Dynamic = objectOf(target);
			if (obj == null)
			{
				warn(script, 'getObjectOrder: no existe "$target"');
				return -1;
			}
			var list:Dynamic = group != null ? groupOf(group) : orderTarget();
			if (list == null)
			{
				warn(script, 'getObjectOrder: no existe el grupo "$group"');
				return -1;
			}
			return Std.isOfType(list, Array) ? (list : Array<Dynamic>).indexOf(obj) : (Reflect.getProperty(list, 'members') : Array<Dynamic>).indexOf(obj);
		});
		script.set('setObjectOrder', function(target:Dynamic, position:Int, ?group:Dynamic):Bool {
			var obj:Dynamic = objectOf(target);
			if (obj == null)
			{
				warn(script, 'setObjectOrder: no existe "$target"');
				return false;
			}
			var list:Dynamic = group != null ? groupOf(group) : orderTarget();
			if (list == null)
			{
				warn(script, 'setObjectOrder: no existe el grupo "$group"');
				return false;
			}
			if (Std.isOfType(list, Array))
			{
				(list : Array<Dynamic>).remove(obj);
				(list : Array<Dynamic>).insert(position, obj);
			}
			else
			{
				list.remove(obj, true);
				list.insert(position, obj);
			}
			return true;
		});
	}

	/** Donde se ordenan los objetos (el CustomSubstate abierto, o el estado). */
	static function orderTarget():Dynamic
		return CustomSubstate.instance != null ? CustomSubstate.instance : LuaUtils.getTargetInstance();

	static inline var INSTANCE_TAG:String = '##PSYCHLUA_STRINGTOOBJ';

	/** Los textos de instanceArg('tag') pasan a ser el objeto (como en Lua). */
	public static function parseInstances(arg:Dynamic):Dynamic
	{
		if (arg == null)
			return null;
		if (Std.isOfType(arg, Array))
			return [for (value in (arg : Array<Dynamic>)) parseInstances(value)];
		if (!Std.isOfType(arg, String))
			return arg;
		var text:String = arg;
		if (text.length <= INSTANCE_TAG.length || !text.startsWith(INSTANCE_TAG))
			return arg;
		var index:Int = text.indexOf('::');
		if (index < 0)
			return arg;
		text = text.substring(index + 2);
		var last:Int = text.lastIndexOf('::');
		var split:Array<String> = (last > -1) ? text.substring(0, last).split('.') : text.split('.');
		var obj:Dynamic = (last > -1) ? Type.resolveClass(text.substring(last + 2)) : PlayState.instance;
		for (part in split)
			obj = LuaUtils.getVarInArray(obj, part.trim());
		return obj;
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
		script.set('removeLuaSprite', function(target:Dynamic, ?destroy:Bool = true, ?group:Dynamic) {
			var sprite:FlxBasic = objectOf(target);
			if (sprite == null)
				return;
			var owner:Dynamic = group != null ? groupOf(group) : LuaUtils.getTargetInstance();
			if (owner != null)
				owner.remove(sprite, true);
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
		moreSprites(script);
	}

	// ------------------------------------------------------------------
	// Grupos
	// ------------------------------------------------------------------

	static function groups(script:FluxScript):Void
	{
		script.set('addToGroup', function(group:Dynamic, target:Dynamic, ?index:Int = -1):Bool {
			var obj:Dynamic = objectOf(target);
			if (obj == null)
			{
				warn(script, 'addToGroup: no existe "$target"');
				return false;
			}
			var list:Dynamic = groupOf(group);
			if (list == null)
			{
				warn(script, 'addToGroup: no existe el grupo "$group"');
				return false;
			}
			if (index < 0)
			{
				if (Std.isOfType(list, Array))
					(list : Array<Dynamic>).push(obj);
				else
					list.add(obj);
			}
			else
				list.insert(index, obj);
			return true;
		});
		script.set('removeFromGroup', function(group:Dynamic, ?index:Int = -1, ?target:Dynamic, ?destroy:Bool = true):Bool {
			var obj:Dynamic = target != null ? objectOf(target) : null;
			if (target != null && obj == null)
			{
				warn(script, 'removeFromGroup: no existe "$target"');
				return false;
			}
			var list:Dynamic = groupOf(group);
			if (list == null)
			{
				warn(script, 'removeFromGroup: no existe el grupo "$group"');
				return false;
			}
			if (Std.isOfType(list, Array))
			{
				var array:Array<Dynamic> = list;
				if (obj == null)
					obj = array[index];
				array.remove(obj);
			}
			else
			{
				if (obj == null)
					obj = (Reflect.getProperty(list, 'members') : Array<Dynamic>)[index];
				list.remove(obj, true);
			}
			if (destroy && obj != null && Reflect.getProperty(obj, 'destroy') != null)
				obj.destroy();
			return obj != null;
		});
		script.set('updateHitboxFromGroup', function(group:Dynamic, index:Int):Bool {
			var item:Dynamic = groupItem(group, index);
			if (item == null || !Std.isOfType(item, FlxSprite))
				return false;
			(item : FlxSprite).updateHitbox();
			return true;
		});
	}

	/** Lo que faltaba de los sprites de Lua: cargar imágenes, colores de un pixel y Animate. */
	static function moreSprites(script:FluxScript):Void
	{
		script.set('loadGraphic', function(target:Dynamic, image:String, ?gridX:Int = 0, ?gridY:Int = 0):Bool {
			var sprite:FlxSprite = objectOf(target);
			if (sprite == null || image == null || image.length == 0)
				return false;
			sprite.loadGraphic(Paths.image(image), gridX != 0 || gridY != 0, gridX, gridY);
			return true;
		});
		script.set('loadFrames', function(target:Dynamic, image:String, ?spriteType:String = 'auto'):Bool {
			var sprite:FlxSprite = objectOf(target);
			if (sprite == null || image == null || image.length == 0)
				return false;
			LuaUtils.loadFrames(sprite, image, spriteType);
			return true;
		});
		script.set('loadMultipleFrames', function(target:Dynamic, images:Array<String>):Bool {
			var sprite:FlxSprite = objectOf(target);
			if (sprite == null || images == null || images.length == 0)
				return false;
			sprite.frames = Paths.getMultiAtlas(images);
			return true;
		});
		script.set('getPixelColor', function(target:Dynamic, x:Int, y:Int):Int {
			var sprite:FlxSprite = objectOf(target);
			return (sprite != null && sprite.pixels != null) ? sprite.pixels.getPixel32(x, y) : FlxColor.BLACK;
		});
		script.set('addAnimationByIndicesLoop', function(target:Dynamic, name:String, prefix:String, indices:Dynamic, ?fps:Float = 24):Bool {
			return addByIndices(target, name, prefix, indices, fps, true);
		});

		#if flxanimate
		script.set('makeFlxAnimateSprite', function(tag:String, ?x:Float = 0, ?y:Float = 0, ?loadFolder:String):psychlua.ModchartAnimateSprite {
			tag = tag.replace('.', '');
			var last:Dynamic = variables().get(tag);
			if (last != null)
			{
				last.kill();
				LuaUtils.getTargetInstance().remove(last, true);
				last.destroy();
			}
			var sprite:psychlua.ModchartAnimateSprite = new psychlua.ModchartAnimateSprite(x, y);
			if (loadFolder != null)
				Paths.loadAnimateAtlas(sprite, loadFolder);
			variables().set(tag, sprite);
			sprite.active = true;
			return sprite;
		});
		script.set('loadAnimateAtlas', function(target:Dynamic, folderOrImg:String, ?spriteJson:String, ?animationJson:String):Bool {
			var sprite:Dynamic = objectOf(target);
			if (sprite == null || !Std.isOfType(sprite, flxanimate.PsychFlxAnimate))
				return false;
			Paths.loadAnimateAtlas(sprite, folderOrImg, spriteJson, animationJson);
			return true;
		});
		script.set('addAnimationBySymbol', function(target:Dynamic, name:String, symbol:String, ?fps:Float = 24, ?loop:Bool = false, ?matX:Float = 0, ?matY:Float = 0):Bool {
			var obj:Dynamic = objectOf(target);
			if (obj == null || !Std.isOfType(obj, flxanimate.PsychFlxAnimate))
				return false;
			var sprite:flxanimate.PsychFlxAnimate = obj;
			sprite.anim.addBySymbol(name, symbol, fps, loop, matX, matY);
			if (sprite.anim.curSymbol == null)
				playOn(sprite, name, true);
			return true;
		});
		script.set('addAnimationBySymbolIndices', function(target:Dynamic, name:String, symbol:String, ?indices:Dynamic, ?fps:Float = 24, ?loop:Bool = false, ?matX:Float = 0, ?matY:Float = 0):Bool {
			var obj:Dynamic = objectOf(target);
			if (obj == null || !Std.isOfType(obj, flxanimate.PsychFlxAnimate))
				return false;
			var sprite:flxanimate.PsychFlxAnimate = obj;
			sprite.anim.addBySymbolIndices(name, symbol, FluxFlixel.indicesOf(indices), fps, loop, matX, matY);
			if (sprite.anim.curSymbol == null)
				playOn(sprite, name, true);
			return true;
		});
		#end
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
		script.set('setTextHeight', function(target:Dynamic, height:Float):Bool {
			var txt:FlxText = textOf(target);
			if (txt == null)
				return false;
			txt.fieldHeight = height;
			return true;
		});
		script.set('setTextAutoSize', function(target:Dynamic, value:Bool):Bool {
			var txt:FlxText = textOf(target);
			if (txt == null)
				return false;
			txt.autoSize = value;
			return true;
		});
		script.set('setTextItalic', function(target:Dynamic, italic:Bool):Bool {
			var txt:FlxText = textOf(target);
			if (txt == null)
				return false;
			txt.italic = italic;
			return true;
		});
		script.set('getTextSize', function(target:Dynamic):Int {
			var txt:FlxText = textOf(target);
			return txt != null ? txt.size : -1;
		});
		script.set('getTextFont', function(target:Dynamic):String {
			var txt:FlxText = textOf(target);
			return txt != null ? txt.font : null;
		});
		script.set('getTextWidth', function(target:Dynamic):Float {
			var txt:FlxText = textOf(target);
			return txt != null ? txt.fieldWidth : 0;
		});
	}

	static function textOf(target:Dynamic):FlxText
	{
		var obj:Dynamic = objectOf(target);
		return Std.isOfType(obj, FlxText) ? obj : null;
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
		script.set('soundFadeCancel', function(?tag:String) {
			var sound:FlxSound = (tag == null || tag.length == 0) ? FlxG.sound.music : soundOf(tag);
			if (sound != null && sound.fadeTween != null)
				sound.fadeTween.cancel();
		});
		script.set('getSoundPitch', function(?tag:String):Float {
			#if FLX_PITCH
			var sound:FlxSound = (tag == null || tag.length == 0) ? FlxG.sound.music : soundOf(tag);
			return sound != null ? sound.pitch : 1;
			#else
			return 1;
			#end
		});
		script.set('setSoundPitch', function(?tag:String, value:Float, ?doPause:Bool = false) {
			#if FLX_PITCH
			var sound:FlxSound = (tag == null || tag.length == 0) ? FlxG.sound.music : soundOf(tag);
			if (sound == null)
				return;
			var wasPlaying:Bool = sound.playing;
			if (doPause)
				sound.pause();
			sound.pitch = value;
			if (doPause && wasPlaying)
				sound.play();
			#else
			warn(script, 'setSoundPitch: el pitch no funciona en esta plataforma');
			#end
		});
		// viejas de Psych (mejor soundFadeIn / soundFadeOut)
		script.set('musicFadeIn', function(duration:Float, ?from:Float = 0, ?to:Float = 1) {
			if (FlxG.sound.music != null)
				FlxG.sound.music.fadeIn(duration, from, to);
		});
		script.set('musicFadeOut', function(duration:Float, ?to:Float = 0) {
			if (FlxG.sound.music != null)
				FlxG.sound.music.fadeOut(duration, to);
		});
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

		// el centro de la cámara del juego (como en Lua: x/y son el centro, no la esquina)
		script.set('setCameraScroll', function(x:Float, y:Float) FlxG.camera.scroll.set(x - FlxG.width / 2, y - FlxG.height / 2));
		script.set('addCameraScroll', function(?x:Float = 0, ?y:Float = 0) FlxG.camera.scroll.add(x, y));
		script.set('getCameraScrollX', function():Float return FlxG.camera.scroll.x + FlxG.width / 2);
		script.set('getCameraScrollY', function():Float return FlxG.camera.scroll.y + FlxG.height / 2);
		// el punto que sigue la cámara en la canción (camFollow)
		script.set('setCameraFollowPoint', function(x:Float, y:Float) {
			var g:PlayState = game();
			if (g != null && g.camFollow != null)
				g.camFollow.setPosition(x, y);
		});
		script.set('addCameraFollowPoint', function(?x:Float = 0, ?y:Float = 0) {
			var g:PlayState = game();
			if (g != null && g.camFollow != null)
			{
				g.camFollow.x += x;
				g.camFollow.y += y;
			}
		});
		script.set('getCameraFollowX', function():Float return (game() != null && game().camFollow != null) ? game().camFollow.x : 0);
		script.set('getCameraFollowY', function():Float return (game() != null && game().camFollow != null) ? game().camFollow.y : 0);
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

		// personajes
		script.set('addCharacterToList', function(name:String, type:String) {
			var g:PlayState = game();
			if (g == null)
				return;
			g.addCharacterToList(name, switch (type.toLowerCase())
			{
				case 'dad' | 'opponent': 1;
				case 'gf' | 'girlfriend': 2;
				default: 0;
			});
		});
		script.set('getCharacterX', function(type:String):Float {
			var group:FlxObject = characterGroupOf(type);
			return group != null ? group.x : 0;
		});
		script.set('getCharacterY', function(type:String):Float {
			var group:FlxObject = characterGroupOf(type);
			return group != null ? group.y : 0;
		});
		script.set('setCharacterX', function(type:String, value:Float) {
			var group:FlxObject = characterGroupOf(type);
			if (group != null)
				group.x = value;
		});
		script.set('setCharacterY', function(type:String, value:Float) {
			var group:FlxObject = characterGroupOf(type);
			if (group != null)
				group.y = value;
		});

		// rating y puntaje
		script.set('setRatingPercent', function(value:Float) {
			var g:PlayState = game();
			if (g == null)
				return;
			g.ratingPercent = value;
			g.setOnScripts('rating', g.ratingPercent);
		});
		script.set('setRatingName', function(value:String) {
			var g:PlayState = game();
			if (g == null)
				return;
			g.ratingName = value;
			g.setOnScripts('ratingName', g.ratingName);
		});
		script.set('setRatingFC', function(value:String) {
			var g:PlayState = game();
			if (g == null)
				return;
			g.ratingFC = value;
			g.setOnScripts('ratingFC', g.ratingFC);
		});
		script.set('updateScoreText', function() {
			var g:PlayState = game();
			if (g != null)
				g.updateScoreText();
		});

		// otra canción, diálogos y videos
		script.set('loadSong', function(?name:String, ?difficultyNum:Int = -1) {
			if (name == null || name.length == 0)
				name = Song.loadedSongName;
			if (difficultyNum == -1)
				difficultyNum = PlayState.storyDifficulty;
			Song.loadFromJson(Highscore.formatSong(name, difficultyNum), name);
			PlayState.storyDifficulty = difficultyNum;
			FlxG.state.persistentUpdate = false;
			LoadingState.loadAndSwitchState(new PlayState());
			if (FlxG.sound.music != null)
			{
				FlxG.sound.music.pause();
				FlxG.sound.music.volume = 0;
			}
			var g:PlayState = game();
			if (g != null && g.vocals != null)
			{
				g.vocals.pause();
				g.vocals.volume = 0;
			}
			FlxG.camera.followLerp = 0;
		});
		script.set('startDialogue', function(dialogueFile:String, ?music:String):Bool {
			var g:PlayState = game();
			if (g == null)
				return false;
			var songPath:String = Paths.formatToSongPath(Song.loadedSongName);
			var path:String = null;
			#if TRANSLATIONS_ALLOWED
			path = Paths.getPath('data/$songPath/${dialogueFile}_${ClientPrefs.data.language}.json', TEXT);
			if (!textExists(path))
			#end
			path = Paths.getPath('data/$songPath/$dialogueFile.json', TEXT);
			if (textExists(path))
			{
				var dialogue:cutscenes.DialogueBoxPsych.DialogueFile = cutscenes.DialogueBoxPsych.parseDialogue(path);
				if (dialogue.dialogue.length > 0)
				{
					g.startDialogue(dialogue, music);
					return true;
				}
				warn(script, 'startDialogue: el diálogo está mal armado ($path)');
			}
			else
			{
				warn(script, 'startDialogue: no existe el diálogo ($path)');
				if (g.endingSong)
					g.endSong();
				else
					g.startCountdown();
			}
			return false;
		});
		script.set('startVideo', function(videoFile:String, ?canSkip:Bool = true, ?forMidSong:Bool = false, ?shouldLoop:Bool = false, ?playOnLoad:Bool = true):Bool {
			var g:PlayState = game();
			if (g == null)
				return false;
			#if VIDEOS_ALLOWED
			if (FileSystem.exists(Paths.video(videoFile)))
			{
				if (g.videoCutscene != null)
				{
					g.remove(g.videoCutscene);
					g.videoCutscene.destroy();
				}
				g.videoCutscene = g.startVideo(videoFile, forMidSong, canSkip, shouldLoop, playOnLoad);
				return true;
			}
			warn(script, 'startVideo: no existe el video $videoFile');
			return false;
			#else
			g.inCutscene = true;
			new FlxTimer().start(0.1, function(_) {
				g.inCutscene = false;
				if (g.endingSong)
					g.endSong();
				else
					g.startCountdown();
			});
			return true;
			#end
		});

		// CustomSubstate (como en Lua)
		script.set('openCustomSubstate', function(name:String, ?pauseGame:Bool = false) {
			if (game() != null)
				CustomSubstate.openCustomSubstate(name, pauseGame);
		});
		script.set('closeCustomSubstate', function():Bool return game() != null && CustomSubstate.closeCustomSubstate());
		script.set('insertToCustomSubstate', function(target:Dynamic, ?pos:Int = -1):Bool {
			var obj:Dynamic = objectOf(target);
			if (CustomSubstate.instance == null || obj == null || !Std.isOfType(obj, FlxBasic))
				return false;
			if (pos < 0)
				CustomSubstate.instance.add(obj);
			else
				CustomSubstate.instance.insert(pos, obj);
			return true;
		});
	}

	static function characterGroupOf(type:String):FlxObject
	{
		var g:PlayState = game();
		if (g == null || type == null)
			return null;
		return switch (type.toLowerCase())
		{
			case 'dad' | 'opponent': g.dadGroup;
			case 'gf' | 'girlfriend': g.gfGroup;
			default: g.boyfriendGroup;
		}
	}

	static function textExists(path:String):Bool
	{
		#if MODS_ALLOWED
		return FileSystem.exists(path);
		#else
		return Assets.exists(path, TEXT);
		#end
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
	// Mouse y mandos
	// ------------------------------------------------------------------

	static function input(script:FluxScript):Void
	{
		#if FLX_MOUSE
		script.set('getMouseX', function(?camera:Dynamic = 'game'):Float return FlxG.mouse.getScreenPosition(cameraOf(camera)).x);
		script.set('getMouseY', function(?camera:Dynamic = 'game'):Float return FlxG.mouse.getScreenPosition(cameraOf(camera)).y);
		script.set('mouseClicked', function(?button:String = 'left'):Bool {
			return switch (button.trim().toLowerCase())
			{
				case 'middle': FlxG.mouse.justPressedMiddle;
				case 'right': FlxG.mouse.justPressedRight;
				default: FlxG.mouse.justPressed;
			}
		});
		script.set('mousePressed', function(?button:String = 'left'):Bool {
			return switch (button.trim().toLowerCase())
			{
				case 'middle': FlxG.mouse.pressedMiddle;
				case 'right': FlxG.mouse.pressedRight;
				default: FlxG.mouse.pressed;
			}
		});
		script.set('mouseReleased', function(?button:String = 'left'):Bool {
			return switch (button.trim().toLowerCase())
			{
				case 'middle': FlxG.mouse.justReleasedMiddle;
				case 'right': FlxG.mouse.justReleasedRight;
				default: FlxG.mouse.justReleased;
			}
		});
		#end

		#if FLX_GAMEPAD
		script.set('anyGamepadJustPressed', function(name:String):Bool return FlxG.gamepads.anyJustPressed(FlxGamepadInputID.fromString(name)));
		script.set('anyGamepadPressed', function(name:String):Bool return FlxG.gamepads.anyPressed(FlxGamepadInputID.fromString(name)));
		script.set('anyGamepadReleased', function(name:String):Bool return FlxG.gamepads.anyJustReleased(FlxGamepadInputID.fromString(name)));
		script.set('gamepadAnalogX', function(id:Int, ?leftStick:Bool = true):Float {
			var pad:FlxGamepad = FlxG.gamepads.getByID(id);
			return pad != null ? pad.getXAxis(leftStick ? FlxGamepadInputID.LEFT_ANALOG_STICK : FlxGamepadInputID.RIGHT_ANALOG_STICK) : 0;
		});
		script.set('gamepadAnalogY', function(id:Int, ?leftStick:Bool = true):Float {
			var pad:FlxGamepad = FlxG.gamepads.getByID(id);
			return pad != null ? pad.getYAxis(leftStick ? FlxGamepadInputID.LEFT_ANALOG_STICK : FlxGamepadInputID.RIGHT_ANALOG_STICK) : 0;
		});
		script.set('gamepadJustPressed', function(id:Int, name:String):Bool {
			var pad:FlxGamepad = FlxG.gamepads.getByID(id);
			return pad != null && Reflect.getProperty(pad.justPressed, name) == true;
		});
		script.set('gamepadPressed', function(id:Int, name:String):Bool {
			var pad:FlxGamepad = FlxG.gamepads.getByID(id);
			return pad != null && Reflect.getProperty(pad.pressed, name) == true;
		});
		script.set('gamepadReleased', function(id:Int, name:String):Bool {
			var pad:FlxGamepad = FlxG.gamepads.getByID(id);
			return pad != null && Reflect.getProperty(pad.justReleased, name) == true;
		});
		#end
	}

	// ------------------------------------------------------------------
	// Datos guardados (initSaveData...)
	// ------------------------------------------------------------------

	static function saves(script:FluxScript):Void
	{
		function saveOf(name:String, where:String):FlxSave
		{
			var save:Dynamic = variables().get('save_$name');
			if (save == null || !Std.isOfType(save, FlxSave))
			{
				warn(script, '$where: falta initSaveData("$name")');
				return null;
			}
			return save;
		}
		script.set('initSaveData', function(name:String, ?folder:String = 'psychenginemods'):FlxSave {
			var existing:Dynamic = variables().get('save_$name');
			if (existing != null && Std.isOfType(existing, FlxSave))
				return existing;
			var save:FlxSave = new FlxSave();
			save.bind(name, CoolUtil.getSavePath() + '/' + folder);
			variables().set('save_$name', save);
			return save;
		});
		script.set('flushSaveData', function(name:String):Bool {
			var save:FlxSave = saveOf(name, 'flushSaveData');
			return save != null && save.flush();
		});
		script.set('getDataFromSave', function(name:String, field:String, ?defaultValue:Dynamic):Dynamic {
			var save:FlxSave = saveOf(name, 'getDataFromSave');
			if (save == null || !Reflect.hasField(save.data, field))
				return defaultValue;
			return Reflect.field(save.data, field);
		});
		script.set('setDataFromSave', function(name:String, field:String, value:Dynamic):Bool {
			var save:FlxSave = saveOf(name, 'setDataFromSave');
			if (save == null)
				return false;
			Reflect.setField(save.data, field, value);
			return true;
		});
		script.set('eraseSaveData', function(name:String):Bool {
			var save:FlxSave = saveOf(name, 'eraseSaveData');
			return save != null && save.erase();
		});
	}

	// ------------------------------------------------------------------
	// Archivos y textos
	// ------------------------------------------------------------------

	static function files(script:FluxScript):Void
	{
		script.set('checkFileExists', function(filename:String, ?absolute:Bool = false):Bool {
			#if MODS_ALLOWED
			return FileSystem.exists(absolute ? filename : Paths.getPath(filename, TEXT));
			#else
			return Assets.exists(absolute ? filename : Paths.getPath(filename, TEXT), TEXT);
			#end
		});
		script.set('getTextFromFile', function(path:String, ?ignoreModFolders:Bool = false):String return Paths.getTextFromFile(path, ignoreModFolders));
		#if sys
		script.set('saveFile', function(path:String, content:String, ?absolute:Bool = false):Bool {
			try
			{
				#if MODS_ALLOWED
				File.saveContent(absolute ? path : Paths.mods(path), content);
				#else
				File.saveContent(path, content);
				#end
				return true;
			}
			catch (e:Dynamic)
			{
				warn(script, 'saveFile: no se pudo guardar $path: $e');
			}
			return false;
		});
		script.set('deleteFile', function(path:String, ?ignoreModFolders:Bool = false, ?absolute:Bool = false):Bool {
			try
			{
				var file:String = absolute ? path : Paths.getPath(path, TEXT, null, !ignoreModFolders);
				if (FileSystem.exists(file))
				{
					FileSystem.deleteFile(file);
					return true;
				}
			}
			catch (e:Dynamic)
			{
				warn(script, 'deleteFile: no se pudo borrar $path: $e');
			}
			return false;
		});
		script.set('directoryFileList', function(folder:String):Array<String> {
			var list:Array<String> = [];
			if (FileSystem.exists(folder) && FileSystem.isDirectory(folder))
				for (entry in FileSystem.readDirectory(folder))
					if (!list.contains(entry))
						list.push(entry);
			return list;
		});
		#end

		script.set('stringStartsWith', function(text:String, start:String):Bool return text != null && text.startsWith(start));
		script.set('stringEndsWith', function(text:String, end:String):Bool return text != null && text.endsWith(end));
		script.set('stringSplit', function(text:String, separator:String):Array<String> return text != null ? text.split(separator) : []);
		script.set('stringTrim', function(text:String):String return text != null ? text.trim() : null);
	}

	// ------------------------------------------------------------------
	// Shaders
	// ------------------------------------------------------------------

	#if (!flash && sys)
	static var shaderCache:Map<String, Array<String>> = new Map<String, Array<String>>();
	#end

	/** [frag, vert] del shader (de shaders/ en los mods o en assets), o null si no existe. */
	public static function shaderCode(name:String):Array<String>
	{
		#if (!flash && sys)
		var g:PlayState = game();
		if (g != null)
		{
			if (!g.runtimeShaders.exists(name) && !g.initLuaShader(name))
				return null;
			return g.runtimeShaders.get(name);
		}
		if (shaderCache.exists(name))
			return shaderCache.get(name);
		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'shaders/'))
		{
			var frag:String = folder + name + '.frag';
			var vert:String = folder + name + '.vert';
			var code:Array<String> = [
				FileSystem.exists(frag) ? File.getContent(frag) : null,
				FileSystem.exists(vert) ? File.getContent(vert) : null
			];
			if (code[0] != null || code[1] != null)
			{
				shaderCache.set(name, code);
				return code;
			}
		}
		#end
		return null;
	}

	static function shaderApi(script:FluxScript):Void
	{
		#if (!flash && sys)
		function shaderOf(target:Dynamic, where:String):FlxRuntimeShader
		{
			var sprite:FlxSprite = objectOf(target);
			if (sprite == null)
			{
				warn(script, '$where: no existe "$target"');
				return null;
			}
			if (sprite.shader == null || !Std.isOfType(sprite.shader, FlxRuntimeShader))
			{
				warn(script, '$where: "$target" no tiene un shader de setSpriteShader');
				return null;
			}
			return cast sprite.shader;
		}

		script.set('initLuaShader', function(name:String, ?glslVersion:Int = 120):Bool {
			return ClientPrefs.data.shaders && shaderCode(name) != null;
		});
		script.set('setSpriteShader', function(target:Dynamic, shader:String):Bool {
			if (!ClientPrefs.data.shaders)
				return false;
			var code:Array<String> = shaderCode(shader);
			if (code == null)
			{
				warn(script, 'setSpriteShader: no existe el shader $shader');
				return false;
			}
			var sprite:FlxSprite = objectOf(target);
			if (sprite == null)
				return false;
			sprite.shader = new shaders.ErrorHandledShader.ErrorHandledRuntimeShader(shader, code[0], code[1]);
			return true;
		});
		script.set('getShaderBool', function(target:Dynamic, prop:String):Null<Bool> {
			var shader:FlxRuntimeShader = shaderOf(target, 'getShaderBool');
			return shader != null ? shader.getBool(prop) : null;
		});
		script.set('getShaderBoolArray', function(target:Dynamic, prop:String):Array<Bool> {
			var shader:FlxRuntimeShader = shaderOf(target, 'getShaderBoolArray');
			return shader != null ? shader.getBoolArray(prop) : null;
		});
		script.set('getShaderInt', function(target:Dynamic, prop:String):Null<Int> {
			var shader:FlxRuntimeShader = shaderOf(target, 'getShaderInt');
			return shader != null ? shader.getInt(prop) : null;
		});
		script.set('getShaderIntArray', function(target:Dynamic, prop:String):Array<Int> {
			var shader:FlxRuntimeShader = shaderOf(target, 'getShaderIntArray');
			return shader != null ? shader.getIntArray(prop) : null;
		});
		script.set('getShaderFloat', function(target:Dynamic, prop:String):Null<Float> {
			var shader:FlxRuntimeShader = shaderOf(target, 'getShaderFloat');
			return shader != null ? shader.getFloat(prop) : null;
		});
		script.set('getShaderFloatArray', function(target:Dynamic, prop:String):Array<Float> {
			var shader:FlxRuntimeShader = shaderOf(target, 'getShaderFloatArray');
			return shader != null ? shader.getFloatArray(prop) : null;
		});
		script.set('setShaderBool', function(target:Dynamic, prop:String, value:Bool):Bool {
			var shader:FlxRuntimeShader = shaderOf(target, 'setShaderBool');
			if (shader == null)
				return false;
			shader.setBool(prop, value);
			return true;
		});
		script.set('setShaderBoolArray', function(target:Dynamic, prop:String, values:Dynamic):Bool {
			var shader:FlxRuntimeShader = shaderOf(target, 'setShaderBoolArray');
			if (shader == null)
				return false;
			shader.setBoolArray(prop, values);
			return true;
		});
		script.set('setShaderInt', function(target:Dynamic, prop:String, value:Int):Bool {
			var shader:FlxRuntimeShader = shaderOf(target, 'setShaderInt');
			if (shader == null)
				return false;
			shader.setInt(prop, value);
			return true;
		});
		script.set('setShaderIntArray', function(target:Dynamic, prop:String, values:Dynamic):Bool {
			var shader:FlxRuntimeShader = shaderOf(target, 'setShaderIntArray');
			if (shader == null)
				return false;
			shader.setIntArray(prop, values);
			return true;
		});
		script.set('setShaderFloat', function(target:Dynamic, prop:String, value:Float):Bool {
			var shader:FlxRuntimeShader = shaderOf(target, 'setShaderFloat');
			if (shader == null)
				return false;
			shader.setFloat(prop, value);
			return true;
		});
		script.set('setShaderFloatArray', function(target:Dynamic, prop:String, values:Dynamic):Bool {
			var shader:FlxRuntimeShader = shaderOf(target, 'setShaderFloatArray');
			if (shader == null)
				return false;
			shader.setFloatArray(prop, values);
			return true;
		});
		script.set('setShaderSampler2D', function(target:Dynamic, prop:String, bitmapPath:String):Bool {
			var shader:FlxRuntimeShader = shaderOf(target, 'setShaderSampler2D');
			if (shader == null)
				return false;
			var graphic = Paths.image(bitmapPath);
			if (graphic == null || graphic.bitmap == null)
				return false;
			shader.setSampler2D(prop, graphic.bitmap);
			return true;
		});
		#else
		for (name in ['initLuaShader', 'setSpriteShader'])
			script.set(name, function(?a:Dynamic, ?b:Dynamic):Bool {
				warn(script, '$name: los shaders no funcionan en esta plataforma');
				return false;
			});
		#end
		script.set('removeSpriteShader', function(target:Dynamic):Bool {
			var sprite:FlxSprite = objectOf(target);
			if (sprite == null)
				return false;
			sprite.shader = null;
			return true;
		});
	}

	// ------------------------------------------------------------------
	// Otros scripts (Lua y HScript)
	// ------------------------------------------------------------------

	/** Como findScript de FunkinLua: "scripts/algo" -> la ruta del .lua (o .hx), o null. */
	static function findPsychScript(file:String, ext:String):String
	{
		if (file == null)
			return null;
		if (!file.endsWith(ext))
			file += ext;
		var path:String = Paths.getPath(file, TEXT);
		if (textExists(path))
			return path;
		if (textExists(file))
			return file;
		return null;
	}

	static function scripts(script:FluxScript):Void
	{
		function exclusionsOf(list:Array<String>, ignoreSelf:Bool):Array<String>
		{
			if (list == null)
				list = [];
			if (ignoreSelf && !list.contains(script.name))
				list.push(script.name);
			return list;
		}
		script.set('callOnScripts', function(name:String, ?args:Array<Dynamic>, ?ignoreStops:Bool = false, ?ignoreSelf:Bool = true, ?excludeScripts:Array<String>, ?excludeValues:Array<Dynamic>):Dynamic {
			var g:PlayState = game();
			return g != null ? g.callOnScripts(name, args, ignoreStops, exclusionsOf(excludeScripts, ignoreSelf), excludeValues) : null;
		});
		script.set('callOnLuas', function(name:String, ?args:Array<Dynamic>, ?ignoreStops:Bool = false, ?ignoreSelf:Bool = true, ?excludeScripts:Array<String>, ?excludeValues:Array<Dynamic>):Dynamic {
			var g:PlayState = game();
			return g != null ? g.callOnLuas(name, args, ignoreStops, exclusionsOf(excludeScripts, ignoreSelf), excludeValues) : null;
		});
		script.set('callOnHScript', function(name:String, ?args:Array<Dynamic>, ?ignoreStops:Bool = false, ?ignoreSelf:Bool = true, ?excludeScripts:Array<String>, ?excludeValues:Array<Dynamic>):Dynamic {
			var g:PlayState = game();
			return g != null ? g.callOnHScript(name, args, ignoreStops, exclusionsOf(excludeScripts, ignoreSelf), excludeValues) : null;
		});
		script.set('setOnScripts', function(name:String, value:Dynamic, ?ignoreSelf:Bool = false, ?exclusions:Array<String>) {
			var g:PlayState = game();
			if (g != null)
				g.setOnScripts(name, value, exclusionsOf(exclusions, ignoreSelf));
		});
		script.set('setOnLuas', function(name:String, value:Dynamic, ?ignoreSelf:Bool = false, ?exclusions:Array<String>) {
			var g:PlayState = game();
			if (g != null)
				g.setOnLuas(name, value, exclusionsOf(exclusions, ignoreSelf));
		});
		script.set('setOnHScript', function(name:String, value:Dynamic, ?ignoreSelf:Bool = false, ?exclusions:Array<String>) {
			var g:PlayState = game();
			if (g != null)
				g.setOnHScript(name, value, exclusionsOf(exclusions, ignoreSelf));
		});

		#if LUA_ALLOWED
		script.set('addLuaScript', function(file:String, ?ignoreAlreadyRunning:Bool = false):Bool {
			var g:PlayState = game();
			var path:String = findPsychScript(file, '.lua');
			if (g == null || path == null)
			{
				warn(script, 'addLuaScript: no existe "$file"');
				return false;
			}
			if (!ignoreAlreadyRunning)
				for (lua in g.luaArray)
					if (lua.scriptName == path)
					{
						script.warn('addLuaScript: "$path" ya está corriendo');
						return false;
					}
			new psychlua.FunkinLua(path);
			return true;
		});
		script.set('removeLuaScript', function(file:String):Bool {
			var g:PlayState = game();
			var path:String = findPsychScript(file, '.lua');
			var found:Bool = false;
			if (g != null && path != null)
				for (lua in g.luaArray.copy())
					if (lua.scriptName == path)
					{
						lua.stop();
						found = true;
					}
			if (!found)
				warn(script, 'removeLuaScript: "$file" no está corriendo');
			return found;
		});
		script.set('callScript', function(file:String, func:String, ?args:Array<Dynamic>):Dynamic {
			var g:PlayState = game();
			var path:String = findPsychScript(file, '.lua');
			if (g != null && path != null)
				for (lua in g.luaArray)
					if (lua.scriptName == path)
						return lua.call(func, args != null ? args : []);
			return null;
		});
		script.set('getRunningScripts', function():Array<String> {
			var g:PlayState = game();
			return g != null ? [for (lua in g.luaArray) lua.scriptName] : [];
		});
		// una función de este script que pueden llamar todos los .lua (también los que se abran después)
		script.set('createGlobalCallback', function(name:String, fn:Dynamic) {
			var g:PlayState = game();
			if (g != null)
				for (lua in g.luaArray)
					if (lua != null && lua.lua != null && !lua.closed)
						llua.Lua.Lua_helper.add_callback(lua.lua, name, fn);
			psychlua.FunkinLua.customFunctions.set(name, fn);
		});
		#end
		#if HSCRIPT_ALLOWED
		script.set('addHScript', function(file:String, ?ignoreAlreadyRunning:Bool = false):Bool {
			var g:PlayState = game();
			var path:String = findPsychScript(file, '.hx');
			if (g == null || path == null)
			{
				warn(script, 'addHScript: no existe "$file"');
				return false;
			}
			if (!ignoreAlreadyRunning)
				for (other in g.hscriptArray)
					if (other.origin == path)
					{
						script.warn('addHScript: "$path" ya está corriendo');
						return false;
					}
			g.initHScript(path);
			return true;
		});
		script.set('removeHScript', function(file:String):Bool {
			var g:PlayState = game();
			var path:String = findPsychScript(file, '.hx');
			var found:Bool = false;
			if (g != null && path != null)
				for (other in g.hscriptArray.copy())
					if (other.origin == path)
					{
						other.destroy();
						found = true;
					}
			if (!found)
				warn(script, 'removeHScript: "$file" no está corriendo');
			return found;
		});
		#end
		script.set('isRunning', function(file:String):Bool {
			var g:PlayState = game();
			if (g == null)
				return false;
			#if LUA_ALLOWED
			var luaPath:String = findPsychScript(file, '.lua');
			if (luaPath != null)
				for (lua in g.luaArray)
					if (lua.scriptName == luaPath)
						return true;
			#end
			#if HSCRIPT_ALLOWED
			var hxPath:String = findPsychScript(file, '.hx');
			if (hxPath != null)
				for (other in g.hscriptArray)
					if (other.origin == hxPath)
						return true;
			#end
			return false;
		});

		// lo que en Lua es para HScript: aquí el código ya es Haxe
		script.set('runHaxeCode', function(code:String, ?varsToBring:Dynamic, ?funcToRun:String, ?funcArgs:Array<Dynamic>):Dynamic {
			if (varsToBring != null)
				for (key in Reflect.fields(varsToBring))
					script.set(key, Reflect.field(varsToBring, key));
			if (!script.run(code))
				return null;
			return funcToRun != null ? script.call(funcToRun, funcArgs) : script.returnValue;
		});
		script.set('runHaxeFunction', function(func:String, ?args:Array<Dynamic>):Dynamic return script.call(func, args));
		script.set('addHaxeLibrary', function(libName:String, ?libPackage:String = ''):Dynamic {
			var cls:Dynamic = Type.resolveClass((libPackage != null && libPackage.length > 0) ? '$libPackage.$libName' : libName);
			if (cls == null)
				cls = FluxClasses.find(libName);
			script.set(libName, cls);
			return cls;
		});
	}

	// ------------------------------------------------------------------
	// Instancias (createInstance, addInstance, instanceArg)
	// ------------------------------------------------------------------

	static function reflection(script:FluxScript):Void
	{
		script.set('createInstance', function(tag:String, className:String, ?args:Array<Dynamic>):Dynamic {
			tag = tag.trim().replace('.', '');
			if (variables().get(tag) != null)
			{
				warn(script, 'createInstance: "$tag" ya se está usando');
				return null;
			}
			var cls:Dynamic = Type.resolveClass(className);
			if (cls == null)
				cls = FluxClasses.find(className);
			if (cls == null)
			{
				warn(script, 'createInstance: no existe la clase $className');
				return null;
			}
			var obj:Dynamic = Type.createInstance(cls, args != null ? parseInstances(args) : []);
			if (obj != null)
				variables().set(tag, obj);
			return obj;
		});
		script.set('addInstance', function(target:Dynamic, ?inFront:Bool = false):Bool {
			var obj:Dynamic = objectOf(target);
			if (obj == null || !Std.isOfType(obj, FlxBasic))
			{
				warn(script, 'addInstance: no existe "$target"');
				return false;
			}
			addToGame(obj, inFront);
			return true;
		});
		script.set('instanceArg', function(name:String, ?className:String):String {
			var text:String = '$INSTANCE_TAG::$name';
			if (className != null)
				text += '::$className';
			return text;
		});
	}

	// ------------------------------------------------------------------
	// El preset de los .hxs de Psych (solo si el engine no puso el suyo)
	// ------------------------------------------------------------------

	static function hxs(script:FluxScript):Void
	{
		script.setDefault('makeSprite', function(?x:Float = 0, ?y:Float = 0, ?image:String):FlxSprite {
			var sprite:FlxSprite = new FlxSprite(x, y);
			if (image != null && image.length > 0)
				sprite.loadGraphic(Paths.image(image));
			sprite.antialiasing = ClientPrefs.data.antialiasing;
			return sprite;
		});
		script.setDefault('makeAnimatedSprite', function(?x:Float = 0, ?y:Float = 0, image:String):FlxSprite {
			var sprite:FlxSprite = new FlxSprite(x, y);
			if (image != null && image.length > 0)
				sprite.frames = Paths.getAtlas(image);
			sprite.antialiasing = ClientPrefs.data.antialiasing;
			return sprite;
		});
		script.setDefault('makeText', function(?x:Float = 0, ?y:Float = 0, ?width:Float = 0, ?text:String = '', ?size:Int = 24):FlxText {
			var txt:FlxText = new FlxText(x, y, width, text, size);
			txt.setFormat(Paths.font('vcr.ttf'), size, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			txt.borderSize = 1.25;
			return txt;
		});
		script.setDefault('switchState', function(target:Dynamic):Bool {
			var state:FlxState = stateOf(target);
			if (state == null)
			{
				warn(script, 'switchState: no existe el estado "$target"');
				return false;
			}
			MusicBeatState.switchState(state);
			return true;
		});
		script.setDefault('resetState', function() MusicBeatState.resetState());
	}

	/** Un estado por nombre ("MainMenuState", "options.OptionsState"), su clase, o el estado mismo. */
	public static function stateOf(target:Dynamic):FlxState
	{
		if (target == null)
			return null;
		if (Std.isOfType(target, FlxState))
			return target;
		var cls:Dynamic = Std.isOfType(target, Class) ? target : null;
		if (cls == null)
		{
			var name:String = Std.string(target);
			cls = Type.resolveClass(name);
			if (cls == null)
				for (pack in ['states.', 'options.', 'states.editors.'])
				{
					cls = Type.resolveClass(pack + name);
					if (cls != null)
						break;
				}
		}
		if (cls == null)
			return null;
		var state:Dynamic = Type.createInstance(cls, []);
		return Std.isOfType(state, FlxState) ? state : null;
	}

	// ------------------------------------------------------------------
	// Lo viejo de Lua (por si un script de antes las usa)
	// ------------------------------------------------------------------

	static function deprecated(script:FluxScript):Void
	{
		script.set('objectPlayAnimation', function(target:Dynamic, name:String, ?forced:Bool = false, ?startFrame:Int = 0):Bool {
			var sprite:Dynamic = objectOf(target);
			if (sprite == null || !Std.isOfType(sprite, FlxSprite))
				return false;
			(sprite : FlxSprite).animation.play(name, forced, false, startFrame);
			return true;
		});
		script.set('luaSpriteMakeGraphic', function(target:Dynamic, width:Int, height:Int, color:Dynamic) {
			var sprite:Dynamic = objectOf(target);
			if (sprite != null && Std.isOfType(sprite, FlxSprite))
				(sprite : FlxSprite).makeGraphic(width, height, colorOf(color));
		});
		script.set('luaSpriteAddAnimationByPrefix', function(target:Dynamic, name:String, prefix:String, ?fps:Float = 24, ?loop:Bool = true) {
			var sprite:Dynamic = objectOf(target);
			if (sprite == null || !Std.isOfType(sprite, FlxSprite))
				return;
			(sprite : FlxSprite).animation.addByPrefix(name, prefix, fps, loop);
			if ((sprite : FlxSprite).animation.curAnim == null)
				(sprite : FlxSprite).animation.play(name, true);
		});
		script.set('luaSpriteAddAnimationByIndices', function(target:Dynamic, name:String, prefix:String, indices:Dynamic, ?fps:Float = 24) {
			addByIndices(target, name, prefix, indices, fps, false);
		});
		script.set('luaSpritePlayAnimation', function(target:Dynamic, name:String, ?forced:Bool = false) {
			var sprite:Dynamic = objectOf(target);
			if (sprite != null && Std.isOfType(sprite, FlxSprite))
				(sprite : FlxSprite).animation.play(name, forced);
		});
		script.set('setLuaSpriteCamera', function(target:Dynamic, ?camera:Dynamic = ''):Bool {
			var obj:Dynamic = objectOf(target);
			if (obj == null || !Std.isOfType(obj, FlxBasic))
				return false;
			(obj : FlxBasic).cameras = [cameraOf(camera)];
			return true;
		});
		script.set('setLuaSpriteScrollFactor', function(target:Dynamic, x:Float, y:Float):Bool {
			var obj:Dynamic = objectOf(target);
			if (obj == null || !Std.isOfType(obj, FlxObject))
				return false;
			(obj : FlxObject).scrollFactor.set(x, y);
			return true;
		});
		script.set('scaleLuaSprite', function(target:Dynamic, x:Float, y:Float):Bool {
			var sprite:Dynamic = objectOf(target);
			if (sprite == null || !Std.isOfType(sprite, FlxSprite))
				return false;
			(sprite : FlxSprite).scale.set(x, y);
			(sprite : FlxSprite).updateHitbox();
			return true;
		});
		script.set('getPropertyLuaSprite', function(target:Dynamic, field:String):Dynamic {
			var obj:Dynamic = objectOf(target);
			if (obj == null)
				return null;
			var split:Array<String> = field.split('.');
			for (i in 0...split.length - 1)
				obj = Reflect.getProperty(obj, split[i]);
			return obj != null ? Reflect.getProperty(obj, split[split.length - 1]) : null;
		});
		script.set('setPropertyLuaSprite', function(target:Dynamic, field:String, value:Dynamic):Bool {
			var obj:Dynamic = objectOf(target);
			if (obj == null)
				return false;
			var split:Array<String> = field.split('.');
			for (i in 0...split.length - 1)
				obj = Reflect.getProperty(obj, split[i]);
			if (obj == null)
				return false;
			Reflect.setProperty(obj, split[split.length - 1], value);
			return true;
		});
	}

	// ------------------------------------------------------------------
	// Otros
	// ------------------------------------------------------------------

	static function other(script:FluxScript):Void
	{
		script.set('getColorFromHex', function(color:String):Int return CoolUtil.colorFromString(color));
		script.set('getColorFromName', function(color:String):Int {
			var parsed:Null<FlxColor> = FlxColor.fromString(color);
			return parsed != null ? parsed : FlxColor.WHITE;
		});
		script.set('getColorFromString', function(color:String):Int {
			var parsed:Null<FlxColor> = FlxColor.fromString(color);
			return parsed != null ? parsed : FlxColor.WHITE;
		});
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
