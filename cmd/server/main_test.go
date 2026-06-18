// Tests de los handlers HTTP con httptest: levantan el handler en memoria (sin abrir
// un puerto real) y verifican status code y cuerpo. Cubren cmd/server, que antes
// tenía 0% de cobertura (solo calc.Sum estaba testeada).
package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// doGet ejercita un handler con un GET a target y devuelve el recorder con la respuesta.
func doGet(handler http.HandlerFunc, target string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, target, nil)
	rec := httptest.NewRecorder()
	handler(rec, req)
	return rec
}

func TestHandleHealth(t *testing.T) {
	rec := doGet(handleHealth, "/health")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, quería %d", rec.Code, http.StatusOK)
	}
	if body := strings.TrimSpace(rec.Body.String()); body != "ok" {
		t.Fatalf("body = %q, quería %q", body, "ok")
	}
}

func TestHandleSumOK(t *testing.T) {
	rec := doGet(handleSum, "/sum?a=2&b=3")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, quería %d", rec.Code, http.StatusOK)
	}
	var got map[string]int
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("respuesta no es JSON válido: %v (body=%q)", err, rec.Body.String())
	}
	if got["result"] != 5 {
		t.Fatalf("result = %d, quería 5 (body=%q)", got["result"], rec.Body.String())
	}
}

func TestHandleSumBadInput(t *testing.T) {
	// a no es un entero -> el handler debe responder 400, no 500 ni 200.
	rec := doGet(handleSum, "/sum?a=x&b=3")
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, quería %d", rec.Code, http.StatusBadRequest)
	}
}

func TestHandleVersion(t *testing.T) {
	rec := doGet(handleVersion, "/version")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, quería %d", rec.Code, http.StatusOK)
	}
	var got map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("respuesta no es JSON válido: %v (body=%q)", err, rec.Body.String())
	}
	if got["version"] != version {
		t.Fatalf("version = %q, quería %q", got["version"], version)
	}
	if got["commit"] == "" {
		t.Fatal("commit vacío; esperaba al menos 'dev'")
	}
}

func TestHandleRoot(t *testing.T) {
	rec := doGet(handleRoot, "/")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, quería %d", rec.Code, http.StatusOK)
	}
	if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "text/html") {
		t.Fatalf("Content-Type = %q, quería text/html", ct)
	}
	// La landing debe traer la versión inyectada por la plantilla.
	if !strings.Contains(rec.Body.String(), version) {
		t.Fatalf("la landing no contiene la versión %q", version)
	}
}

func TestCommitInfoFallbackRender(t *testing.T) {
	// Con commit en "dev" (no inyectado por ldflags), debe caer a RENDER_GIT_COMMIT
	// y acortarlo a 7 caracteres.
	t.Setenv("RENDER_GIT_COMMIT", "abcdef1234567890")
	if got := commitInfo(); got != "abcdef1" {
		t.Fatalf("commitInfo() = %q, quería %q", got, "abcdef1")
	}
}
