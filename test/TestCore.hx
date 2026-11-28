import fluxscript.FluxClasses;
import fluxscript.FluxScript;
import fluxscript.FluxTasks;

/** El estado del juego de mentira (sus campos se usan directo). */
@:keep
class Juego
{
	public var health:Float = 1;
	public var songScore:Int = 0;
	public var nombre:String = 'bf';

	public function new() {}

	public function saludo():String
		return 'hey';
}

/** Pruebas de FluxScript sin Flixel (haxe test.hxml). */
class TestCore
{
	static var passes:Int = 0;
	static var fails:Int = 0;
	static var errors:Array<String> = [];
	static var warnings:Array<String> = [];

	static function check(cond:Bool, msg:String):Void
	{
		if (cond)
			passes++;
		else
		{
			fails++;
			Sys.println('FALLO: $msg');
		}
	}

	static function script(code:String, ?parent:Dynamic):FluxScript
	{
		var s:FluxScript = new FluxScript(code, 'prueba.flux', parent);
		s.onError = function(message) errors.push(message);
		s.onWarning = function(message) warnings.push(message);
		return s;
	}

	static function listFiles(dir:String, out:Array<String>):Void
	{
		if (!sys.FileSystem.exists(dir))
			return;
		for (entry in sys.FileSystem.readDirectory(dir))
		{
			var path:String = dir + '/' + entry;
			if (sys.FileSystem.isDirectory(path))
				listFiles(path, out);
			else if (StringTools.endsWith(entry, '.flux') || StringTools.endsWith(entry, '.fluxg'))
				out.push(path);
		}
	}

	public static function main()
	{
		var keep:Array<Dynamic> = [demo.MiClase];
		FluxClasses.addPackage('demo.');

		// textos con variables
		var s = script("
			var n = 'Juaquin';
			var puntos = 21;
			var lista = [1, 2];
			a = 'Hola $n, tienes ${puntos * 2} puntos';
			b = 'precio: $$5 y ${'anidado ' + n}';
			c = \"sin cambio $n\";
			d = '${lista.length} cosas';
			e = 'solo texto';
			f = '$n';
		");
		check(s.execute(), 'interpolación carga: ' + errors);
		check(s.get('a') == 'Hola Juaquin, tienes 42 puntos', 'a = ' + s.get('a'));
		check(s.get('b') == "precio: $5 y anidado Juaquin", 'b = ' + s.get('b'));
		check(s.get('c') == "sin cambio $n", 'c = ' + s.get('c'));
		check(s.get('d') == '2 cosas', 'd = ' + s.get('d'));
		check(s.get('e') == 'solo texto' && s.get('f') == 'Juaquin', 'e, f');

		// campos del padre directo (leer y cambiar)
		var juego = new Juego();
		s = script("
			health = 2;
			songScore += 100;
			songScore++;
			var antes = songScore--;
			x = nombre + ' ' + saludo() + ' ' + antes;
			function subir() { health += 0.5; return health; }
		", juego);
		check(s.execute(), 'padre carga: ' + errors);
		check(juego.health == 2 && juego.songScore == 100, 'health ${juego.health}, songScore ${juego.songScore}');
		check(s.get('x') == 'bf hey 101', 'x = ' + s.get('x'));
		check(s.call('subir') == 2.5 && juego.health == 2.5, 'función que cambia el padre');
		check(s.get('health') == null, 'no se creó una variable "health" del script');

		// sin import
		s = script("
			var m = new MiClase(5);
			var otra = new demo.MiClase();
			valor = m.valor + otra.valor;
		");
		check(s.execute(), 'sin import carga: ' + errors);
		check(s.get('valor') == 12, 'new MiClase sin import: ' + s.get('valor'));
		errors = [];
		s = script("var x = NoExiste.algo;");
		check(!s.execute() && errors.length == 1 && errors[0].indexOf('NoExiste') >= 0, 'una clase que no existe da error claro: ' + errors);

		// import que no existe: avisa y sigue
		errors = [];
		warnings = [];
		s = script("import nada.NoExiste; listo = true;");
		check(s.execute() && s.get('listo') == true, 'import que no existe no corta el script');
		check(errors.length == 0 && warnings.length == 1 && warnings[0].indexOf('nada.NoExiste') >= 0, 'el import que no existe es un aviso: ' + warnings);

		// import con la ruta de otro engine (el engine pone FluxClasses.resolver)
		FluxClasses.resolver = function(path:String):Dynamic return path == 'funkin.game.MiClase' ? demo.MiClase : null;
		s = script("import funkin.game.MiClase as Otra; valor = new Otra(3).valor + new MiClase(1).valor;");
		check(s.execute() && s.get('valor') == 4, 'import con FluxClasses.resolver y alias: ' + s.get('valor') + ' ' + errors);
		FluxClasses.resolver = null;

		// desde un archivo
		sys.io.File.saveContent('/tmp/fluxscript_prueba.flux', "function hola() return 'archivo';");
		s = FluxScript.fromFile('/tmp/fluxscript_prueba.flux');
		check(s != null && s.execute() && s.call('hola') == 'archivo', 'FluxScript.fromFile');
		check(FluxScript.fromFile('/tmp/no_existe.flux') == null, 'fromFile de un archivo que no existe da null');

		// on(): varias funciones para el mismo evento
		s = script("
			golpes = [];
			on('beatHit', function(b) golpes.push(b));
			on('onBeatHit', function(b) golpes.push(b + 100));
			function onBeatHit(b) { golpes.push(b * 10); return 'ok'; }
			on('stepHit', function(s) pasos = s);
		");
		check(s.execute(), 'on carga');
		check(s.call('onBeatHit', [3]) == 'ok', 'call devuelve lo de la función del script');
		check(Std.string(s.get('golpes')) == '[3,103,30]', 'golpes = ' + s.get('golpes'));
		check(s.exists('onStepHit') && s.exists('onBeatHit') && !s.exists('onUpdate'), 'exists con on()');
		s.call('onStepHit', [8]);
		check(s.get('pasos') == 8, 'on("stepHit") sin función del script');

		// for sobre null, shared, #if e importCode
		var a = script("for (x in null) nunca = true; shared.monedas = 5; #if FLUXSCRIPT flux = true; #else flux = false; #end");
		var b = script("monedas = shared.monedas; importCode('extra = monedas * 2;');");
		check(a.execute() && b.execute(), 'shared/importCode cargan: ' + errors);
		check(a.get('nunca') == null && a.get('flux') == true, 'for sobre null y #if FLUXSCRIPT');
		check(b.get('monedas') == 5 && b.get('extra') == 10, 'shared entre scripts e importCode');

		// errores
		errors = [];
		s = script("function rompe() { var o = null; return o.campo; } function bien() return 1;");
		check(s.execute(), 'carga');
		check(s.call('rompe') == null && errors.length == 1 && errors[0].indexOf('rompe') >= 0, 'error en una función: ' + errors);
		check(s.call('bien') == 1, 'el script sigue funcionando después del error');
		errors = [];
		s = script("var x = ;");
		check(!s.execute() && errors.length == 1 && errors[0].indexOf('Error al cargar') >= 0, 'error de sintaxis: ' + errors);

		// close()
		var closed:Bool = false;
		s = script("function cerrar() this.close(); function f() return 1;");
		s.onClose = function() closed = true;
		check(s.execute(), 'close carga');
		s.call('cerrar');
		check(closed && !s.active && s.call('f') == null, 'close() deja de recibir llamadas');

		// checkSyntax y los ejemplos del repo (solo se leen, no se ejecutan)
		check(FluxScript.checkSyntax("var a = 'x $y';") == null, 'checkSyntax de código bien');
		var bad:String = FluxScript.checkSyntax("var a = ;\nvar b = 2;", 'malo.flux');
		check(bad != null && bad.indexOf('malo.flux') >= 0, 'checkSyntax da el error: ' + bad);
		var examples:Array<String> = [];
		listFiles('../examples', examples);
		check(examples.length >= 4, 'ejemplos encontrados: ' + examples);
		for (file in examples)
		{
			var problem:String = FluxScript.checkSyntax(sys.io.File.getContent(file), file);
			check(problem == null, 'el ejemplo $file se lee bien: $problem');
		}

		TestLuau.run(check, script, errors, warnings);

		Sys.println('FluxScript (núcleo): $passes OK, $fails fallos');
		if (fails > 0)
			Sys.exit(1);
	}
}
