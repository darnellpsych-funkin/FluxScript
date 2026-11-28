package fluxscript;

import crowplexus.hscript.Expr;
import fluxscript.FluxTasks.FluxTask;

using StringTools;

/**
 * Lo de Lua y Luau que trae todo FluxScript (no depende de Flixel):
 *
 *  - `task.wait(segundos)` dentro de las funciones (ver FluxAsync), `task.spawn(f, ...)`,
 *    `task.defer(f, ...)`, `task.delay(segundos, f, ...)` y `task.cancel(tarea)`.
 *  - `require('modulo')`: carga otro .flux una sola vez y devuelve lo que exporta.
 *  - `importScript('archivo')`: ejecuta otro .flux dentro de este (comparten todo).
 *  - `loadstring(código)`: devuelve una función que ejecuta ese código.
 *  - `print`, `warn`, `typeof`, `tostring`, `tonumber`, `pcall`, `xpcall`, `error`, `assert`.
 *  - `math` (clamp, round, sign, lerp, map, random...), `os` (time, clock, date) y `tick()`.
 *  - `parseJson`, `toJson`, `fileExists` y `readFile`.
 */
@:access(fluxscript.FluxScript)
class FluxLib
{
	public static function apply(script:FluxScript):Void
	{
		tasks(script);
		modules(script);
		basics(script);
		libraries(script);
	}

	// ------------------------------------------------------------------
	// task
	// ------------------------------------------------------------------

	static function tasks(script:FluxScript):Void
	{
		// lo que FluxAsync pone en lugar de cada task.wait
		script.set(FluxAsync.WAIT, function(seconds:Dynamic, next:Dynamic):Dynamic {
			var task:FluxTask = script.currentTask != null ? script.currentTask : new FluxTask(script);
			var secs:Float = FluxTasks.seconds(seconds);
			task.schedule(secs, function() script.runTask(task, next, [secs], 'task.wait'));
			return null;
		});
		script.set(FluxAsync.ITERATOR, function(value:Dynamic):Iterator<Dynamic> {
			return script.interp != null ? script.interp.iteratorOf(value) : [].iterator();
		});

		var task:Dynamic = {
			// la espera de verdad la arma FluxAsync; esto es task.wait(segundos, función)
			// (o un task.wait donde no se puede esperar, que no espera)
			wait: function(?seconds:Dynamic, ?fn:Dynamic):Dynamic {
				if (fn != null && Reflect.isFunction(fn))
					return later(script, FluxTasks.seconds(seconds), fn, [], 'task.wait');
				return 0;
			},
			spawn: Reflect.makeVarArgs(function(args:Array<Dynamic>):Dynamic {
				var fn:Dynamic = args.shift();
				var t:FluxTask = new FluxTask(script);
				if (fn == null || !Reflect.isFunction(fn))
					script.warn('task.spawn: falta la función');
				else
					script.runTask(t, fn, args, 'task.spawn');
				return t;
			}),
			defer: Reflect.makeVarArgs(function(args:Array<Dynamic>):Dynamic {
				var fn:Dynamic = args.shift();
				return later(script, 0, fn, args, 'task.defer');
			}),
			delay: Reflect.makeVarArgs(function(args:Array<Dynamic>):Dynamic {
				var seconds:Float = FluxTasks.seconds(args.shift());
				var fn:Dynamic = args.shift();
				return later(script, seconds, fn, args, 'task.delay');
			}),
			cancel: function(target:Dynamic):Void {
				if (target == null)
					return;
				if (Std.isOfType(target, FluxTask))
					(target : FluxTask).cancel();
				else
					FluxTasks.stopTimer(target); // un FlxTimer o un FlxTween también
			}
		};
		script.set('task', task);
	}

	static function later(script:FluxScript, seconds:Float, fn:Dynamic, args:Array<Dynamic>, where:String):FluxTask
	{
		var t:FluxTask = new FluxTask(script);
		if (fn == null || !Reflect.isFunction(fn))
		{
			script.warn('$where: falta la función');
			return t;
		}
		t.schedule(seconds, function() script.runTask(t, fn, args, where));
		return t;
	}

	// ------------------------------------------------------------------
	// require, importScript, loadstring y archivos
	// ------------------------------------------------------------------

	static var loaded:Map<String, FluxModule> = new Map<String, FluxModule>();

	/**
	 * Borra los módulos de require (los vuelve a cargar el próximo require).
	 * FluxFlixel lo llama al cambiar de estado; `all` también borra los de los scripts globales.
	 */
	public static function clearModules(?all:Bool = false):Void
	{
		for (key in [for (k in loaded.keys()) k])
		{
			var entry:FluxModule = loaded.get(key);
			if (all || !entry.persistent)
			{
				loaded.remove(key);
				if (entry.script != null)
					entry.script.destroy();
			}
		}
	}

	static function modules(script:FluxScript):Void
	{
		script.set('require', function(name:String):Dynamic return requireModule(script, name));
		script.set('importScript', function(path:String):Bool {
			var file:String = findScript(script, path);
			if (file == null)
			{
				script.warn('importScript: no existe "$path"');
				return false;
			}
			var code:String = FluxScript.readFile(file);
			return code != null && script.run(code, file);
		});
		script.set('loadstring', function(source:String, ?chunkName:String):Dynamic {
			if (source == null)
				return null;
			var expr:Expr = null;
			try
			{
				expr = script.parse(source, chunkName != null ? chunkName : script.name);
			}
			catch (e:Dynamic)
			{
				script.warn('loadstring: ' + FluxScript.errorText(e));
				return null;
			}
			return Reflect.makeVarArgs(function(args:Array<Dynamic>):Dynamic {
				return script.interp != null ? script.interp.executeNested(expr) : null;
			});
		});

		script.set('fileExists', function(path:String):Bool return FluxScript.findFile(path, script) != null);
		script.set('readFile', function(path:String):String {
			var file:String = FluxScript.findFile(path, script);
			return file != null ? FluxScript.readFile(file) : null;
		});
		script.set('parseJson', function(text:String):Dynamic return text != null ? haxe.Json.parse(text) : null);
		script.set('toJson', function(value:Dynamic, ?pretty:Bool = false):String return haxe.Json.stringify(value, null, pretty ? '\t' : null));
	}

	/** "utilidades" -> utilidades.flux (o .hx), buscado con FluxScript.findFile. */
	public static function findScript(script:FluxScript, name:String):String
	{
		if (name == null || name.length == 0)
			return null;
		var lower:String = name.toLowerCase();
		var candidates:Array<String> = (lower.endsWith('.flux') || lower.endsWith('.fluxg') || lower.endsWith('.hx')) ? [name] : [
			name + '.flux',
			name + '.hx',
			name
		];
		for (candidate in candidates)
		{
			var file:String = FluxScript.findFile(candidate, script);
			if (file != null)
				return file;
		}
		return null;
	}

	/**
	 * require: el módulo se ejecuta una sola vez (en su propio script, con lo mismo que
	 * el que lo pidió) y se guarda lo que exporta: lo que devuelve con `return`, o si no
	 * devuelve nada, sus funciones y las variables que crea sin `var`.
	 */
	public static function requireModule(script:FluxScript, name:String):Dynamic
	{
		var file:String = findScript(script, name);
		if (file == null)
			throw 'require: no existe "$name"';
		var key:String = (script.persistent ? 'global:' : '') + file;
		var entry:FluxModule = loaded.get(key);
		if (entry != null)
		{
			if (entry.loading)
				throw 'require: "$name" se pide a sí mismo (require circular)';
			return entry.exports;
		}

		var code:String = FluxScript.readFile(file);
		if (code == null)
			throw 'require: no se pudo leer "$file"';
		var module:FluxScript = new FluxScript(code, file, script.parent);
		module.modFolder = script.modFolder;
		module.persistent = script.persistent;
		module.onError = script.onError;
		module.onWarning = script.onWarning;
		module.onPrint = script.onPrint;
		script.copyPresetsTo(module);

		entry = new FluxModule(module, script.persistent);
		loaded.set(key, entry);
		var before:Map<String, Dynamic> = module.interp.variables.copy();
		if (!module.execute())
		{
			loaded.remove(key);
			module.destroy();
			throw 'require: el módulo "$name" tiene un error';
		}
		entry.loading = false;
		entry.exports = module.returnedValue ? module.returnValue : exportsOf(module, before);
		return entry.exports;
	}

	static function exportsOf(module:FluxScript, before:Map<String, Dynamic>):Dynamic
	{
		var exports:Dynamic = {};
		for (key => value in module.interp.variables)
			if (!before.exists(key) || before.get(key) != value)
				Reflect.setField(exports, key, value);
		return exports;
	}

	// ------------------------------------------------------------------
	// print, warn, typeof, pcall...
	// ------------------------------------------------------------------

	static function basics(script:FluxScript):Void
	{
		script.set('print', Reflect.makeVarArgs(function(args:Array<Dynamic>):Dynamic {
			script.print(join(args));
			return null;
		}));
		script.set('warn', Reflect.makeVarArgs(function(args:Array<Dynamic>):Dynamic {
			script.warn(join(args));
			return null;
		}));
		script.set('typeof', typeOf);
		script.set('tostring', function(value:Dynamic):String return Std.string(value));
		script.set('tonumber', toNumber);

		// pcall(f, ...) -> [true, resultado] o [false, error]
		script.set('pcall', Reflect.makeVarArgs(function(args:Array<Dynamic>):Array<Dynamic> {
			var fn:Dynamic = args.shift();
			try
			{
				return [true, protectedCall(script, fn, args)];
			}
			catch (e:Dynamic)
			{
				return [false, FluxScript.errorText(e)];
			}
		}));
		// xpcall(f, alFallar, ...) -> [true, resultado] o [false, lo que devolvió alFallar(error)]
		script.set('xpcall', Reflect.makeVarArgs(function(args:Array<Dynamic>):Array<Dynamic> {
			var fn:Dynamic = args.shift();
			var handler:Dynamic = args.shift();
			try
			{
				return [true, protectedCall(script, fn, args)];
			}
			catch (e:Dynamic)
			{
				var text:String = FluxScript.errorText(e);
				return [false, (handler != null && Reflect.isFunction(handler)) ? protectedCall(script, handler, [text]) : text];
			}
		}));
		script.set('error', function(message:Dynamic, ?level:Int):Dynamic {
			throw message != null ? message : 'error';
		});
		script.set('assert', function(value:Dynamic, ?message:Dynamic):Dynamic {
			if (value == null || value == false)
				throw message != null ? message : 'assertion failed!';
			return value;
		});
	}

	static function protectedCall(script:FluxScript, fn:Dynamic, args:Array<Dynamic>):Dynamic
	{
		if (fn == null || !Reflect.isFunction(fn))
			throw 'se esperaba una función';
		return script.interp != null ? script.interp.callProtected(fn, args) : Reflect.callMethod(null, fn, args);
	}

	static function join(args:Array<Dynamic>):String
		return [for (arg in args) Std.string(arg)].join(' ');

	/** El tipo de un valor: 'null', 'Bool', 'Int', 'Float', 'String', 'Array', 'Function', 'Object', o el nombre de la clase ('FlxSprite'). */
	public static function typeOf(value:Dynamic):String
	{
		return switch (Type.typeof(value))
		{
			case TNull: 'null';
			case TInt: 'Int';
			case TFloat: 'Float';
			case TBool: 'Bool';
			case TFunction: 'Function';
			case TObject:
				if (Std.isOfType(value, Class)) 'Class'; else if (Std.isOfType(value, Enum)) 'Enum'; else 'Object';
			case TClass(c):
				if (c == String) 'String'; else if (c == Array) 'Array'; else shortName(Type.getClassName(c));
			case TEnum(e):
				shortName(Type.getEnumName(e));
			default:
				'Unknown';
		}
	}

	static function shortName(path:String):String
		return path == null ? 'Unknown' : path.substr(path.lastIndexOf('.') + 1);

	/** Como en Lua: tonumber('12') = 12, tonumber('0x1F') = 31, tonumber('ff', 16) = 255, tonumber('hola') = null. */
	public static function toNumber(value:Dynamic, ?base:Int):Dynamic
	{
		if (value == null || Std.isOfType(value, Bool))
			return null;
		if (Std.isOfType(value, Int) || Std.isOfType(value, Float))
			return value;
		var text:String = Std.string(value).trim().toLowerCase();
		if (text.length == 0)
			return null;
		var negative:Bool = text.charAt(0) == '-';
		var digits:String = (negative || text.charAt(0) == '+') ? text.substr(1) : text;
		if (base != null && base != 10)
		{
			if (base < 2 || base > 36 || digits.length == 0)
				return null;
			var result:Float = 0;
			for (i in 0...digits.length)
			{
				var c:Int = digits.charCodeAt(i);
				var d:Int = (c >= '0'.code && c <= '9'.code) ? c - '0'.code : ((c >= 'a'.code && c <= 'z'.code) ? c - 'a'.code + 10 : 99);
				if (d >= base)
					return null;
				result = result * base + d;
			}
			return intOrFloat(negative ? -result : result);
		}
		if (~/^0x[0-9a-f]+$/.match(digits))
		{
			var result:Float = 0;
			for (i in 2...digits.length)
			{
				var c:Int = digits.charCodeAt(i);
				result = result * 16 + ((c >= '0'.code && c <= '9'.code) ? c - '0'.code : c - 'a'.code + 10);
			}
			return intOrFloat(negative ? -result : result);
		}
		if (~/^([0-9]+\.?[0-9]*|\.[0-9]+)(e[+-]?[0-9]+)?$/.match(digits))
		{
			var number:Float = Std.parseFloat(digits);
			if (Math.isNaN(number))
				return null;
			if (negative)
				number = -number;
			return (digits.indexOf('.') < 0 && digits.indexOf('e') < 0) ? intOrFloat(number) : number;
		}
		return null;
	}

	static function intOrFloat(value:Float):Dynamic
		return (Math.abs(value) < 2147483647 && value == Math.ffloor(value)) ? Std.int(value) : value;

	// ------------------------------------------------------------------
	// math, os y tick
	// ------------------------------------------------------------------

	static function libraries(script:FluxScript):Void
	{
		var math:Dynamic = {
			pi: Math.PI,
			huge: Math.POSITIVE_INFINITY,
			abs: function(x:Float):Float return Math.abs(x),
			floor: function(x:Float):Int return Math.floor(x),
			ceil: function(x:Float):Int return Math.ceil(x),
			// como en Luau: 2.5 -> 3, -2.5 -> -3
			round: function(x:Float):Int return x >= 0 ? Math.floor(x + 0.5) : Math.ceil(x - 0.5),
			sqrt: function(x:Float):Float return Math.sqrt(x),
			pow: function(x:Float, y:Float):Float return Math.pow(x, y),
			exp: function(x:Float):Float return Math.exp(x),
			log: function(x:Float, ?base:Float):Float return base == null ? Math.log(x) : Math.log(x) / Math.log(base),
			sin: function(x:Float):Float return Math.sin(x),
			cos: function(x:Float):Float return Math.cos(x),
			tan: function(x:Float):Float return Math.tan(x),
			asin: function(x:Float):Float return Math.asin(x),
			acos: function(x:Float):Float return Math.acos(x),
			atan: function(y:Float, ?x:Float):Float return x == null ? Math.atan(y) : Math.atan2(y, x),
			atan2: function(y:Float, x:Float):Float return Math.atan2(y, x),
			fmod: function(a:Float, b:Float):Float return a % b,
			min: Reflect.makeVarArgs(function(args:Array<Dynamic>):Dynamic {
				var best:Dynamic = args.length > 0 ? args[0] : null;
				for (v in args)
					if (v < best)
						best = v;
				return best;
			}),
			max: Reflect.makeVarArgs(function(args:Array<Dynamic>):Dynamic {
				var best:Dynamic = args.length > 0 ? args[0] : null;
				for (v in args)
					if (v > best)
						best = v;
				return best;
			}),
			clamp: function(x:Float, min:Float, max:Float):Float return x < min ? min : (x > max ? max : x),
			sign: function(x:Float):Int return x > 0 ? 1 : (x < 0 ? -1 : 0),
			lerp: function(a:Float, b:Float, t:Float):Float return a + (b - a) * t,
			// math.map(5, 0, 10, 0, 100) = 50
			map: function(x:Float, inMin:Float, inMax:Float, outMin:Float, outMax:Float):Float {
				return inMax == inMin ? outMin : outMin + (x - inMin) * (outMax - outMin) / (inMax - inMin);
			},
			// como en Lua: math.random() = 0..1, math.random(6) = 1..6, math.random(5, 10) = 5..10
			random: function(?m:Dynamic, ?n:Dynamic):Dynamic {
				if (m == null)
					return Math.random();
				var low:Int = n == null ? 1 : Std.int(m);
				var high:Int = n == null ? Std.int(m) : Std.int(n);
				if (high < low)
					return low;
				return low + Std.random(high - low + 1);
			}
		};
		script.set('math', math);

		var os:Dynamic = {
			time: function():Float return Math.ffloor(Date.now().getTime() / 1000),
			clock: function():Float return haxe.Timer.stamp(),
			date: function(?format:String):Dynamic return dateOf(script, format)
		};
		script.set('os', os);
		script.set('tick', function():Float return Date.now().getTime() / 1000);
	}

	/** os.date(formato) con los % de DateTools ('%Y-%m-%d %H:%M:%S'), o '*t' para los datos sueltos. */
	static function dateOf(script:FluxScript, format:String):Dynamic
	{
		var now:Date = Date.now();
		if (format == '*t' || format == '!*t')
			return {
				year: now.getFullYear(),
				month: now.getMonth() + 1,
				day: now.getDate(),
				hour: now.getHours(),
				min: now.getMinutes(),
				sec: now.getSeconds(),
				wday: now.getDay() + 1,
				isdst: false
			};
		try
		{
			return DateTools.format(now, format != null ? format : '%Y-%m-%d %H:%M:%S');
		}
		catch (e:Dynamic)
		{
			script.warn('os.date: ' + Std.string(e));
		}
		return null;
	}
}

/** Un módulo cargado con require. */
class FluxModule
{
	public var script:FluxScript;
	public var exports:Dynamic = null;
	public var loading:Bool = true;
	public var persistent:Bool;

	public function new(script:FluxScript, persistent:Bool)
	{
		this.script = script;
		this.persistent = persistent;
	}
}
