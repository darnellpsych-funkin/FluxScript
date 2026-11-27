package fluxscript;

import crowplexus.hscript.Expr;
import crowplexus.hscript.Parser;

/**
 * El parser de HScript (hscript-iris) con un arreglo: un `#else` o un `#if` falso
 * que termina justo al final del archivo ya no lee más allá del final.
 */
class FluxParser extends Parser
{
	override function skipTokens()
	{
		var spos = preprocStack.length - 1;
		var obj = preprocStack[spos];
		var pos = readPos;
		while (true)
		{
			var tk = token();
			if (tk == TEof)
			{
				if (preprocStack.length != 0)
					error(EInvalidPreprocessor("Unclosed"), pos, pos);
				push(tk); // el fin del archivo sigue ahí para el que llamó
				break;
			}
			if (preprocStack[spos] != obj)
			{
				push(tk);
				break;
			}
		}
	}
}
