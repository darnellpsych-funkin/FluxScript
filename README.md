<p align="center"><img src="docs/banner.png" alt="FluxScript" width="640"></p>

# FluxScript

Addon de HScript por **joaquinalonso**, exclusivo para el uso de FNF. Se piensa expandir a P-Slice Engine y muchos más.

FluxScript es el HScript de Psych Engine 1.0 ([hscript-iris](https://github.com/crowplexus/hscript-iris)) con cosas extra para hacer mods más rápido. Un `.hx` de Psych funciona igual en FluxScript, y todo lo nuevo es opcional.

Los scripts son archivos `.flux` (y `.fluxg` para los scripts globales).

| Engine | Estado |
|---|---|
| [Flux Engine](https://github.com/darnellpsych-funkin/FNF-FluxEngine) | Viene incluido: canciones, escenarios, personajes, eventos, menús y scripts globales |
| Psych Engine 1.0.4 | Se puede agregar (ver [Agregarlo a un engine](#agregarlo-a-un-engine)) |
| P-Slice Engine | Próximamente |

## Lo nuevo

### Clases sin `import`

Cualquier clase del juego se usa directo. Si un nombre que empieza con mayúscula no existe, FluxScript busca una clase con ese nombre en Flixel, OpenFL, Haxe y los paquetes de Psych (`backend`, `objects`, `states`, `substates`, `psychlua`...).

```haxe
var fondo = new FlxBackdrop(Paths.image('menuDesat'));
var icono = new HealthIcon('bf');
```

El `import` sigue funcionando igual, y uno de algo que no existe ya no corta el script: avisa y sigue.

### Los campos del juego directo

Los campos del estado del juego (el PlayState o el menú) se leen y se cambian sin `game.`:

```haxe
health = 2;
songScore += 100;
boyfriend.visible = false;
camHUD.alpha = 0.5;
```

Si el engine ya le dio al script una variable con ese nombre (como `curBeat`, `combo` o `misses` en Psych), se usa la variable. Para cambiar el valor del juego en esos casos, usa `game.` (`game.combo = 0`).

### Textos con variables

En las comillas simples, `$nombre` y `${expresión}` se reemplazan por su valor (como en Haxe). `$$` es un `$`. Las comillas dobles no cambian.

```haxe
texto.text = 'Beat $curBeat - vida ${Math.round(health * 50)}%';
```

### Varias funciones para el mismo evento: `on` y `off`

```haxe
on('beatHit', function() fondo.color = color('#FF66CC'));
on('beatHit', function() texto.text = 'Beat $curBeat');

function onBeatHit() { /* también se llama, como siempre */ }

off('beatHit'); // las quita todas (o off('beatHit', función) para una sola)
```

`'beatHit'` y `'onBeatHit'` son lo mismo. Si el script también tiene la función, se llaman todas.

### `shared`: datos que duran toda la partida

Lo comparten todos los FluxScript, y no se borra al cambiar de canción o de menú:

```haxe
shared.canciones = (shared.canciones ?? 0) + 1;
```

### `wait`, `every` y `color`

```haxe
wait(1.5, function() texto.visible = false);   // una vez, en 1.5 segundos
every(1, function() {                           // cada segundo...
	segundos++;
	return segundos < 10;                       // ...hasta que devuelva false
});
var rosa = color('#FF3EA5');                   // o color(0xFFFF3EA5), o FlxColor.PINK
```

`wait` y `every` devuelven el `FlxTimer` (se puede cancelar con `.cancel()`).

### La API de Lua de Psych

Las funciones de los `.lua` de Psych están con los mismos nombres y argumentos, así un script de Lua se pasa a FluxScript casi copiando:

- **Propiedades**: `getProperty`, `setProperty`, `getPropertyFromClass`, `setPropertyFromClass`, `getPropertyFromGroup`, `setPropertyFromGroup`, `callMethod`, `callMethodFromClass`, `getObjectOrder`, `setObjectOrder`.
- **Sprites**: `makeLuaSprite`, `makeAnimatedLuaSprite`, `makeGraphic`, `addLuaSprite`, `removeLuaSprite`, `luaSpriteExists`, `addAnimationByPrefix`, `addAnimationByIndices`, `addAnimation`, `playAnim`, `addOffset`, `scaleObject`, `setGraphicSize`, `updateHitbox`, `setScrollFactor`, `setObjectCamera`, `setBlendMode`, `screenCenter`, `objectsOverlap`, `getMidpointX`/`Y`, `getGraphicMidpointX`/`Y`, `getScreenPositionX`/`Y`.
- **Textos**: `makeLuaText`, `addLuaText`, `removeLuaText`, `luaTextExists`, `setTextString`, `getTextString`, `setTextSize`, `setTextWidth`, `setTextColor`, `setTextFont`, `setTextBorder`, `setTextAlignment`.
- **Tweens y timers**: `doTweenX`/`Y`/`Angle`/`Alpha`/`Zoom`/`Color`, `startTween`, `cancelTween`, `noteTweenX`/`Y`/`Angle`/`Alpha`/`Direction`, `runTimer`, `cancelTimer`.
- **Sonido**: `playSound`, `playMusic`, `stopSound`, `pauseSound`, `resumeSound`, `soundFadeIn`/`Out`, `setSoundVolume`, `getSoundVolume`, `setSoundTime`, `getSoundTime`, `luaSoundExists`, `precacheImage`/`Sound`/`Music`.
- **Cámaras**: `getCamera`, `cameraShake`, `cameraFlash`, `cameraFade`, `cameraSetTarget`.
- **Canción**: `characterPlayAnim`, `characterDance`, `startCountdown`, `endSong`, `restartSong`, `exitSong`, `getSongPosition`, `addScore`/`addMisses`/`addHits`, `setScore`/`setMisses`/`setHits`, `setHealth`, `addHealth`, `getHealth`, `setHealthBarColors`, `setTimeBarColors`, `triggerEvent`.
- **Otras**: `getColorFromHex`, `getRandomInt`, `getRandomFloat`, `getRandomBool`, `close`, y lo mismo que tiene un `.hx` de Psych (`game`, `setVar`/`getVar`/`removeVar`, `debugPrint`, `getModSetting`, `keyboardJustPressed`, `keyJustPressed`, `Function_Stop`...).

Diferencias con Lua, porque FluxScript sí puede guardar objetos:

- Donde va un tag también se puede pasar el objeto: `scaleObject(miSprite, 2, 2)`.
- `makeLuaSprite` y `makeLuaText` devuelven el objeto.
- `onTweenCompleted`, `onTimerCompleted` y `onSoundFinished` se llaman en el script que creó el tween, el timer o el sonido.
- `playSound(nombre, volumen, función)` también sirve con una función para cuando termina.

Los tags son los mismos que usan los `.lua` (`setVar`/`getVar`), así que un `.lua` y un `.flux` pueden usar los mismos sprites.

### Otros

- `importCode(código)`: ejecuta más código en el mismo script (comparten variables y funciones).
- `#if FLUXSCRIPT ... #end`, y `FLUXSCRIPT_VERSION` con la versión.
- `for (x in lista)` con una lista `null` no hace nada (en vez de cortar el script).
- `this` es el script: `this.close()` lo apaga.
- `scriptName` es la ruta del archivo, y `trace(...)` muestra el nombre del script y la línea.
- `FlxColor`, `FlxPoint`, `FlxAxes`, `FlxTextAlign`, `FlxTweenType` y `BlendMode` funcionan aunque en Haxe sean abstracts.
- Los errores dicen el archivo y la línea, y un error dentro de una función no apaga el script.

## En Flux Engine

- **Canciones**: `mods/TuMod/scripts/` (todas las canciones), `data/<canción>/`, `stages/`, `characters/`, `custom_notetypes/` y `custom_events/`, igual que los `.hx`. Reciben los mismos callbacks (`onCreate`, `onCreatePost`, `onUpdate`, `onBeatHit`, `goodNoteHit`, `onEvent`...).
- **Menús**: `mods/TuMod/states/MainMenuState.flux` (o el menú que sea). `switchState('MiMenu')` abre `states/MiMenu.flux` como un menú propio.
- **Globales**: un `.fluxg` en `mods/TuMod/scripts/`, o un `.flux` en `mods/TuMod/scripts/global/`. Corren siempre, en todos los menús y canciones, sin reiniciarse.
- Además tienen todo el preset de los `.hxs` de Flux (`makeText`, `makeSprite`, `tween`, `timer`, `switchState`, `importScript`...).
- Desde Lua: `runFluxScript(código, ?función, ?argumentos)`, `addFluxScript('scripts/algo.flux')` y `runFluxFunction('fluxscript', función, argumentos)`.

## Ejemplos

En [`examples/`](examples) (para Flux Engine):

- [`scripts/ejemplo.flux`](examples/scripts/ejemplo.flux): lo nuevo de FluxScript en una canción.
- [`scripts/estilo-lua.flux`](examples/scripts/estilo-lua.flux): la API de Lua de Psych.
- [`scripts/global/contador.flux`](examples/scripts/global/contador.flux): un script global.
- [`states/MainMenuState.flux`](examples/states/MainMenuState.flux): un script del menú principal.

## Agregarlo a un engine

Necesita `hscript-iris` (Psych 1.0 ya lo trae) y Flixel. `fluxscript.psych.FluxPsych` está hecho para Psych Engine 1.0.4. Con `-D hscriptPos` (Psych ya lo tiene) los errores dicen la línea.

1. Copia `src/fluxscript` a la carpeta `source/` del engine (así lo hace Flux Engine), o instálalo con `haxelib git fluxscript https://github.com/darnellpsych-funkin/FluxScript` y agrega `<haxelib name="fluxscript" />` en `Project.xml`.
2. Crea los scripts y llama sus funciones:

```haxe
import fluxscript.FluxScript;
import fluxscript.psych.FluxPsych;

var script:FluxScript = FluxScript.fromFile('mods/MiMod/scripts/hola.flux', FlxG.state);
script.modFolder = 'MiMod';
FluxPsych.apply(script); // Psych 1.0 y sus forks (en otros engines: fluxscript.FluxFlixel.apply)
if (script.execute())
	script.call('onCreate');

// en cada callback del juego
script.call('onUpdate', [elapsed]);
if (script.call('onPause') == LuaUtils.Function_Stop) { /* ... */ }

// al salir
script.destroy();
```

Más cosas para el engine:

- `script.exists('onUpdate')`, `script.set('nombre', valor)`, `script.get('nombre')` y `script.parent = nuevoEstado`.
- `script.onError` / `script.onWarning` (o `FluxScript.defaultErrorHandler` / `defaultWarningHandler` para todos): dónde mostrar los errores y avisos.
- `script.onClose`: se llama cuando el script hace `close()`.
- `FluxScript.defines.set('MI_ENGINE', true)`: para `#if MI_ENGINE` en los scripts.
- `FluxClasses.addPackage('mi.paquete.')` y `FluxClasses.alias('Nombre', valor)`: más clases para usar sin `import`.
- `FluxClasses.resolver`: el equivalente de los `import` de otros engines (por ejemplo `funkin.game.PlayState` de Codename).
- `FluxScript.checkSyntax(código, nombre)`: revisa el código sin ejecutarlo (null si está bien, o el error).

Ojo con el "sin `import`": una clase que el juego no usa en ninguna parte no queda en el ejecutable, así que tampoco se puede usar desde un script.

## Código

- `src/fluxscript/FluxScript.hx`: el script (cargar, ejecutar, llamar funciones, `on`, `shared`...).
- `src/fluxscript/FluxInterp.hx` y `FluxParser.hx`: el intérprete y el parser de hscript-iris con los agregados.
- `src/fluxscript/FluxSyntax.hx`: los textos con variables.
- `src/fluxscript/FluxClasses.hx`: las clases sin `import`.
- `src/fluxscript/FluxFlixel.hx`: lo de Flixel (`FlxColor`, `wait`, `every`, `color`...).
- `src/fluxscript/psych/FluxPsych.hx`: lo de Psych Engine 1.0 (la API de Lua y el preset de los `.hx`).

## Pruebas

```
cd test
haxe test.hxml
```

Prueban lo nuevo de FluxScript sin Flixel y que los ejemplos se lean bien. `haxe test-cpp.hxml` hace lo mismo en C++.

## Créditos

- FluxScript: joaquinalonso.
- [hscript-iris](https://github.com/crowplexus/hscript-iris) de crowplexus, el HScript de Psych Engine 1.0.
- [Psych Engine](https://github.com/ShadowMario/FNF-PsychEngine) de ShadowMario y su equipo: los nombres y el comportamiento de la API de Lua.
- [HaxeFlixel](https://haxeflixel.com).
