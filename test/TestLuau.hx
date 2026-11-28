import fluxscript.FluxLib;
import fluxscript.FluxScript;
import fluxscript.FluxTasks;

/** Pruebas de lo de Lua y Luau (task.wait, task.*, require, print, math...). */
class TestLuau
{
	static var check:(Bool, String) -> Void;
	static var make:(String, ?Dynamic) -> FluxScript;
	static var errors:Array<String>;
	static var warnings:Array<String>;

	static function step(times:Int = 1, seconds:Float = 0.1):Void
		for (i in 0...times)
			FluxTasks.update(seconds);

	static function clean():Void
	{
		errors.resize(0);
		warnings.resize(0);
	}

	public static function run(checkFn:(Bool, String) -> Void, makeFn:(String, ?Dynamic) -> FluxScript, errorList:Array<String>, warningList:Array<String>):Void
	{
		check = checkFn;
		make = makeFn;
		errors = errorList;
		warnings = warningList;
		clean();

		waits();
		loops();
		tasks();
		modules();
		basics();
	}

	static function waits():Void
	{
		// task.wait en el cuerpo de una función
		var s = make("
			log = [];
			function contar() {
				log.push('3');
				task.wait(1);
				log.push('2');
				var pasaron = task.wait(0.5);
				log.push('dt ' + pasaron);
				wait(0.5);
				log.push('ya');
			}
		");
		check(s.execute(), 'task.wait carga: ' + errors);
		s.call('contar');
		var log:Array<Dynamic> = s.get('log');
		check(log.join(',') == '3', 'antes de la espera: ' + log);
		step(5);
		check(log.join(',') == '3', 'todavía esperando a los 0.5s: ' + log);
		step(6);
		check(log.join(',') == '3,2', 'después de 1s: ' + log);
		step(5);
		check(log.join(',') == '3,2,dt 0.5', 'var = task.wait(0.5): ' + log);
		step(5);
		check(log.join(',') == '3,2,dt 0.5,ya', 'wait(0.5) con un argumento: ' + log);
		check(s.pendingTasks().length == 0 && FluxTasks.pending() == 0, 'no quedan esperas');

		// if / else / switch y las variables de antes de la espera
		s = make("
			log = [];
			function f(modo) {
				var n = 10;
				if (modo == 'a') {
					task.wait(1);
					n += 1;
				} else if (modo == 'b') {
					n += 2;
				} else {
					return 'nada';
				}
				switch (modo) {
					case 'a': task.wait(1); n *= 10;
					default: n *= 100;
				}
				log.push(modo + n);
				return 'fin';
			}
		");
		check(s.execute(), 'if/switch carga: ' + errors);
		check(s.call('f', ['b']) == 'fin', 'una función que no llega a esperar devuelve lo de siempre');
		check(s.call('f', ['c']) == 'nada', 'return antes de esperar');
		s.call('f', ['a']);
		check((s.get('log') : Array<Dynamic>).join(',') == 'b1200', 'el camino sin esperas sigue igual: ' + s.get('log'));
		step(25);
		check((s.get('log') : Array<Dynamic>).join(',') == 'b1200,a110', 'if y switch que esperan: ' + s.get('log'));

		// función propia llamada wait: no se toca
		s = make("function wait(x) return x * 2; function f() { var a = wait(3); return a; }");
		check(s.execute() && s.call('f') == 6, 'una función wait del script no se cambia');

		// avisos
		clean();
		s = make("task.wait(1); function f() { trace(task.wait(1)); }");
		check(s.execute(), 'carga con avisos');
		check(warnings.length == 2, 'avisa el task.wait de afuera y el de la expresión: ' + warnings);
		check(warnings.length == 2 && warnings[0].indexOf('línea') >= 0, 'el aviso dice la línea: ' + warnings);
		clean();

		// un error después de la espera
		s = make("function f() { task.wait(0.1); var o = null; o.campo = 1; }");
		check(s.execute(), 'carga');
		s.call('f');
		step(2);
		check(errors.length == 1 && errors[0].indexOf('task.wait') >= 0, 'el error después de una espera se avisa: ' + errors);
		clean();
	}

	static function loops():Void
	{
		var s = make("
			log = [];
			function f() {
				var i = 0;
				while (i < 3) {
					log.push('w' + i);
					task.wait(0.1);
					i++;
				}
				for (x in ['a', 'b', 'c']) {
					if (x == 'b') continue;
					task.wait(0.1);
					log.push(x);
				}
				var j = 0;
				do {
					j++;
					if (j == 2) break;
					task.wait(0.1);
				} while (j < 5);
				log.push('j' + j);
				for (k in 0...3) {
					for (m in 0...2) {
						if (m == 1) break;
						task.wait(0.1);
						log.push(k + '' + m);
					}
				}
				log.push('fin');
			}
		");
		check(s.execute(), 'loops carga: ' + errors);
		s.call('f');
		step(30);
		check((s.get('log') : Array<Dynamic>).join(',') == 'w0,w1,w2,a,c,j2,00,10,20,fin', 'while/for/do-while/break/continue/anidados: ' + s.get('log'));

		// un loop largo que casi nunca espera no llena la pila
		s = make("
			total = 0;
			function f() {
				for (i in 0...20000) {
					if (i == 19999) task.wait(0.1);
					total += 1;
				}
				listo = true;
			}
		");
		check(s.execute(), 'loop largo carga');
		s.call('f');
		check(s.get('total') == 19999 && s.get('listo') != true, 'loop largo antes de la espera: ' + s.get('total'));
		step(2);
		check(s.get('total') == 20000 && s.get('listo') == true, 'loop largo después de la espera: ' + s.get('total'));

		// cada vuelta del for tiene su propia variable (para las funciones de adentro)
		s = make("
			log = [];
			function f() {
				for (i in 0...3) {
					task.delay(0.5, function() log.push(i));
					task.wait(0.1);
				}
			}
		");
		check(s.execute(), 'for con delay carga');
		s.call('f');
		step(10);
		check((s.get('log') : Array<Dynamic>).join(',') == '0,1,2', 'cada vuelta su variable: ' + s.get('log'));
		clean();
	}

	static function tasks():Void
	{
		var s = make("
			log = [];
			function contar(desde) {
				var n = desde;
				while (n > 0) {
					log.push(n);
					task.wait(1);
					n--;
				}
				log.push('fin');
			}
			function empezar() {
				tarea = task.spawn(contar, 3);
				task.delay(0.5, function(a, b) log.push(a + b), 'x', 'y');
				task.defer(function() log.push('defer'));
				otra = task.delay(5, function() log.push('nunca'));
				task.wait(0.2, function() log.push('wait con función'));
			}
		");
		check(s.execute(), 'task carga: ' + errors);
		s.call('empezar');
		var log:Array<Dynamic> = s.get('log');
		check(log.join(',') == '3', 'task.spawn corre enseguida: ' + log);
		var tarea:Dynamic = s.get('tarea');
		check(Std.isOfType(tarea, FluxTask) && (tarea : FluxTask).waiting, 'task.spawn devuelve la tarea (esperando)');
		step(1, 0.01);
		check(log.join(',') == '3,defer', 'task.defer en el siguiente frame: ' + log);
		step(1, 0.2);
		check(log.join(',') == '3,defer,wait con función', 'task.wait(segundos, función): ' + log);
		step(3, 0.1);
		check(log.join(',') == '3,defer,wait con función,xy', 'task.delay con argumentos: ' + log);
		step(5, 0.1);
		check(log.join(',') == '3,defer,wait con función,xy,2', 'sigue la tarea: ' + log);
		s.run('task.cancel(tarea); task.cancel(otra);');
		check((s.get('tarea') : FluxTask).cancelled, 'task.cancel');
		step(80, 0.1);
		check(log.join(',') == '3,defer,wait con función,xy,2', 'después de cancelar no sigue: ' + log);
		check(s.pendingTasks().length == 0, 'no quedan tareas');

		// destroy cancela lo que espera
		s = make("function f() { task.wait(1); hecho = true; } function g() { task.delay(1, function() hecho = true); }");
		check(s.execute(), 'carga');
		s.call('f');
		s.call('g');
		check(s.pendingTasks().length == 2, 'dos tareas esperando: ' + s.pendingTasks().length);
		var before:Int = FluxTasks.pending();
		s.destroy();
		check(FluxTasks.pending() == before - 2, 'destroy cancela las esperas');
		step(20);

		// close: no sigue
		s = make("function f() { task.wait(0.1); hecho = true; }");
		check(s.execute(), 'carga');
		s.call('f');
		s.close();
		step(3);
		check(s.get('hecho') == null, 'un script cerrado no sigue después de la espera');
		clean();
	}

	static function modules():Void
	{
		var dir:String = '/tmp/fluxscript_modulos';
		if (!sys.FileSystem.exists(dir))
			sys.FileSystem.createDirectory(dir);
		sys.io.File.saveContent('$dir/utilidades.flux', "
			var veces = 0; // privada
			function doble(x) { veces++; return x * 2; }
			function cuantas() return veces;
		");
		sys.io.File.saveContent('$dir/tabla.flux', "return {nombre: 'tabla', suma: function(a, b) return a + b};");
		sys.io.File.saveContent('$dir/circular.flux', "var yo = require('circular');");
		sys.io.File.saveContent('$dir/roto.flux', "var x = ;");
		sys.io.File.saveContent('$dir/extra.flux', "extra = 'importado ' + base;");
		sys.io.File.saveContent('$dir/datos.json', '{"vidas": 3}');

		var s = FluxScript.fromFile('$dir/principal.flux') ?? new FluxScript("
			function probar() {
				var u = require('utilidades');
				var t = require('tabla.flux');
				var otra = require('utilidades');
				return [u.doble(4), u.doble(1), otra.cuantas(), u == otra, t.nombre, t.suma(2, 3), u.veces];
			}
			function errores() {
				var r1 = pcall(require, 'no_existe');
				var r2 = pcall(require, 'circular');
				var r3 = pcall(require, 'roto');
				return [r1[0], r1[1], r2[1], r3[0]];
			}
			function archivos() {
				base = 'ok';
				var bien = importScript('extra');
				return [bien, extra, base, fileExists('datos.json'), fileExists('nada.json'), parseJson(readFile('datos.json')).vidas, toJson({a: 1})];
			}
		", '$dir/principal.flux');
		s.onError = function(m) errors.push(m);
		s.onWarning = function(m) warnings.push(m);
		check(s.execute(), 'require carga: ' + errors);
		var r:Array<Dynamic> = s.call('probar');
		check(r != null && r.join(',') == '8,2,2,true,tabla,5,null', 'require: exports, caché y return: ' + r + ' ' + errors);
		clean();
		r = s.call('errores');
		check(r != null && r[0] == false && Std.string(r[1]).indexOf('no_existe') >= 0, 'require de algo que no existe: ' + r);
		check(r != null && Std.string(r[2]).indexOf('circular') >= 0 && r[3] == false, 'require circular y con error: ' + r);
		clean();
		r = s.call('archivos');
		check(r != null && r.join(',') == 'true,importado ok,ok,true,false,3,{"a":1}', 'importScript, fileExists, readFile y json: ' + r + ' ' + errors);
		FluxLib.clearModules(true);
		clean();

		// el ejemplo del repo (examples/modules/cuenta.flux)
		var ejemplo = new FluxScript("function f() { var c = require('cuenta'); return [c.numeros(3).join(' '), c.puntos(12), c.puntos(2), c.vecesUsado(), c.usos]; }", '../examples/modules/principal.flux');
		ejemplo.onError = function(m) errors.push(m);
		check(ejemplo.execute(), 'ejemplo carga');
		r = ejemplo.call('f');
		check(r != null && r.join(',') == '3 2 1,50,0,2,null', 'examples/modules/cuenta.flux: ' + r + ' ' + errors);
		FluxLib.clearModules(true);
		clean();

		// loadstring e importCode dentro de una función no borran sus variables
		s = make("
			function f() {
				var local = 5;
				importCode('desdeImport = 1;');
				var g = loadstring('return local2 * 2;');
				local2 = 21;
				var mal = loadstring('var = ;');
				return [local, g(), mal == null, desdeImport];
			}
		");
		check(s.execute(), 'loadstring carga');
		r = s.call('f');
		check(r != null && r.join(',') == '5,42,true,1', 'loadstring e importCode: ' + r + ' ' + errors);
		check(warnings.length == 1 && warnings[0].indexOf('loadstring') >= 0, 'loadstring con error avisa: ' + warnings);
		clean();

		// los presets se copian a los módulos
		var usos:Int = 0;
		s = make("function f() return require('utilidades').doble(1);", null);
		s.usePreset('prueba', function(x:FluxScript) {
			usos++;
			x.set('marca', 'si');
		});
		check(!s.usePreset('prueba', function(_) usos++), 'usePreset no aplica dos veces');
		var m = new FluxScript("x = marca;", '$dir/m.flux');
		s.copyPresetsTo(m);
		check(m.execute() && m.get('x') == 'si' && usos == 2, 'copyPresetsTo: ' + usos);
		clean();
	}

	static function basics():Void
	{
		var printed:Array<String> = [];
		var s = make("
			function f() {
				print('hola', 2, true);
				warn('cuidado', 1);
				return [
					typeof(1), typeof(1.5), typeof('a'), typeof(true), typeof(null), typeof([1]), typeof({a: 1}),
					typeof(f), typeof(new StringMap()), typeof(Math)
				];
			}
			function numeros() {
				return [tonumber('12'), tonumber('0x1F'), tonumber('-2.5'), tonumber('ff', 16), tonumber('1e3'), tonumber('hola'), tonumber('12abc'), tostring(5)];
			}
			function protegido() {
				var ok = pcall(function(a, b) return a + b, 2, 3);
				var mal = pcall(function() error('se rompió'));
				var x = xpcall(function() error('otra'), function(e) return 'manejado: ' + e);
				var a = pcall(assert, false, 'falló assert');
				var b = assert(7, 'no');
				return [ok[0], ok[1], mal[0], mal[1], x[1], a[1], b];
			}
			function matematica() {
				return [math.clamp(15, 0, 10), math.round(2.5), math.round(-2.5), math.sign(-3), math.lerp(0, 10, 0.25),
					math.map(5, 0, 10, 0, 100), math.min(3, 1, 2), math.max(3, 1, 2), math.floor(2.7), math.pi > 3.14,
					math.random(3, 3), math.random(1) == 1, math.random() < 1];
			}
			function tiempo() {
				var t = os.date('*t');
				return [t.year > 2000, os.time() > 0, tick() > 0, os.clock() >= 0, os.date('%Y').length];
			}
		");
		s.onPrint = function(text) printed.push(text);
		check(s.execute(), 'básicos cargan: ' + errors);
		var r:Array<Dynamic> = s.call('f');
		check(printed.join('|') == 'hola 2 true', 'print: ' + printed);
		check(warnings.length == 1 && warnings[0] == 'cuidado 1', 'warn: ' + warnings);
		check(r != null && r.join(',') == 'Int,Float,String,Bool,null,Array,Object,Function,StringMap,Class', 'typeof: ' + r);
		r = s.call('numeros');
		check(r != null && r.join(',') == '12,31,-2.5,255,1000,null,null,5', 'tonumber/tostring: ' + r);
		r = s.call('protegido');
		check(r != null && r[0] == true && r[1] == 5 && r[2] == false && Std.string(r[3]).indexOf('se rompió') >= 0, 'pcall: ' + r);
		check(r != null && r[4] == 'manejado: otra' && r[5] == 'falló assert' && r[6] == 7, 'xpcall/assert: ' + r);
		r = s.call('matematica');
		check(r != null && r.join(',') == '10,3,-3,-1,2.5,50,1,3,2,true,3,true,true', 'math: ' + r);
		r = s.call('tiempo');
		check(r != null && r.join(',') == 'true,true,true,true,4', 'os y tick: ' + r);
		check(errors.length == 0, 'sin errores: ' + errors);
		clean();
	}
}
