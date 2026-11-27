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
