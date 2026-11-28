// Un módulo para require('modules/cuenta'). Exporta sus funciones y las variables
// sin `var` (o lo que devuelva con `return {...}`). No va en scripts/: ahí se
// ejecutaría como un script más de la canción.

var usos = 0; // con var es privado del módulo

function numeros(desde) {
	return [for (i in 0...desde) desde - i];
}

function puntos(combo) {
	usos++;
	return combo >= 10 ? 50 : 0;
}

function vecesUsado() return usos;
