// Lo de Luau en FluxScript: task.wait, task.spawn, require, print, pcall, math...
// Va en mods/TuMod/scripts/ (todas las canciones) o en mods/TuMod/data/<canción>/.

// require: carga modules/cuenta.flux una sola vez y devuelve lo que exporta
var cuenta = require('modules/cuenta');
var aviso:FlxText;
var luces = null;

function onCreatePost() {
	aviso = makeText(0, 200, FlxG.width, '', 48);
	aviso.alignment = 'center';
	aviso.cameras = [camHUD];
	add(aviso);
	print('Canción:', PlayState.SONG.song, typeof(aviso)); // print('a', 'b') muestra "a b"
}

// task.wait espera ahí mismo, como en Luau: sin timers ni funciones adentro de funciones
function onSongStart() {
	for (n in cuenta.numeros(3)) {
		aviso.text = '$n';
		task.wait(0.5);
	}
	aviso.text = '¡Ya!';
	task.wait(1);
	aviso.text = '';
}

// task.spawn: una tarea que sigue sola hasta que se cancela
function onBeatHit() {
	if (curBeat == 16 && luces == null)
		luces = task.spawn(function() {
			while (true) {
				camGame.zoom += 0.03;
				task.wait(Conductor.crochet / 1000); // un beat
			}
		});
	if (curBeat == 64 && luces != null) {
		task.cancel(luces);
		luces = null;
	}
}

function goodNoteHit(note) {
	if (note.isSustainNote) return;
	// pcall atrapa los errores: devuelve [true, resultado] o [false, el error]
	var r = pcall(cuenta.puntos, combo);
	if (r[0] && r[1] > 0)
		addScore(r[1]);
}

function noteMiss(note) {
	warn('fallo número $misses'); // un aviso (en amarillo en Flux Engine)
	task.delay(0.3, function() health = math.clamp(health, 0.1, 2));
}
