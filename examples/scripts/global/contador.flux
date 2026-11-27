// En mods/TuMod/scripts/global/: corre siempre (menús y canciones) y no se reinicia.
// (También sirve un archivo .fluxg en mods/TuMod/scripts/.)

var notas = 0;
var texto:FlxText = null;

function onStateCreatePost(estado) {
	texto = null;
	if (Std.isOfType(estado, PlayState)) return; // en las canciones no

	texto = makeText(10, FlxG.height - 30, 0, '', 16);
	texto.scrollFactor.set();
	estado.add(texto);

	every(1, function() {
		if (texto == null) return false; // false = deja de repetirse
		texto.text = 'Notas: $notas - ${DateTools.format(Date.now(), "%H:%M:%S")}';
		return true;
	});
}

function onStateSwitch(estado) {
	texto = null; // el menú viejo se borra con todo lo que tenía
}

// en las canciones llegan los mismos callbacks que a un script normal
function goodNoteHit(note) {
	if (!note.isSustainNote) notas++;
}
