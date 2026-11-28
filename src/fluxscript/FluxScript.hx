package fluxscript;

import crowplexus.hscript.Expr;
import crowplexus.hscript.Printer;
import fluxscript.FluxTasks.FluxTask;

/**
 * FluxScript: un addon de HScript (hscript-iris) para FNF.
 *
 * Se escribe igual que un .hx de Psych Engine y además tiene:
 *  - sin `import`: cualquier clase del juego se usa directo (FluxClasses);
 *  - los campos del estado se leen y se cambian directo (`health = 2`);
 *  - textos con variables: 'Hola $nombre, tienes ${score} puntos';
 *  - `on('beatHit', función)`: varias funciones para el mismo evento;
 *  - `shared`: datos que comparten todos los FluxScript y duran toda la partida;
 *  - lo de Luau: `task.wait(segundos)` dentro de las funciones, `task.spawn/delay/
 *    defer/cancel`, `require`, `print`, `warn`, `typeof`, `pcall`, `math`, `os`...
 *    (FluxLib y FluxAsync);
 *  - `importCode(código)`, `importScript`, `wait`/`every` y el preset de los .hxs
 *    (con FluxFlixel), y la API de Lua de Psych (con fluxscript.psych.FluxPsych).
 *
 * Uso básico (en un engine):
 *   var script = new FluxScript(codigo, 'mods/x/scripts/hola.flux', FlxG.state);
 *   FluxPsych.apply(script);         // Psych Engine 1.0.4 (ya incluye FluxFlixel)
 *   // o FluxFlixel.apply(script);   // otros engines: timers, colores, clases de Flixel
 *   if (script.execute()) script.call('onCreate');
 */
@:allow(fluxscript.FluxLib)
class FluxScript
{
	public static inline var VERSION:String = '1.1.0';

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

	/** Qué hacer con print(...) de todos los scripts (por defecto, trace). Cada script puede tener el suyo. */
	public static dynamic function defaultPrintHandler(script:FluxScript, text:String):Void
		trace('[FluxScript] ${script.name}: $text');

	/**
	 * Busca un archivo para require, importScript, fileExists y readFile. Devuelve la
	 * ruta, o null si no existe. Por defecto mira al lado del script y la ruta tal cual;
	 * los engines lo cambian para buscar en sus mods (FluxPsych lo hace para Psych).
	 */
	public static dynamic function findFile(path:String, ?from:FluxScript):String
		return findLocalFile(path, from);

	/** Lee un archivo de findFile (null si no se puede). */
	public static dynamic function readFile(path:String):String
	{
		#if sys
		try
		{
			return sys.io.File.getContent(path);
		}
		catch (e:Dynamic) {}
		#end
		return null;
	}

	/** findFile por defecto: al lado del script, o la ruta tal cual. */
	public static function findLocalFile(path:String, ?from:FluxScript):String
	{
		#if sys
		if (path == null || path.length == 0)
			return null;
		if (from != null && from.name != null)
		{
			var dir:String = haxe.io.Path.directory(from.name);
			if (dir.length > 0)
			{
				var near:String = haxe.io.Path.join([dir, path]);
				if (sys.FileSystem.exists(near) && !sys.FileSystem.isDirectory(near))
					return near;
			}
		}
		if (sys.FileSystem.exists(path) && !sys.FileSystem.isDirectory(path))
			return path;
		#end
		return null;
	}

	/** Nombre del script (la ruta del archivo) para los errores. */
	public var name(default, null):String;

	public var interp(default, null):FluxInterp;
	public var parser(default, null):FluxParser;

	/** false después de destroy(). */
	public var active(default, null):Bool = true;

	/** Lo que devolvió el cuerpo del script al ejecutarse. */
	public var returnValue:Dynamic = null;

	/** Si el último código ejecutado tenía un `return valor` fuera de las funciones. */
	public var returnedValue(default, null):Bool = false;

	/** Errores de este script (si es null se usa defaultErrorHandler). */
	public var onError:String->Void = null;

	/** Avisos de este script (si es null se usa defaultWarningHandler). */
	public var onWarning:String->Void = null;

	/** Se llama cuando el script se cierra solo con close(). */
	public var onClose:Void->Void = null;

	/** print(...) de este script (si es null se usa defaultPrintHandler). */
	public var onPrint:String->Void = null;

	/**
	 * Llama a una función del script desde Haxe (un callback de un timer, un tween...).
	 * Los errores se avisan con onError (`where` dice dónde) y devuelve null.
	 */
	public function callSafe(fn:Dynamic, ?args:Array<Dynamic>, ?where:String = 'callback'):Dynamic
	{
		if (!active || fn == null || !Reflect.isFunction(fn))
			return null;
		try
		{
			return interp != null ? interp.callProtected(fn, args) : Reflect.callMethod(null, fn, args != null ? args : []);
		}
		catch (e:Dynamic)
		{
			error('Error en $where: ' + errorText(e));
		}
		return null;
	}

	/** Carpeta del mod del script (la pone el engine; la usa getModSetting). */
	public var modFolder:String = null;

	/**
	 * Para los scripts globales (los que duran toda la partida): sus task.wait y
	 * task.delay siguen aunque cambie el estado o se pause el juego, y sus módulos
	 * de require no se borran al cambiar de estado.
	 */
	public var persistent:Bool = false;

	/** Lo que se le aplicó al script (FluxFlixel, FluxPsych...), para hacer lo mismo con los módulos de require. */
	var presets:Array<{name:String, apply:FluxScript->Void}> = [];

	/** Las tareas que están esperando (se cancelan con destroy). */
	var tasks:Array<FluxTask> = [];

	/** La tarea que se está ejecutando (task.spawn, task.delay o lo que sigue a un task.wait). */
	var currentTask:FluxTask = null;

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

		// lo de Lua y Luau: task, require, print, warn, typeof, pcall, math, os...
		FluxLib.apply(this);
	}

	/**
	 * Aplica algo al script una sola vez (FluxFlixel.apply, FluxPsych.apply...) y lo
	 * anota para hacer lo mismo con los módulos que cargue con require.
	 * Devuelve false si ya se había aplicado.
	 */
	public function usePreset(name:String, apply:FluxScript->Void):Bool
	{
		if (hasPreset(name))
			return false;
		presets.push({name: name, apply: apply});
		apply(this);
		return true;
	}

	public function hasPreset(name:String):Bool
	{
		for (preset in presets)
			if (preset.name == name)
				return true;
		return false;
	}

	/** Le aplica a otro script lo mismo que se le aplicó a este (para los módulos de require). */
	public function copyPresetsTo(other:FluxScript):Void
	{
		for (preset in presets)
			other.usePreset(preset.name, preset.apply);
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

	/**
	 * Ejecuta más código en el mismo intérprete (las variables y funciones se mantienen).
	 * `origin` es el nombre para los errores (por defecto, el del script).
	 */
	public function run(source:String, ?origin:String):Bool
	{
		if (!active || source == null)
			return false;
		try
		{
			var expr:Expr = parse(source, origin);
			returnedValue = FluxAsync.returnsValue(expr);
			returnValue = interp.executeNested(expr);
			return true;
		}
		catch (e:Dynamic)
		{
			error('Error al cargar: ' + errorText(e));
			return false;
		}
	}

	/**
	 * Lee el código (con los textos con variables y los task.wait ya preparados) sin
	 * ejecutarlo. Si no se puede leer, tira el error.
	 */
	public function parse(source:String, ?origin:String):Expr
	{
		// el salto de línea final evita que el parser lea de más si el archivo termina en "#end"
		var expr:Expr = parser.parseString(FluxSyntax.process(source) + '\n', origin != null ? origin : name);
		return FluxAsync.transform(expr, warn);
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
		var previousTask:FluxTask = currentTask;
		currentTask = null; // lo que llama el engine no es parte de una tarea
		var list:Array<Dynamic> = listeners.get(eventKey(name));
		if (list != null)
			for (fn in list.copy())
			{
				var value:Dynamic = callFunction(name, fn, args);
				if (value != null)
					result = value;
			}
		var fn:Dynamic = functionOf(name);
		if (fn != null && active)
		{
			var value:Dynamic = callFunction(name, fn, args);
			if (value != null)
				result = value;
		}
		currentTask = previousTask;
		return result;
	}

	/** Ejecuta `fn` como parte de una tarea (task.spawn, task.delay o lo que sigue a un task.wait). */
	@:allow(fluxscript)
	function runTask(task:FluxTask, fn:Dynamic, args:Array<Dynamic>, where:String):Dynamic
	{
		if (!active || fn == null || !Reflect.isFunction(fn))
			return null;
		var previous:FluxTask = currentTask;
		currentTask = task;
		var result:Dynamic = null;
		try
		{
			result = interp != null ? interp.callProtected(fn, args) : Reflect.callMethod(null, fn, args != null ? args : []);
		}
		catch (e:Dynamic)
		{
			error('Error en $where: ' + errorText(e));
		}
		currentTask = previous;
		return result;
	}

	@:allow(fluxscript)
	function trackTask(task:FluxTask):Void
	{
		if (!tasks.contains(task))
			tasks.push(task);
	}

	@:allow(fluxscript)
	function untrackTask(task:FluxTask):Void
		tasks.remove(task);

	/** Las tareas que están esperando. */
	public function pendingTasks():Array<FluxTask>
		return tasks.copy();

	/** Cancela todas las tareas que están esperando (task.wait, task.delay...). */
	public function cancelTasks():Void
	{
		for (task in tasks.copy())
			task.cancel();
		tasks = [];
	}

	function callFunction(name:String, fn:Dynamic, args:Array<Dynamic>):Dynamic
	{
		try
		{
			return interp != null ? interp.callProtected(fn, args) : Reflect.callMethod(null, fn, args);
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

	/** Si el script tiene esa variable (aunque valga null). */
	public function has(name:String):Bool
		return interp != null && interp.variables.exists(name);

	/** set, pero solo si el script todavía no la tiene (así no se pisa lo que puso el engine). */
	public function setDefault(name:String, value:Dynamic):Void
		if (!has(name))
			set(name, value);

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
		cancelTasks();
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

	/** Lo que hace print(...) en este script. */
	public function print(text:String):Void
	{
		if (onPrint != null)
			onPrint(text);
		else
			defaultPrintHandler(this, text);
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
