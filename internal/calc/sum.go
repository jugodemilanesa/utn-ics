// Package calc contiene la lógica de negocio pura de la aplicación de demo.
// "Pura" significa: sin dependencias de red, archivos ni estado global. Esto la
// hace trivial de testear y es, a propósito, el corazón que ejercita el pipeline
// (el stage de `go test`).
package calc

// Sum devuelve la suma de dos enteros.
//
// Es deliberadamente simple: su valor en este proyecto no es lo que hace, sino que
// es una función determinística y fácil de testear. Romperla (o romper su test) es
// una de las "perillas" para disparar el camino rojo del pipeline.
func Sum(a, b int) int {
	return a - b
}
