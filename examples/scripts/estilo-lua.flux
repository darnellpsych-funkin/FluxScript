// La API de Lua de Psych funciona igual en FluxScript (mismos nombres y argumentos).
// Donde va un tag también se puede pasar el objeto, y makeLua... devuelve el objeto.

function onCreate() {
	makeLuaSprite('nube', 'stageback', -600, -300);
	setScrollFactor('nube', 0.9, 0.9);
	scaleObject('nube', 1.1, 1.1);
	addLuaSprite('nube', false);

	var titulo = makeLuaText('titulo', 'FluxScript', 0, 0, 80);
	setTextSize(titulo, 40); // el objeto o el tag, como quieras
	setTextColor('titulo', 'FF3EA5');
	screenCenter(titulo, 'x');
	addLuaText(titulo);

	runTimer('ocultar', 3);
}

function onTimerCompleted(tag, loops, loopsLeft) {
	if (tag == 'ocultar')
		doTweenAlpha('chau', 'titulo', 0, 1, 'quadOut');
}

function onTweenCompleted(tag, vars) {
	if (tag == 'chau')
		removeLuaText('titulo');
}

function onBeatHit() {
	if (curBeat % 8 == 0)
		cameraShake('game', 0.004, 0.15);
}
