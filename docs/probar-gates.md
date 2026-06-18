# Como romper cada gate a proposito (guia de pruebas)

Catalogo de los gates que traban la pipeline, con el cambio MINIMO para disparar cada
uno, como verlo y como deshacerlo. Sirve para entender la pipeline y para la demo del TP.

Hay **tres niveles** donde probar, de mas barato/seguro a mas caro/riesgoso:

1. **Local** — instantaneo, cero riesgo. La mayoria de los gates se reproducen aca.
2. **PR descartable** — abris un PR que NUNCA mergeas; ves el check rojo y el merge bloqueado.
3. **Deploy (fire-drill)** — solo en master; rompe prod a proposito, con las redes (health
   gate + rollback) puestas. Se hace deliberadamente y mirandolo.

Regla de oro para limpiar despues de cualquier prueba LOCAL (sin commitear):
```
git restore .            # descarta cambios en archivos trackeados
git clean -fd            # borra archivos nuevos sin trackear (ej. el archivo con el secreto falso)
```

---

## Nivel 1 / 2 — Gates de CI

Todos se ven **local** con un comando; si ademas los metes en un PR, ves el check rojo y
`mergeState BLOCKED` (branch protection). Atajo: `make check` corre gofmt+vet+build+test+govulncheck.

### gofmt (block Validate)
- **Que chequea:** que el codigo este formateado (`gofmt`).
- **Donde / que:** en cualquier `.go`, metele indentacion con espacios en vez de tab, o
  espacios al final de una linea.
- **Verlo:** `gofmt -l .` (lista el archivo) o `make check`.
- **Deshacer:** `make fmt` (o `git restore`).

### go vet (block Validate)
- **Que chequea:** construcciones sospechosas que compilan pero casi seguro son bugs.
- **Donde / que:** en `cmd/server/main.go`, agregale un `Printf` con verbo mal:
  ```go
  log.Printf("puerto %d", addr)   // addr es string, %d espera int
  ```
- **Verlo:** `go vet ./...` o `make check`.
- **Deshacer:** `git restore cmd/server/main.go`.

### go build (block Validate)
- **Que chequea:** que compile.
- **Donde / que:** en cualquier `.go`, usa una variable que no existe (ej. `_ = noExiste`).
- **Verlo:** `go build ./...` o `make check`.

### go test (block Validate) — el "camino rojo" clasico
- **Que chequea:** que pasen los tests.
- **Donde / que:** en `internal/calc/sum.go`, cambia el cuerpo de `Sum`:
  ```go
  func Sum(a, b int) int {
      return a - b   // antes: a + b
  }
  ```
- **Verlo:** `go test ./...` (falla `sum_test.go`) o `make check`.
- **Nota:** este es el cambio que se uso para demostrar el camino rojo (check rojo →
  merge bloqueado). Si ademas tocas el test para que "pase", ver el fire-drill de deploy.

### govulncheck (block Security)
- **Que chequea:** vulnerabilidades conocidas (CVEs) de la stdlib y deps que el codigo alcanza.
- **Donde / que:** en `go.mod`, volve a una version EOL de Go (sin parches):
  ```
  go 1.22
  ```
  y borra la linea `toolchain go1.25.11`.
- **Verlo:** `make vuln` → reporta ~29 vulns de la stdlib de 1.22.
- **Deshacer:** `git restore go.mod`.

### gitleaks (block Security)
- **Que chequea:** secretos (tokens, claves) que se hayan colado a algun archivo del repo.
- **Donde / que:** crea un archivo cualquiera con un secreto de juguete (NO lo commitees):
  ```
  printf 'github_token = "ghp_0123456789abcdef0123456789abcdef0123"\n' > leak-test.txt
  ```
- **Verlo:** `make secrets` → gitleaks lo marca (regla de GitHub PAT) y sale != 0.
- **Deshacer:** `rm leak-test.txt`.

### Sonar — Quality Gate: cobertura de codigo nuevo (block Sonar)
- **Que chequea:** que el codigo NUEVO de la rama tenga >= 80% de cobertura.
- **Donde / que:** agrega una funcion nueva SIN test. En `internal/calc/sum.go`:
  ```go
  // Mul no tiene test a proposito: baja la cobertura de codigo nuevo.
  func Mul(a, b int) int { return a * b }
  ```
- **Verlo:** SOLO en un PR (el analisis necesita SonarCloud). El check
  `SonarCloud Code Analysis` queda rojo con `new_coverage < 80%`. Consultable por API:
  ```
  curl -s "https://sonarcloud.io/api/qualitygates/project_status?projectKey=jugodemilanesa_utn-ics&pullRequest=<N>"
  ```
- **Deshacer:** borrar la funcion (o agregarle un test).

### Sonar — Quality Gate: duplicacion (block Sonar)
- **Que chequea:** que el codigo nuevo no tenga > 3% de lineas duplicadas.
- **Donde / que:** copia y pega un bloque de ~20 lineas identicas (ej. duplica un handler
  entero con otro nombre).
- **Verlo:** en un PR, `new_duplicated_lines_density > 3`.
- **Deshacer:** borrar la copia.

---

## Nivel 3 — Gates del Deploy

El deploy corre **solo en master, post-merge**. El smoke (`scripts/smoke.sh`) tiene tres
chequeos y cada uno es un gate: liveness (`/health`), correctitud (`/sum`), trazabilidad
(`/version`). Ademas estan el **health-check gate de Render** y el **rollback automatico**.

### Ensayo SEGURO (local, sin tocar prod)

`smoke.sh` es el mismo script que corre el deploy. Ensayalo contra un server local:
```
make run                                               # en otra terminal: levanta localhost:8080
bash scripts/smoke.sh http://localhost:8080                 # pasa
bash scripts/smoke.sh http://localhost:8080 deadbeef        # FALLA en /version (mismatch de commit)
```
Para ensayar la falla de `/sum` o `/health` local, rompe el handler (ver abajo), corre
`make run` y apunta el smoke a localhost. Reproduce el gate sin riesgo de prod.

### Fire-drill REAL (rompe prod a proposito, con red)

Esto ejercita deploy gate + rollback de punta a punta. **Importante:** despues hay que
restaurar master con un revert PR (ver `runbook-incidentes.md`). El truco es que el CI tiene
que pasar (si no, no llega a deployar), asi que hay que ajustar tambien el test
correspondiente — eso muestra justamente que el smoke es un gate INDEPENDIENTE de los unit tests.

**Variante A — el health gate retiene la version vieja (rollback "no degrada"):**
1. En `internal/calc/sum.go`: `return a + b + 1`.
2. En `internal/calc/sum_test.go`: ajusta los esperados para que el test pase con la nueva logica.
3. PR → merge. En el deploy: `/health` da 503 (porque `Sum(2,3)=6 != 5`) → Render **no
   switchea** el trafico y deja viva la version anterior → el smoke ve `/version` con el
   commit viejo → falla por mismatch → `rollback-render.sh` detecta "el gate ya retuvo la
   buena, no degrado" y manda la alerta a Telegram.
4. Restaurar: revert PR.

**Variante B — rollback REAL via API (el que llama a Render):**
1. En `cmd/server/main.go`, en `handleSum`, devolve mal el resultado:
   ```go
   writeJSON(w, map[string]int{"a": a, "b": b, "result": calc.Sum(a, b) + 1})
   ```
2. En `cmd/server/main_test.go`, ajusta `TestHandleSumOK` para que espere `6` (asi el CI pasa).
3. PR → merge. En el deploy: `/health` queda OK (Sum sigue bien) → la version nueva se
   promueve → pero el smoke `/sum?a=2&b=3` espera `result:5` y recibe `6` → falla → el
   epilogue `on_fail` dispara `rollback-render.sh`, que esta vez SI llama a la API de Render
   y revierte al deploy anterior + alerta a Telegram con el comando de revert.
4. Restaurar: revert PR.

**Punto honesto:** los gates de deploy no se "testean" rompiendo prod en el dia a dia; para
eso estan el health gate y el rollback. Se ensayan local con `smoke.sh`, y el fire-drill real
se hace una vez, deliberadamente, sabiendo que las redes te cubren.

---

## Branch protection (GitHub)

No es un gate aparte: es lo que convierte un check rojo en "no se puede mergear". Con
cualquiera de los gates de CI roto en un PR, el PR queda `mergeState BLOCKED` (require PR +
los 3 checks requeridos + `enforce_admins=true`). Se ve con:
```
gh pr view <N> --json mergeStateStatus,statusCheckRollup
```
