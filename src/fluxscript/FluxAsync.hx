package fluxscript;

import crowplexus.hscript.Expr;
import crowplexus.hscript.Tools;

/**
 * `task.wait(segundos)` dentro de una función, como en Luau:
 *
 *     function onSongStart() {
 *         texto.text = '3';
 *         task.wait(1);
 *         texto.text = '2';
 *         var pasaron = task.wait(0.5);
 *         texto.text = '¡Ya!';
 *     }
 *
 * HScript no puede pausar una función a la mitad, así que antes de ejecutar el código
 * las funciones con task.wait se reescriben: lo que sigue a cada espera pasa a una
 * función que se llama cuando la espera termina. Funciona en el cuerpo de la función y
 * dentro de if/else, switch, while, do-while y for (con break y continue). `wait(segundos)`
 * con un solo argumento es lo mismo (si el script no tiene su propia función `wait`).
 *
 * Lo que no se puede (avisa con la línea): task.wait dentro de una expresión
 * (`trace(task.wait(1))`), dentro de try/catch o fuera de una función. Ojo: la función
 * vuelve en el primer task.wait, así que si otra función la llamó, esa sigue sin esperar
 * (para eso está task.spawn).
 */
class FluxAsync
{
	/** La función que hace la espera (FluxLib la pone en cada script). */
	public static inline var WAIT:String = '__fluxWait';

	/** La que da el iterador de un `for` que espera. */
	public static inline var ITERATOR:String = '__fluxIterator';

	static inline var RESULT:String = '__fluxDt';

	var counter:Int = 0;
	var bareWait:Bool = true;
	var warn:String->Void;

	function new(warn:String->Void)
		this.warn = warn;

	/** El código con las funciones que esperan ya reescritas (o el mismo, si no hay ningún task.wait). */
	public static function transform(e:Expr, ?warn:String->Void):Expr
	{
		if (e == null)
			return e;
		var t:FluxAsync = new FluxAsync(warn != null ? warn : function(_) {});
		t.bareWait = !declares(e, 'wait');
		if (!t.anyWait(e))
			return e;
		var result:Expr = t.visit(e);
		for (left in t.waitsIn(result))
			t.warn(t.at(left) + 'task.wait solo espera dentro de una función (onCreate, onBeatHit, task.spawn...)');
		return result;
	}

	/** Si el código tiene un `return valor` fuera de las funciones (lo que exporta un módulo de require). */
	public static function returnsValue(e:Expr):Bool
	{
		var found:Bool = false;
		function look(x:Expr):Void
		{
			if (found || x == null)
				return;
			switch (Tools.expr(x))
			{
				case EReturn(value):
					if (value != null)
						found = true;
					return;
				case EFunction(_, _, _, _):
					return;
				default:
			}
			Tools.iter(x, look);
		}
		look(e);
		return found;
	}

	// ------------------------------------------------------------------
	// Buscar las esperas
	// ------------------------------------------------------------------

	/** Los argumentos de task.wait(...) / wait(...), o null si no es una espera. */
	function waitArgs(e:Expr):Array<Expr>
	{
		if (e == null)
			return null;
		switch (Tools.expr(e))
		{
			case ECall(callee, args) if (args.length <= 1):
				switch (Tools.expr(callee))
				{
					case EField(owner, 'wait', _):
						switch (Tools.expr(owner))
						{
							case EIdent('task'):
								return args;
							default:
						}
					case EIdent('wait') if (bareWait):
						return args;
					default:
				}
			case EParent(inner):
				return waitArgs(inner);
			default:
		}
		return null;
	}

	/** Si hay una espera en `e` (sin mirar dentro de otras funciones). */
	function hasWait(e:Expr):Bool
	{
		if (e == null)
			return false;
		if (waitArgs(e) != null)
			return true;
		switch (Tools.expr(e))
		{
			case EFunction(_, _, _, _):
				return false;
			default:
		}
		var found:Bool = false;
		Tools.iter(e, function(sub:Expr) {
			if (!found && hasWait(sub))
				found = true;
		});
		return found;
	}

	/** Si hay una espera en cualquier parte (también dentro de funciones). */
	function anyWait(e:Expr):Bool
	{
		if (e == null)
			return false;
		if (waitArgs(e) != null)
			return true;
		var found:Bool = false;
		Tools.iter(e, function(sub:Expr) {
			if (!found && anyWait(sub))
				found = true;
		});
		return found;
	}

	/** Las esperas que quedaron sin reescribir (sin mirar dentro de otras funciones). */
	function waitsIn(e:Expr):Array<Expr>
	{
		var list:Array<Expr> = [];
		function look(x:Expr):Void
		{
			if (x == null)
				return;
			if (waitArgs(x) != null)
			{
				list.push(x);
				return;
			}
			switch (Tools.expr(x))
			{
				case EFunction(_, _, _, _):
					return;
				default:
			}
			Tools.iter(x, look);
		}
		look(e);
		return list;
	}

	/** Si el script declara su propia función o variable con ese nombre. */
	static function declares(e:Expr, name:String):Bool
	{
		var found:Bool = false;
		function look(x:Expr):Void
		{
			if (found || x == null)
				return;
			switch (Tools.expr(x))
			{
				case EFunction(_, _, n, _) if (n == name):
					found = true;
					return;
				case EVar(n, _, _, _) if (n == name):
					found = true;
					return;
				default:
			}
			Tools.iter(x, look);
		}
		look(e);
		return found;
	}

	// ------------------------------------------------------------------
	// Reescribir
	// ------------------------------------------------------------------

	function visit(e:Expr):Expr
	{
		if (e == null)
			return null;
		switch (Tools.expr(e))
		{
			case EFunction(args, body, name, ret):
				var inner:Expr = visit(body);
				if (hasWait(inner))
				{
					inner = mk(EBlock(block(statements(inner), null)), inner);
					for (left in waitsIn(inner))
						warn(at(left) + 'task.wait no espera aquí: úsalo como una línea sola (no dentro de una expresión ni de try/catch)');
				}
				return mk(EFunction(args, inner, name, ret), e);
			default:
				return map(e, visit);
		}
	}

	/** La espera de una línea: `task.wait(s)`, `var x = task.wait(s)` o `x = task.wait(s)`. */
	function waitStatement(s:Expr):{seconds:Expr, bind:Array<Expr>}
	{
		var args:Array<Expr> = waitArgs(s);
		if (args != null)
			return {seconds: secondsOf(args, s), bind: []};
		switch (Tools.expr(s))
		{
			case EVar(n, t, value, isConst):
				var a:Array<Expr> = waitArgs(value);
				if (a != null)
					return {seconds: secondsOf(a, s), bind: [mk(EVar(n, t, ident(RESULT, s), isConst), s)]};
			case EBinop('=', target, value):
				var a:Array<Expr> = waitArgs(value);
				if (a != null)
					return {seconds: secondsOf(a, s), bind: [mk(EBinop('=', target, ident(RESULT, s)), s)]};
			case EMeta(_, _, inner):
				return waitStatement(inner);
			default:
		}
		return null;
	}

	function secondsOf(args:Array<Expr>, at:Expr):Expr
		return args.length > 0 ? args[0] : mk(EConst(CInt(0)), at);

	/**
	 * Las líneas de un bloque, con lo que sigue a cada espera dentro de una función.
	 * `k` es la función a llamar cuando el bloque termina (null si no hay nada después).
	 */
	function block(list:Array<Expr>, k:Expr):Array<Expr>
	{
		var out:Array<Expr> = [];
		for (i in 0...list.length)
		{
			var s:Expr = list[i];
			if (!hasWait(s))
			{
				out.push(s);
				continue;
			}
			var rest:Array<Expr> = list.slice(i + 1);
			var w = waitStatement(s);
			if (w != null)
			{
				var body:Array<Expr> = w.bind.concat(block(rest, k));
				out.push(call(ident(FluxAsync.WAIT, s), [w.seconds, fn([RESULT], body, s)], s));
				return out;
			}
			var next:Expr = k;
			if (rest.length > 0)
			{
				var name:String = '__fluxNext' + (++counter);
				out.push(mk(EVar(name, null, fn([], block(rest, k), s)), s));
				next = ident(name, s);
			}
			for (x in compound(s, next))
				out.push(x);
			return out;
		}
		if (k != null)
			out.push(call(k, [], k));
		return out;
	}

	/** Una línea con una espera adentro (if, switch, un bloque o un loop). */
	function compound(s:Expr, k:Expr):Array<Expr>
	{
		switch (Tools.expr(s))
		{
			case EBlock(list):
				return [mk(EBlock(block(list, k)), s)];
			case EParent(inner):
				return compound(inner, k);
			case EMeta(_, _, inner):
				return compound(inner, k);
			case EIf(cond, yes, no):
				return [mk(EIf(cond, branch(yes, k), no != null ? branch(no, k) : end(k, s)), s)];
			case ESwitch(value, cases, def):
				var list:Array<SwitchCase> = [
					for (c in cases)
						({values: c.values, expr: branch(c.expr, k), ifExpr: c.ifExpr} : SwitchCase)
				];
				return [mk(ESwitch(value, list, def != null ? branch(def, k) : end(k, s)), s)];
			case EWhile(cond, body):
				return loop(s, cond, body, k, false, null);
			case EDoWhile(cond, body):
				return loop(s, cond, body, k, true, null);
			case EFor(v, it, body):
				var iterator:String = '__fluxIt' + (++counter);
				var out:Array<Expr> = [mk(EVar(iterator, null, call(ident(FluxAsync.ITERATOR, s), [it], s)), s)];
				var cond:Expr = call(field(ident(iterator, s), 'hasNext', s), [], s);
				var first:Expr = mk(EVar(v, null, call(field(ident(iterator, s), 'next', s), [], s)), s);
				for (x in loop(s, cond, body, k, false, first))
					out.push(x);
				return out;
			default:
				// try/catch o una espera dentro de una expresión: no se puede (transform avisa)
				var out:Array<Expr> = [s];
				if (k != null)
					out.push(call(k, [], s));
				return out;
		}
	}

	function branch(e:Expr, k:Expr):Expr
		return mk(EBlock(block(statements(e), k)), e);

	function end(k:Expr, at:Expr):Expr
		return k != null ? mk(EBlock([call(k, [], at)]), at) : null;

	/**
	 * Un loop que espera. Cada vuelta es una función (`__fluxBodyN`) y `__fluxLoopN` las
	 * va llamando: si la vuelta termina sin esperar, sigue en el mismo `do..while` (así un
	 * loop largo no llena la pila); si espera, la vuelta llama a `__fluxLoopN` al terminar.
	 *   break    -> { __fluxRunN = false; k(); return; }
	 *   continue -> { __fluxLoopN(); return; }
	 */
	function loop(at:Expr, cond:Expr, body:Expr, k:Expr, doWhile:Bool, first:Expr):Array<Expr>
	{
		var id:Int = ++counter;
		var running:String = '__fluxRun$id';
		var again:String = '__fluxAgain$id';
		var loopName:String = '__fluxLoop$id';
		var bodyName:String = '__fluxBody$id';
		var firstName:String = '__fluxFirst$id';

		var stop:Array<Expr> = [assign(running, bool(false, at), at)];
		if (k != null)
			stop.push(call(k, [], at));
		stop.push(mk(EReturn(null), at));
		var breakExpr:Expr = mk(EBlock(stop), at);
		var continueExpr:Expr = mk(EBlock([call(ident(loopName, at), [], at), mk(EReturn(null), at)]), at);

		var lines:Array<Expr> = [for (x in statements(body)) jumps(x, breakExpr, continueExpr)];
		if (first != null)
			lines.unshift(first);
		var bodyFn:Expr = fn([], block(lines, ident(loopName, at)), at);

		var test:Expr = doWhile ? mk(EBinop('||', ident(firstName, at), cond), at) : cond;
		var run:Array<Expr> = [];
		if (doWhile)
			run.push(assign(firstName, bool(false, at), at));
		run.push(call(ident(bodyName, at), [], at));
		var exit:Array<Expr> = [assign(running, bool(false, at), at)];
		if (k != null)
			exit.push(call(k, [], at));
		exit.push(mk(EReturn(null), at));

		var loopFn:Expr = fn([], [
			mk(EIf(ident(running, at), mk(EBlock([assign(again, bool(true, at), at), mk(EReturn(null), at)]), at)), at),
			assign(running, bool(true, at), at),
			mk(EDoWhile(ident(again, at), mk(EBlock([
				assign(again, bool(false, at), at),
				mk(EIf(test, mk(EBlock(run), at), mk(EBlock(exit), at)), at)
			]), at)), at),
			assign(running, bool(false, at), at)
		], at);

		var out:Array<Expr> = [
			mk(EVar(running, null, bool(false, at)), at),
			mk(EVar(again, null, bool(false, at)), at),
			mk(EVar(loopName, null, mk(EIdent('null'), at)), at)
		];
		if (doWhile)
			out.push(mk(EVar(firstName, null, bool(true, at)), at));
		out.push(mk(EVar(bodyName, null, bodyFn), at));
		out.push(assign(loopName, loopFn, at));
		out.push(call(ident(loopName, at), [], at));
		return out;
	}

	/** Cambia los break/continue de este loop (no los de un loop o una función de adentro). */
	function jumps(e:Expr, breakExpr:Expr, continueExpr:Expr):Expr
	{
		if (e == null)
			return null;
		switch (Tools.expr(e))
		{
			case EBreak:
				return breakExpr;
			case EContinue:
				return continueExpr;
			case EWhile(_, _) | EDoWhile(_, _) | EFor(_, _, _) | EFunction(_, _, _, _):
				return e;
			default:
				return map(e, function(x:Expr) return jumps(x, breakExpr, continueExpr));
		}
	}

	// ------------------------------------------------------------------
	// Ayudas para armar el código
	// ------------------------------------------------------------------

	static function statements(e:Expr):Array<Expr>
	{
		return switch (Tools.expr(e))
		{
			case EBlock(list): list;
			default: [e];
		}
	}

	static function mk(def:ExprDef, at:Expr):Expr
	{
		#if hscriptPos
		var e:Expr = {
			e: def,
			pmin: at != null ? at.pmin : 0,
			pmax: at != null ? at.pmax : 0,
			origin: at != null ? at.origin : null,
			line: at != null ? at.line : 0
		};
		return e;
		#else
		return def;
		#end
	}

	/** Tools.map de hscript, pero que devuelve un Expr (el de Tools con hscriptPos no se puede usar con tipos). */
	static function map(e:Expr, f:Expr->Expr):Expr
	{
		var def:ExprDef = switch (Tools.expr(e))
		{
			case EVar(n, t, v, c): EVar(n, t, v != null ? f(v) : null, c);
			case EParent(x): EParent(f(x));
			case EBlock(list): EBlock([for (x in list) f(x)]);
			case EField(x, name, safe): EField(f(x), name, safe);
			case EBinop(op, a, b): EBinop(op, f(a), f(b));
			case EUnop(op, prefix, x): EUnop(op, prefix, f(x));
			case ECall(x, args): ECall(f(x), [for (a in args) f(a)]);
			case EIf(c, a, b): EIf(f(c), f(a), b != null ? f(b) : null);
			case EWhile(c, x): EWhile(f(c), f(x));
			case EDoWhile(c, x): EDoWhile(f(c), f(x));
			case EFor(v, it, x): EFor(v, f(it), f(x));
			case EFunction(args, x, name, ret): EFunction(args, f(x), name, ret);
			case EReturn(x): EReturn(x != null ? f(x) : null);
			case EArray(x, i): EArray(f(x), f(i));
			case EArrayDecl(list): EArrayDecl([for (x in list) f(x)]);
			case ENew(cl, args): ENew(cl, [for (a in args) f(a)]);
			case EThrow(x): EThrow(f(x));
			case ETry(x, v, t, c): ETry(f(x), v, t, f(c));
			case EObject(fields): EObject([for (field in fields) {name: field.name, e: f(field.e)}]);
			case ETernary(c, a, b): ETernary(f(c), f(a), f(b));
			case ESwitch(x, cases, def):
				ESwitch(f(x), [
					for (c in cases)
						({values: [for (v in c.values) f(v)], expr: f(c.expr), ifExpr: c.ifExpr != null ? f(c.ifExpr) : null} : SwitchCase)
				], def != null ? f(def) : null);
			case EMeta(name, args, x): EMeta(name, args == null ? null : [for (a in args) f(a)], f(x));
			case ECheckType(x, t): ECheckType(f(x), t);
			default: return e;
		}
		return mk(def, e);
	}

	static function ident(name:String, at:Expr):Expr
		return mk(EIdent(name), at);

	static function field(e:Expr, name:String, at:Expr):Expr
		return mk(EField(e, name, false), at);

	static function call(fnExpr:Expr, args:Array<Expr>, at:Expr):Expr
		return mk(ECall(fnExpr, args), at);

	static function assign(name:String, value:Expr, at:Expr):Expr
		return mk(EBinop('=', ident(name, at), value), at);

	static function bool(value:Bool, at:Expr):Expr
		return mk(EIdent(value ? 'true' : 'false'), at);

	static function fn(params:Array<String>, body:Array<Expr>, at:Expr):Expr
		return mk(EFunction([for (p in params) {name: p, opt: true}], mk(EBlock(body), at)), at);

	/** "línea 12: " (con -D hscriptPos), para los avisos. */
	function at(e:Expr):String
	{
		#if hscriptPos
		return 'línea ${e.line}: ';
		#else
		return '';
		#end
	}
}
