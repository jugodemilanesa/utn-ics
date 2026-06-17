// Package web embebe los assets estáticos (la landing) dentro del binario.
//
// Existe por la limitación de //go:embed: solo puede embeber archivos de su propia
// carpeta o subcarpetas, nunca de carpetas hacia arriba (".."). Como main.go vive en
// cmd/server/ y no puede alcanzar este web/, ponemos el embed acá y main lo importa.
package web

// El import en blanco habilita la directiva //go:embed sin usar el paquete embed
// directamente (porque embebemos en un string, no en un embed.FS).
import _ "embed"

// IndexHTML es el contenido de index.html, horneado en el binario al compilar.
//
//go:embed index.html
var IndexHTML string
