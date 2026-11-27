package fluxscript;

/**
 * Lo que FluxScript le agrega a la sintaxis de HScript antes de leer el código.
 *
 *  - Textos con variables, como en Haxe: en las comillas simples, `$nombre` y
 *    `${expresión}` se reemplazan por su valor; `$$` es un `$`.
 *        'Hola $jugador, tienes ${score * 2} puntos'
 *    Las comillas dobles no cambian ("$x" queda igual).
 *
 * Las líneas no cambian de lugar, así los errores muestran la línea correcta.
 * No depende de Flixel (se puede probar solo).
 */
class FluxSyntax
{
	public static function process(code:String):String
	{
		if (code == null)
			return null;
		var out:StringBuf = new StringBuf();
		var i:Int = 0;
		var n:Int = code.length;
		while (i < n)
		{
			var c:Int = StringTools.fastCodeAt(code, i);

			// comentarios
			if (c == '/'.code && i + 1 < n)
			{
				var next:Int = StringTools.fastCodeAt(code, i + 1);
				if (next == '/'.code)
				{
					var end:Int = code.indexOf('\n', i);
					if (end < 0)
						end = n;
					out.add(code.substring(i, end));
					i = end;
					continue;
				}
				if (next == '*'.code)
				{
					var end:Int = code.indexOf('*/', i + 2);
					end = end < 0 ? n : end + 2;
					out.add(code.substring(i, end));
					i = end;
					continue;
				}
			}

			if (c == '"'.code)
			{
				var end:Int = stringEnd(code, i, '"'.code);
				out.add(code.substring(i, end));
				i = end;
				continue;
			}

			if (c == "'".code)
			{
				var end:Int = stringEnd(code, i, "'".code);
				out.add(interpolate(code.substring(i + 1, end - 1)));
				i = end;
				continue;
			}

			out.addChar(c);
			i++;
		}
		return out.toString();
	}

	/** Dónde termina el texto que empieza en `start` (después de la comilla final). */
	static function stringEnd(code:String, start:Int, quote:Int):Int
	{
		var n:Int = code.length;
		var j:Int = start + 1;
		var depth:Int = 0; // dentro de ${...} puede haber otras comillas y llaves
		while (j < n)
		{
			var d:Int = StringTools.fastCodeAt(code, j);
			if (d == '\\'.code)
			{
				j += 2;
				continue;
			}
			if (quote == "'".code && d == '$'.code && j + 1 < n && StringTools.fastCodeAt(code, j + 1) == '{'.code)
			{
				// ${ ... } : saltar hasta su llave, con textos adentro
				j = exprEnd(code, j + 2);
				continue;
			}
			j++;
			if (d == quote)
				return j;
		}
		return n;
	}

	/** Posición después de la `}` que cierra un `${` (desde el primer carácter de adentro). */
	static function exprEnd(code:String, from:Int):Int
	{
		var n:Int = code.length;
		var depth:Int = 1;
		var j:Int = from;
		while (j < n)
		{
			var d:Int = StringTools.fastCodeAt(code, j);
			if (d == '"'.code || d == "'".code)
			{
				j = stringEnd(code, j, d);
				continue;
			}
			if (d == '{'.code)
				depth++;
			else if (d == '}'.code)
			{
				depth--;
				if (depth == 0)
					return j + 1;
			}
			j++;
		}
		return n;
	}

	/** El contenido de un texto con comillas simples, con sus variables ya reemplazadas. */
	static function interpolate(body:String):String
	{
		if (body.indexOf('$') < 0)
			return "'" + body + "'";

		var parts:Array<String> = [];
		var literal:StringBuf = new StringBuf();
		var hasExpr:Bool = false;
		var i:Int = 0;
		var n:Int = body.length;
		while (i < n)
		{
			var c:Int = StringTools.fastCodeAt(body, i);
			if (c == '\\'.code && i + 1 < n)
			{
				literal.add(body.substr(i, 2));
				i += 2;
				continue;
			}
			if (c == '$'.code && i + 1 < n)
			{
				var next:Int = StringTools.fastCodeAt(body, i + 1);
				if (next == '$'.code)
				{
					literal.add('$');
					i += 2;
					continue;
				}
				if (next == '{'.code)
				{
					var end:Int = exprEnd(body, i + 2);
					var inner:String = body.substring(i + 2, end - 1);
					parts.push("'" + literal.toString() + "'");
					literal = new StringBuf();
					parts.push('(' + process(inner) + ')');
					hasExpr = true;
					i = end;
					continue;
				}
				if (isIdentStart(next))
				{
					var j:Int = i + 2;
					while (j < n && isIdentChar(StringTools.fastCodeAt(body, j)))
						j++;
					parts.push("'" + literal.toString() + "'");
					literal = new StringBuf();
					parts.push('(' + body.substring(i + 1, j) + ')');
					hasExpr = true;
					i = j;
					continue;
				}
			}
			literal.addChar(c);
			i++;
		}
		if (!hasExpr)
			return "'" + literal.toString() + "'";
		parts.push("'" + literal.toString() + "'");
		// "'' + (a) + ''": siempre empieza con un texto, así + junta textos
		return '(' + parts.join(' + ') + ')';
	}

	static inline function isIdentStart(c:Int):Bool
		return (c >= 'a'.code && c <= 'z'.code) || (c >= 'A'.code && c <= 'Z'.code) || c == '_'.code;

	static inline function isIdentChar(c:Int):Bool
		return isIdentStart(c) || (c >= '0'.code && c <= '9'.code);
}
