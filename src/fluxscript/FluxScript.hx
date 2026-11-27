package fluxscript;

import crowplexus.hscript.Expr;
import crowplexus.hscript.Printer;

/**
 * FluxScript: un addon de HScript (hscript-iris) para FNF.
 *
 * Se escribe igual que un .hx de Psych Engine y además tiene:
 *  - sin `import`: cualquier clase del juego se usa directo (FluxClasses);
 *  - los campos del estado se leen y se cambian directo (`health = 2`);
 *  - textos con variables: 'Hola $nombre, tienes ${score} puntos';
 *  - `on('beatHit', función)`: varias funciones para el mismo evento;
 *  - `shared`: datos que comparten todos los FluxScript y duran toda la partida;
 *  - `importCode(código)`, `wait`/`every` (con FluxFlixel) y la API de Lua de
 *    Psych (con fluxscript.psych.FluxPsych).
 *
 * Uso básico (en un engine):
 *   var script = new FluxScript(codigo, 'mods/x/scripts/hola.flux', FlxG.state);
 *   FluxPsych.apply(script);         // Psych Engine 1.0.4 (ya incluye FluxFlixel)
 *   // o FluxFlixel.apply(script);   // otros engines: timers, colores, clases de Flixel
 *   if (script.execute()) script.call('onCreate');
 */
class FluxScript
{
	public static inline var VERSION:String = '1.0.0';

	/** Datos que comparten todos los FluxScript y duran toda la partida (`shared.monedas = 5`). */
	public static var shared(default, null):Dynamic = {};

	/** Lo que se puede usar en `#if NOMBRE` (el engine agrega los suyos con FluxScript.defines.set). */
	public static var defines(default, null):Map<String, Dynamic> = makeDefines();

	static function makeDefines():Map<String, Dynamic>
	{
		var map:Map<String, Dynamic> = new Map<String, Dynamic>();
		map.set('FLUXSCRIPT', true);
		#if desktop map.set('desktop', true); #end
		#if mobile map.set('mobile', true); #end
		#if windows map.set('windows', true); #end
		#if linux map.set('linux', true); #end
		#if mac map.set('mac', true); #end
		#if android map.set('android', true); #end
		#if debug map.set('debug', true); #end
		return map;
	}

	/** Qué hacer con los errores de todos los scripts (por defecto, trace). Cada script puede tener el suyo. */
	public static dynamic function defaultErrorHandler(script:FluxScript, message:String):Void
		trace('[FluxScript] ${script.name}: $message');

	/** Lo mismo para los avisos (cosas que no cortan el script, como un `import` que no existe). */
	public static dynamic function defaultWarningHandler(script:FluxScript, message:String):Void
		trace('[FluxScript] ${script.name}: $message');

	/** Nombre del script (la ruta del archivo) para los errores. */
	public var name(default, null):String;

	public var interp(default, null):FluxInterp;
	public var parser(default, null):FluxParser;

	/** false después de destroy(). */
	public var active(default, null):Bool = true;

	/** Lo que devolvió el cuerpo del script al ejecutarse. */
	public var returnValue:Dynamic = null;

	/** Errores de este script (si es null se usa defaultErrorHandler). */
	public var onError:String->Void = null;

	/** Avisos de este script (si es null se usa defaultWarningHandler). */
	public var onWarning:String->Void = null;

	/** Se llama cuando el script se cierra solo con close(). */
	public var onClose:Void->Void = null;

	/** Carpeta del mod del script (la pone el engine; la usa getModSetting). */
	public var modFolder:String = null;

	/** Funciones agregadas con on('evento', función). */
	var listeners:Map<String, Array<Dynamic>> = new Map<String, Array<Dynamic>>();

	var code:String;

	/**
	 * @param code   el código
	 * @param name   nombre para los errores (normalmente la ruta del archivo)
	 * @param parent el objeto cuyos campos se usan directo (el estado del juego)
	 */
	public function new(code:String, ?name:String, ?parent:Dynamic)
	{
		this.code = code;
		this.name = name != null ? name : 'FluxScript';

		parser = makeParser();

		interp = new FluxInterp();
		interp.parent = parent;
		interp.warningHandler = function(message:String) warn(message);
		preset();
	}

	static function makeParser():FluxParser
	{
		var parser:FluxParser = new FluxParser();
		parser.allowJSON = true;
		parser.allowTypes = true;
		parser.allowMetadata = true;
		for (key => value in defines)
			parser.preprocesorValues.set(key, value);
		return parser;
	}

	/**
	 * Revisa si el código se puede leer, sin ejecutarlo.
	 * Devuelve null si está bien, o el error (con la línea).
	 */
	public static function checkSyntax(code:String, ?name:String):String
	{
		try
		{
			makeParser().parseString(FluxSyntax.process(code) + '\n', name != null ? name : 'FluxScript');
			return null;
		}
		catch (e:Dynamic)
		{
			return errorText(e);
		}
	}

	#if sys
	/** Un FluxScript con el código de un archivo (null si el archivo no existe). */
	public static function fromFile(path:String, ?parent:Dynamic):FluxScript
	{
		if (path == null || !sys.FileSystem.exists(path))
			return null;
		return new FluxScript(sys.io.File.getContent(path), path, parent);
	}
	#end

	/** Lo que todo FluxScript tiene, en cualquier engine. */
	function preset():Void
	{
		set('Std', Std);
		set('Math', Math);
		set('StringTools', StringTools);
		set('Type', Type);
		set('Reflect', Reflect);
		set('Lambda', Lambda);
		set('Date', Date);
		set('DateTools', DateTools);
		set('EReg', EReg);
		set('Json', haxe.Json);
		set('StringMap', haxe.ds.StringMap);
		set('IntMap', haxe.ds.IntMap);
		set('ObjectMap', haxe.ds.ObjectMap);

		set('this', this);
		set('shared', shared);
		set('scriptName', name);
		set('FLUXSCRIPT_VERSION', VERSION);

		set('trace', Reflect.makeVarArgs(function(args:Array<Dynamic>) {
			var pos = interp.posInfos();
			var text:String = [for (arg in args) Std.string(arg)].join(', ');
			haxe.Log.trace(text, {fileName: name, lineNumber: pos.lineNumber, className: '', methodName: ''});
			return null;
		}));

		// varias funciones para el mismo evento: on('beatHit', function(beat) {...})
		set('on', function(event:String, fn:Dynamic):Dynamic {
			var key:String = eventKey(event);
			var list:Array<Dynamic> = listeners.get(key);
			if (list == null)
			{
				list = [];
				listeners.set(key, list);
			}
			list.push(fn);
			return fn;
		});
		set('off', function(event:String, ?fn:Dynamic):Void {
			var key:String = eventKey(event);
			if (fn == null)
				listeners.remove(key);
			else if (listeners.exists(key))
				listeners.get(key).remove(fn);
		});

		// otro FluxScript dentro de este (comparten variables y funciones)
		set('importCode', function(code:String):Bool return run(code));
	}

	/** "beatHit" y "onBeatHit" son el mismo evento. */
	static function eventKey(event:String):String
	{
		if (event == null)
			return '';
		if (event.length > 2 && StringTools.startsWith(event, 'on') && event.charAt(2) == event.charAt(2).toUpperCase())
			return event;
		return 'on' + event.charAt(0).toUpperCase() + event.substr(1);
	}

	/** Ejecuta el código del script. Devuelve false si hubo un error. */
	public function execute():Bool
		return run(code);

	/** Ejecuta más código en el mismo intérprete (las variables y funciones se mantienen). */
	public function run(source:String):Bool
	{
		if (!active || source == null)
			return false;
		try
		{
			// el salto de línea final evita que el parser lea de más si el archivo termina en "#end"
			var expr:Expr = parser.parseString(FluxSyntax.process(source) + '\n', name);
			returnValue = interp.execute(expr);
			return true;
		}
		catch (e:Dynamic)
		{
			error('Error al cargar: ' + errorText(e));
			return false;
		}
	}

	/** Si existe la función (o hay funciones agregadas con on()). */
	public function exists(name:String):Bool
	{
		if (!active || name == null)
			return false;
		if (functionOf(name) != null)
			return true;
		var list:Array<Dynamic> = listeners.get(eventKey(name));
		return list != null && list.length > 0;
	}

	/**
	 * Llama a la función del script y a las agregadas con on(). Devuelve lo que
	 * devolvió la función del script (o la última de on() que devolvió algo).
	 */
	public function call(name:String, ?args:Array<Dynamic>):Dynamic
	{
		if (!active || name == null)
			return null;
		if (args == null)
			args = [];
		var result:Dynamic = null;
		var list:Array<Dynamic> = listeners.get(eventKey(name));
		if (list != null)
			for (fn in list.copy())
			{
				var value:Dynamic = callFunction(name, fn, args);
				if (value != null)
					result = value;
			}
		var fn:Dynamic = functionOf(name);
		if (fn != null)
		{
			var value:Dynamic = callFunction(name, fn, args);
			if (value != null)
				result = value;
		}
		return result;
	}

	function callFunction(name:String, fn:Dynamic, args:Array<Dynamic>):Dynamic
	{
		try
		{
			return Reflect.callMethod(null, fn, args);
		}
		catch (e:Dynamic)
		{
			error('Error en $name: ' + errorText(e));
		}
		return null;
	}

	function functionOf(name:String):Dynamic
	{
		if (interp == null || !interp.variables.exists(name))
			return null;
		var fn:Dynamic = interp.variables.get(name);
		return Reflect.isFunction(fn) ? fn : null;
	}

	public function set(name:String, value:Dynamic):Void
	{
		if (interp != null)
			interp.variables.set(name, value);
	}

	public function get(name:String):Dynamic
		return (interp != null && interp.variables.exists(name)) ? interp.variables.get(name) : null;

	/** El objeto cuyos campos el script usa directo (el estado del juego, o null). */
	public var parent(get, set):Dynamic;

	function get_parent():Dynamic
		return interp != null ? interp.parent : null;

	function set_parent(value:Dynamic):Dynamic
	{
		if (interp != null)
			interp.parent = value;
		return value;
	}

	/** El script deja de recibir llamadas (close() desde el script). */
	public function close():Void
	{
		if (!active)
			return;
		active = false;
		if (onClose != null)
			onClose();
	}

	public function destroy():Void
	{
		active = false;
		listeners = new Map<String, Array<Dynamic>>();
		if (interp != null)
			interp.parent = null;
		interp = null;
		parser = null;
		code = null;
	}

	public function error(message:String):Void
	{
		if (onError != null)
			onError(message);
		else
			defaultErrorHandler(this, message);
	}

	public function warn(message:String):Void
	{
		if (onWarning != null)
			onWarning(message);
		else
			defaultWarningHandler(this, message);
	}

	public static function errorText(e:Dynamic):String
	{
		if (Std.isOfType(e, Error))
			return Printer.errorToString(cast e, true);
		return Std.string(e);
	}

	public function toString():String
		return 'FluxScript($name)';
}
