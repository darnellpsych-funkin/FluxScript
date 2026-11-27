// En mods/TuMod/states/MainMenuState.flux: corre mientras está abierto el menú principal.
// Los campos del menú también se usan directo.

var aviso = makeText(0, FlxG.height - 44, FlxG.width, 'FluxScript $FLUXSCRIPT_VERSION - presiona M', 20);

function onCreatePost() {
	aviso.alignment = 'center';
	aviso.scrollFactor.set();
	add(aviso);
}

function onUpdate(elapsed) {
	if (keyboardJustPressed('M'))
		aviso.text = 'Hola desde $scriptName';
}
