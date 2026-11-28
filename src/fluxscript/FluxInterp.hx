package fluxscript;

import crowplexus.hscript.Expr;
import crowplexus.hscript.Interp;
import crowplexus.hscript.Tools;

/**
 * El intérprete de FluxScript: el de HScript (hscript-iris) con estos agregados:
 *
 *  - Los campos del "padre" (el estado del juego: PlayState, un menú...) se usan
 *    directo, para leer y para cambiar: `health = 2`, `songScore += 100`,
 *    `boyfriend.visible = false`.
 *  - Sin `import`: un nombre con mayúscula que no existe se busca como clase
 *    (FluxClasses). Un `import` de algo que no existe avisa (warningHandler) y no
 *    corta el script.
 *  - `for (x in null)` no hace nada en vez de cortar el script.
 *  - executeNested: importCode/loadstring desde una función no le borran sus variables.
 *  - callProtected: un error atrapado desde Haxe (pcall) no rompe las variables locales.
 *  - `i++` / `i--` sobre variables locales (hscript-iris 1.1 no las cambiaba).
 */
class FluxInterp extends Interp
{
	/** El objeto cuyos campos el script usa directo (o null). */
	public var parent(default, set):Dynamic = null;

	/** Avisos que no cortan el script (un `import` de algo que no existe). */
	public var warningHandler:String->Void = null;

	var parentFields:Map<String, Bool> = new Map<String, Bool>();

	public function new()
	{
		super();
		showPosOnLog = false;
		depth = 0; // hscript lo pone recién en execute (y executeNested lo guarda antes)
		inTry = false;
	}

	function set_parent(value:Dynamic):Dynamic
	{
		parent = value;
		parentFields = new Map<String, Bool>();
		if (value != null)
		{
			var cls:Class<Dynamic> = Type.getClass(value);
			if (cls != null)
				for (field in Type.getInstanceFields(cls))
					parentFields.set(field, true);
		}
		return value;
	}

	/** Si `id` es un campo del padre que el script no tapó con una variable propia. */
	public inline function isParentField(id:String):Bool
		return parent != null && parentFields.exists(id) && !locals.exists(id) && !variables.exists(id);

	override function resolve(id:String):Dynamic
	{
		var local = locals.get(id);
		if (local != null)
			return local.r;
		if (variables.exists(id))
			return variables.get(id);
		if (imports.exists(id))
			return imports.get(id);
		if (parent != null && parentFields.exists(id))
			return Reflect.getProperty(parent, id);

		// sin import: FlxBackdrop, BitmapData, HealthIcon...
		var first:Int = StringTools.fastCodeAt(id, 0);
		if (first >= 'A'.code && first <= 'Z'.code)
		{
			var found:Dynamic = FluxClasses.find(id);
			if (found != null)
			{
				imports.set(id, found);
				return found;
			}
		}
		error(EUnknownVariable(id));
		return null;
	}

	override public function getOrImportClass(name:String):Dynamic
	{
		var found:Dynamic = FluxClasses.resolvePath(name);
		if (found != null)
			return found;
		found = super.getOrImportClass(name);
		if (found == null && FluxClasses.resolver != null)
			found = FluxClasses.resolver(name); // nombres de otros engines (los pone el engine)
		return found;
	}

	/** `import` de algo que no existe: avisa (con el aviso del script) y sigue. */
	override public function expr(e:Expr):Dynamic
	{
		switch (Tools.expr(e))
		{
			case EImport(path, alias):
				#if hscriptPos
				curExpr = e;
				#end
				if (crowplexus.iris.Iris.blocklistImports.contains(path))
					error(ECustom('No se puede importar "$path"'));
				var found:Dynamic = getOrImportClass(path);
				if (found == null)
				{
					if (warningHandler != null)
						warningHandler('import: no existe "$path"');
					return null;
				}
				imports.set(path.substr(path.lastIndexOf('.') + 1), found);
				if (alias != null)
					imports.set(alias, found);
				return null;
			default:
				return super.expr(e);
		}
	}

	// ----- cambiar campos del padre sin "game." -----

	override function assign(e1:Expr, e2:Expr):Dynamic
	{
		switch (Tools.expr(e1))
		{
			case EIdent(id) if (isParentField(id)):
				var value:Dynamic = expr(e2);
				Reflect.setProperty(parent, id, value);
				return value;
			default:
				return super.assign(e1, e2);
		}
	}

	override function evalAssignOp(op:String, fop:Dynamic->Dynamic->Dynamic, e1:Expr, e2:Expr):Dynamic
	{
		switch (Tools.expr(e1))
		{
			case EIdent(id) if (isParentField(id)):
				var value:Dynamic = fop(Reflect.getProperty(parent, id), expr(e2));
				Reflect.setProperty(parent, id, value);
				return value;
			default:
				return super.evalAssignOp(op, fop, e1, e2);
		}
	}

	override function increment(e:Expr, prefix:Bool, delta:Int):Dynamic
	{
		switch (Tools.expr(e))
		{
			case EIdent(id) if (isParentField(id)):
				var old:Dynamic = Reflect.getProperty(parent, id);
				var value:Dynamic = old + delta;
				Reflect.setProperty(parent, id, value);
				return prefix ? value : old;
			case EIdent(id) if (locals.get(id) != null):
				// hscript-iris 1.1 no cambia las variables locales con ++ y -- (`var i = 0; i++;` dejaba 0)
				#if hscriptPos
				curExpr = e;
				#end
				var local = locals.get(id);
				if (local.const == true)
					error(ECustom('No se puede cambiar "$id": es final'));
				var old:Dynamic = local.r;
				local.r = old + delta;
				return prefix ? local.r : old;
			default:
				return super.increment(e, prefix, delta);
		}
	}

	override function makeIterator(v:Dynamic):Iterator<Dynamic>
	{
		if (v == null)
			return [].iterator();
		return super.makeIterator(v);
	}

	/** El iterador de un `for (x in v)` (lo usan los `for` que esperan con task.wait). */
	public function iteratorOf(v:Dynamic):Iterator<Dynamic>
		return makeIterator(v);

	/**
	 * Llama a una función del script desde Haxe. Si la función tira un error, el
	 * intérprete vuelve a como estaba antes de llamarla (hscript solo lo hace dentro de
	 * un try/catch del script) y el error sigue: así pcall, o un callback del engine que
	 * falla en medio de otra función, no le rompen las variables a lo que se estaba ejecutando.
	 */
	public function callProtected(fn:Dynamic, args:Array<Dynamic>):Dynamic
	{
		var oldLocals = locals;
		var oldDepth:Int = depth;
		var oldDeclared:Int = declared.length;
		var oldTry:Bool = inTry;
		try
		{
			return Reflect.callMethod(null, fn, args != null ? args : []);
		}
		catch (err:Dynamic)
		{
			locals = oldLocals;
			depth = oldDepth;
			if (declared.length > oldDeclared)
				declared.splice(oldDeclared, declared.length - oldDeclared);
			inTry = oldTry;
			throw err;
		}
	}

	/**
	 * Ejecuta código sin borrar las variables locales de lo que se estaba ejecutando
	 * (importCode, importScript o loadstring desde adentro de una función).
	 */
	public function executeNested(e:Expr):Dynamic
	{
		var oldLocals = locals;
		var oldDepth:Int = depth;
		var oldDeclared = declared;
		try
		{
			var result:Dynamic = execute(e);
			locals = oldLocals;
			depth = oldDepth;
			declared = oldDeclared;
			return result;
		}
		catch (err:Dynamic)
		{
			locals = oldLocals;
			depth = oldDepth;
			declared = oldDeclared;
			throw err;
		}
	}

	override function fcall(o:Dynamic, f:String, args:Array<Dynamic>):Dynamic
	{
		for (entry in usings) // `using StringTools;` y compañía
		{
			var v:Dynamic = entry.call(o, f, args);
			if (v != null)
				return v;
		}
		if (o == null)
			error(EInvalidAccess(f));
		var fn:Dynamic = get(o, f);
		if (fn == null || !Reflect.isFunction(fn))
			error(ECustom('No existe la función "$f" en ${describe(o)}'));
		return call(o, fn, args);
	}

	/** Un nombre corto para los errores (la clase del objeto). */
	public static function describe(o:Dynamic):String
	{
		if (o == null)
			return 'null';
		if (Std.isOfType(o, Class))
			return Type.getClassName(cast o);
		var cls:Class<Dynamic> = Type.getClass(o);
		return cls != null ? Type.getClassName(cls) : Std.string(Type.typeof(o));
	}
}
