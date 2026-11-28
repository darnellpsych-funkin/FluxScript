package fluxscript;

/**
 * Las esperas de `task` (task.wait, task.delay, task.defer...), como en Luau.
 *
 * Sin Flixel se usa una lista propia que avanza con `FluxTasks.update(segundos)`.
 * FluxFlixel usa FlxTimer: así las esperas se pausan con el juego (igual que los
 * timers de Psych) y se borran al cambiar de estado. Las de los scripts con
 * `persistent = true` (los globales) siguen en la lista propia, que FluxFlixel
 * avanza en cada frame: no se pausan ni se borran.
 */
class FluxTasks
{
	/**
	 * Empieza una espera: llama a `callback` en `seconds` segundos (0 = el próximo
	 * frame) y devuelve algo para cancelarla con stopTimer. `persistent` es para los
	 * scripts globales: la espera sigue aunque cambie el estado.
	 */
	public static dynamic function startTimer(seconds:Float, callback:Void->Void, persistent:Bool):Dynamic
		return startOwnTimer(seconds, callback);

	/** Una espera de la lista propia (la que avanza con update). */
	public static function startOwnTimer(seconds:Float, callback:Void->Void):FluxOwnTimer
	{
		var timer:FluxOwnTimer = new FluxOwnTimer(clock + seconds, callback, nextOrder++);
		queue.push(timer);
		return timer;
	}

	/** Cancela una espera de startTimer. */
	public static dynamic function stopTimer(timer:Dynamic):Void
	{
		if (timer == null)
			return;
		if (Std.isOfType(timer, FluxOwnTimer))
		{
			(timer : FluxOwnTimer).cancelled = true;
			queue.remove(timer);
			return;
		}
		var cancel:Dynamic = Reflect.getProperty(timer, 'cancel');
		if (cancel != null && Reflect.isFunction(cancel))
			Reflect.callMethod(timer, cancel, []);
	}

	static var queue:Array<FluxOwnTimer> = [];
	static var clock:Float = 0;
	static var nextOrder:Int = 0;

	/**
	 * Avanza las esperas propias (solo hace falta sin Flixel). Lo que se pide durante
	 * esta llamada (como un task.defer) queda para la siguiente.
	 */
	public static function update(elapsed:Float):Void
	{
		clock += elapsed;
		var due:Array<FluxOwnTimer> = [for (timer in queue) if (timer.time <= clock + 0.0000001) timer];
		if (due.length == 0)
			return;
		due.sort(function(a, b) return a.time != b.time ? (a.time < b.time ? -1 : 1) : a.order - b.order);
		for (timer in due)
			queue.remove(timer);
		for (timer in due)
			if (!timer.cancelled)
				timer.callback();
	}

	/** Borra todas las esperas propias. */
	public static function clear():Void
	{
		for (timer in queue)
			timer.cancelled = true;
		queue = [];
	}

	/** Cuántas esperas propias hay (para las pruebas). */
	public static function pending():Int
		return queue.length;

	/** Los segundos de task.wait(segundos): null, negativo o un valor raro es 0 (el próximo frame). */
	public static function seconds(value:Dynamic):Float
	{
		if (value == null)
			return 0;
		var number:Float = Std.isOfType(value, String) ? Std.parseFloat(value) : value;
		return (Math.isNaN(number) || number < 0) ? 0 : number;
	}
}

/**
 * Una tarea: lo que devuelven task.spawn, task.delay y task.defer (y lo que usa una
 * función que hizo task.wait). `task.cancel(tarea)` o `tarea.cancel()` la frenan:
 * lo que estaba esperando ya no sigue.
 */
@:keep
class FluxTask
{
	public var script(default, null):FluxScript;

	/** true después de cancel(). */
	public var cancelled(default, null):Bool = false;

	/** Si está esperando (un task.wait o un task.delay que todavía no llegó). */
	public var waiting(get, never):Bool;

	var timers:Array<Dynamic> = [];

	public function new(script:FluxScript)
		this.script = script;

	function get_waiting():Bool
		return timers.length > 0;

	/** Llama a `fn` en `seconds` segundos (si la tarea no se canceló ni el script se cerró). */
	@:allow(fluxscript)
	function schedule(seconds:Float, fn:Void->Void):Void
	{
		if (cancelled || script == null || !script.active)
			return;
		var timer:Dynamic = null;
		timer = FluxTasks.startTimer(seconds, function() {
			timers.remove(timer);
			if (timers.length == 0 && script != null)
				script.untrackTask(this);
			if (!cancelled && script != null && script.active)
				fn();
		}, script.persistent);
		timers.push(timer);
		script.trackTask(this);
	}

	public function cancel():Void
	{
		if (cancelled)
			return;
		cancelled = true;
		for (timer in timers)
			FluxTasks.stopTimer(timer);
		timers = [];
		if (script != null)
			script.untrackTask(this);
	}

	public function toString():String
		return 'FluxTask(' + (cancelled ? 'cancelada' : (waiting ? 'esperando' : 'lista')) + ')';
}

/** Una espera de la lista propia de FluxTasks (sin Flixel). */
@:allow(fluxscript.FluxTasks)
class FluxOwnTimer
{
	var time:Float;
	var callback:Void->Void;
	var order:Int;
	var cancelled:Bool = false;

	function new(time:Float, callback:Void->Void, order:Int)
	{
		this.time = time;
		this.callback = callback;
		this.order = order;
	}

	public function cancel():Void
		FluxTasks.stopTimer(this);
}
