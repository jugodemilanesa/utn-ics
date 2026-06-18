// Command server es el ejecutable de la app de demo: un servidor HTTP mínimo.
//
// Su rol en el pipeline:
//   - GET /health  -> permite el smoke test post-deploy (¿la app levantó?)
//   - GET /sum     -> expone la lógica pura calc.Sum por HTTP
//   - GET /        -> sirve la landing con Three.js (versión/commit visibles).
//     La versión es la "perilla visible" del deploy.
package main

import (
	"encoding/json"
	"html/template"
	"log"
	"net/http"
	"os"
	"strconv"

	"github.com/jugodemilanesa/utn-ics/internal/calc"
	"github.com/jugodemilanesa/utn-ics/web"
)

// version es la "perilla visible": al cambiarla, pushear y desplegar, se ve el
// cambio en producción => prueba de que el deploy llegó.
const version = "1.0.1"

// commit lo puede inyectar el pipeline en tiempo de build con linker flags:
//
//	go build -ldflags "-X main.commit=$(git rev-parse --short HEAD)" ./cmd/server
//
// En desarrollo local queda "dev". Es una técnica clave de CI: estampar el SHA del
// commit dentro del binario para saber exactamente qué versión está corriendo.
var commit = "dev"

// indexTmpl es la landing parseada una sola vez al iniciar (no en cada request).
// web.IndexHTML viene embebido en el binario (ver web/embed.go).
// template.Must envuelve el parseo: si el HTML tuviera un error de template, el
// programa no arranca (mejor fallar al inicio que en cada visita).
var indexTmpl = template.Must(template.New("index").Parse(web.IndexHTML))

func main() {
	// ServeMux es el router de la stdlib. Desde Go 1.22 entiende patrones con
	// método + ruta ("GET /health"), así que no hace falta una librería externa.
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", handleHealth)
	mux.HandleFunc("GET /sum", handleSum)
	mux.HandleFunc("GET /version", handleVersion)
	mux.HandleFunc("GET /", handleRoot) // catch-all: cualquier GET no matcheado arriba

	// Render (y casi todo PaaS) te dice en qué puerto escuchar vía la variable de
	// entorno PORT. Si no está (desarrollo local), usamos 8080 por defecto.
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	addr := ":" + port

	log.Printf("servidor escuchando en %s (versión %s)", addr, version)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal(err) // si el servidor no puede arrancar, fallamos fuerte
	}
}

// handleHealth es la sonda de salud. No solo dice "el proceso está vivo": valida la
// invariante crítica de negocio (que Sum funcione). Render hace polling a esta ruta
// DURANTE el deploy y solo switchea el tráfico a la versión nueva si responde 200;
// si no, deja viva la anterior (gate + rollback automático). Como Render reconstruye
// la imagen por su cuenta (el CI no la buildea), este check corre contra el artefacto
// REALMENTE desplegado y atraparía una divergencia entre lo que testeó el CI y lo que
// compiló Render. Si la invariante falla, devolvemos 503 (vivo pero NO apto para tráfico).
func handleHealth(w http.ResponseWriter, r *http.Request) {
	if !healthy() {
		http.Error(w, "unhealthy: invariante Sum rota", http.StatusServiceUnavailable)
		return
	}
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))
}

// healthy reporta si la app esta apta para servir trafico. Hoy valida la invariante
// de negocio (Sum); cuando haya dependencias (DB, etc.) se chequean aca. Es una var de
// funcion (no codigo inline) para que los tests puedan simular el caso unhealthy y
// verificar que el handler responde 503: asi el contrato "no sano -> 503" queda testeado.
var healthy = func() bool { return calc.Sum(2, 3) == 5 }

// handleVersion expone versión y commit como JSON. Es la pieza de TRAZABILIDAD: el
// smoke test post-deploy le pega para confirmar que el commit vivo en prod es el que
// se acaba de desplegar (no una versión cacheada ni un deploy que no tomó).
func handleVersion(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, map[string]string{"version": version, "commit": commitInfo()})
}

// handleSum parsea ?a=&b=, llama a la lógica pura y devuelve el resultado en JSON.
// Fijate que el handler NO suma: delega en calc.Sum. Acá solo hay traducción HTTP.
func handleSum(w http.ResponseWriter, r *http.Request) {
	a, errA := strconv.Atoi(r.URL.Query().Get("a"))
	b, errB := strconv.Atoi(r.URL.Query().Get("b"))
	if errA != nil || errB != nil {
		http.Error(w, `{"error":"los parámetros a y b deben ser enteros"}`, http.StatusBadRequest)
		return
	}
	writeJSON(w, map[string]int{"a": a, "b": b, "result": calc.Sum(a, b)})
}

// handleRoot sirve la landing animada con Three.js, inyectando versión y commit.
// Usa html/template, que escapa el contenido según el contexto (defensa contra
// inyección). Acá version/commit son strings simples, pero la práctica es correcta.
func handleRoot(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	data := struct {
		Version string
		Commit  string
	}{Version: version, Commit: commitInfo()}
	if err := indexTmpl.Execute(w, data); err != nil {
		http.Error(w, "error renderizando la página", http.StatusInternalServerError)
	}
}

// commitInfo resuelve el commit a mostrar, en orden de confiabilidad:
//  1. el valor inyectado por -ldflags al compilar (build-time, lo más fiable).
//  2. RENDER_GIT_COMMIT: Render lo setea en runtime con el SHA que efectivamente
//     construyó. Esto nos da trazabilidad commit->binario SIN tener que pasar el
//     build-arg COMMIT desde el Deploy Hook (que no lo soporta).
//  3. "dev" en desarrollo local.
//
// Se acorta a 7 caracteres (el short SHA convencional de git) para mostrar y comparar.
func commitInfo() string {
	c := commit
	if c == "dev" {
		if env := os.Getenv("RENDER_GIT_COMMIT"); env != "" {
			c = env
		}
	}
	if len(c) > 7 {
		c = c[:7]
	}
	return c
}

// writeJSON centraliza el seteo del Content-Type y la serialización, para no
// repetirlo en cada handler.
func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}
