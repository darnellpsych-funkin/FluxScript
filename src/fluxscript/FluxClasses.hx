package fluxscript;

/**
 * El "sin import" de FluxScript: si el script usa un nombre que empieza con
 * mayúscula y no existe (FlxBackdrop, HealthIcon, BitmapData...), se busca una
 * clase con ese nombre en los paquetes de Flixel, OpenFL, Haxe y los engines de
 * FNF (Psych, P-Slice, V-Slice, Codename...). El resultado se guarda.
 *
 * Los engines pueden agregar sus paquetes con `FluxClasses.addPackage('mi.paquete.')`
 * y nombres propios con `FluxClasses.alias('Nombre', Clase)`.
 */
class FluxClasses
{
	/** Paquetes donde se busca, en orden (con el punto al final; "" es el paquete raíz). */
	public static var packages(default, null):Array<String> = [
		'',
		// Flixel
		'flixel.',
		'flixel.math.',
		'flixel.util.',
		'flixel.tweens.',
		'flixel.text.',
		'flixel.group.',
		'flixel.sound.',
		'flixel.graphics.',
		'flixel.graphics.frames.',
		'flixel.animation.',
		'flixel.effects.',
		'flixel.effects.particles.',
		'flixel.ui.',
		'flixel.input.keyboard.',
		'flixel.input.mouse.',
		'flixel.input.gamepad.',
		'flixel.path.',
		'flixel.system.',
		'flixel.addons.display.',
		'flixel.addons.effects.',
		'flixel.addons.effects.chainable.',
		'flixel.addons.text.',
		'flixel.addons.transition.',
		'flixel.addons.util.',
		'flixel.addons.ui.',
		// OpenFL
		'openfl.display.',
		'openfl.filters.',
		'openfl.geom.',
		'openfl.media.',
		'openfl.text.',
		'openfl.utils.',
		'openfl.events.',
		'openfl.net.',
		'openfl.',
		// Haxe
		'haxe.',
		'haxe.ds.',
		'haxe.io.',
		'haxe.crypto.',
		'sys.',
		'sys.io.',
		// Psych Engine 1.0 y sus forks (Flux Engine, P-Slice...)
		'backend.',
		'objects.',
		'states.',
		'states.stages.',
		'states.editors.',
		'substates.',
		'options.',
		'psychlua.',
		'shaders.',
		'cutscenes.',
		'flxanimate.',
		// V-Slice y Codename Engine
		'funkin.',
		'funkin.play.',
		'funkin.graphics.',
		'funkin.audio.',
		'funkin.util.',
		'funkin.ui.',
		'funkin.game.',
		'funkin.backend.',
		'funkin.backend.utils.'
	];

	/**
	 * Para los `import` con rutas de otros engines: el engine puede devolver su
	 * equivalente (ej. "funkin.game.PlayState" de Codename -> states.PlayState).
	 */
	public static var resolver:String->Dynamic = null;

	static var aliases:Map<String, Dynamic> = new Map<String, Dynamic>();
	static var cache:Map<String, Dynamic> = new Map<String, Dynamic>();
	static var misses:Map<String, Bool> = new Map<String, Bool>();

	/** La clase (o enum) con ese nombre, o null si no hay ninguna. */
	public static function find(name:String):Dynamic
	{
		if (name == null || name.length == 0)
			return null;
		if (aliases.exists(name))
			return aliases.get(name);
		if (cache.exists(name))
			return cache.get(name);
		if (misses.exists(name))
			return null;

		var found:Dynamic = null;
		for (pack in packages)
		{
			found = Type.resolveClass(pack + name);
			if (found == null)
				found = Type.resolveEnum(pack + name);
			if (found != null)
				break;
		}
		if (found != null)
			cache.set(name, found);
		else
			misses.set(name, true);
		return found;
	}

	/** La clase de una ruta completa ("flixel.util.FlxColor"), con los alias de abstracts. */
	public static function resolvePath(path:String):Dynamic
	{
		if (path == null)
			return null;
		if (aliases.exists(path))
			return aliases.get(path);
		var found:Dynamic = Type.resolveClass(path);
		if (found == null)
			found = Type.resolveEnum(path);
		return found;
	}

	/** Agrega un paquete donde buscar (ej. "mikolka.vslice."). */
	public static function addPackage(pack:String):Void
	{
		if (pack == null)
			return;
		if (pack.length > 0 && !StringTools.endsWith(pack, '.'))
			pack += '.';
		if (!packages.contains(pack))
		{
			packages.push(pack);
			misses.clear();
		}
	}

	/**
	 * Un nombre propio (corto o con paquete) para algo que no es una clase en
	 * tiempo de ejecución, como los abstracts: alias('FlxColor', FluxColor).
	 */
	public static function alias(name:String, value:Dynamic):Void
	{
		aliases.set(name, value);
		misses.remove(name);
	}

	public static function clearCache():Void
	{
		cache.clear();
		misses.clear();
	}
}
