// FluxScript (.flux): se escribe como un .hx de Psych, con cosas extra.
// Va en mods/TuMod/scripts/ (todas las canciones) o en mods/TuMod/data/<canción>/.

var fondo = new FlxBackdrop(Paths.image('menuDesat')); // sin import
var texto:FlxText;

function onCreatePost() {
	fondo.alpha = 0.12;
	fondo.velocity.set(40, 20);
	fondo.cameras = [camHUD]; // camHUD es del juego: se usa directo, sin "game."
	insert(0, fondo);

	texto = makeText(20, 140, 0, '', 24);
	texto.cameras = [camHUD];
	add(texto);

	// shared: lo comparten todos los FluxScript y dura toda la partida
	shared.canciones = (shared.canciones ?? 0) + 1;
}

// on(): varias funciones para el mismo evento, sin pisarse
on('beatHit', function() {
	if (curBeat % 4 == 0)
		fondo.color = color('#FF66CC');
});
on('beatHit', function() {
	// textos con variables: $nombre y ${expresión}
	texto.text = 'Beat $curBeat - canción ${shared.canciones} de la sesión';
});

function goodNoteHit(note) {
	if (note.isSustainNote) return;
	health += 0.005; // cambia la vida del juego directo
	if (combo > 0 && combo % 50 == 0)
		cameraFlash('hud', 'FFFFFF', 0.3);
}

function noteMiss(note) {
	texto.text = '¡Uy! $misses fallos';
	wait(0.6, function() texto.text = ''); // como un timer, pero más corto de escribir
}
