# Estado de implementacion

Resumen de que esta hecho y donde retomar. Fecha de corte: 2026-06-17.
Para el diseno completo ver `plan.md`.

## Que esta implementado y funcionando

### Repositorio / VCS
- Repo git en GitHub: `jugodemilanesa/utn-ics` (publico). Rama principal: **`master`**.
- Identidad git local: `jugodemilanesa` + noreply (ver CLAUDE.md). Sin co-autoria en commits.

### App de demo (Go) - las 4 piezas completas
- `internal/calc/sum.go` + `sum_test.go`: funcion pura `Sum` con tests table-driven (100% cobertura).
- `cmd/server/main.go`: servidor HTTP con `GET /` (landing), `GET /health`, `GET /sum?a=&b=`. Lee `PORT`.
- `web/index.html` + `web/embed.go`: landing animada con Three.js, embebida con `//go:embed`. Muestra version y commit.
- `Dockerfile` multi-stage (build `cimg`/golang -> runtime `scratch`) + `.dockerignore`. Build local verificado.
- `go.mod`: directiva `go 1.22` (sin patch, por compatibilidad con CircleCI).

### Entorno de entrega (Render)
- Servicio web vivo: **https://utn-ics.onrender.com** (free tier, duerme a los 15 min).
- **Auto-Deploy: OFF** -> deploya solo cuando CircleCI le pega al Deploy Hook.
- Deploy Hook obtenido y cargado como secreto en CircleCI (ver abajo).
- La imagen Docker la construye Render desde el `Dockerfile` (CircleCI no la construye).

### Calidad (SonarCloud)
- Proyecto creado, Automatic Analysis apagado (usamos CI-based).
- `sonar-project.properties` en el repo (org + projectKey confirmados, cobertura via `coverage.out`).
- Analisis corriendo dentro del pipeline (job `sonar`), verde.

### Servidor de IC (CircleCI)
- Proyecto conectado al repo. Pipeline versionado en `.circleci/config.yml`.
- Tres jobs:
  - `validar` (`cimg/go:1.22`): gofmt, `go vet`, `go build`, `go test -coverprofile`. Persiste workspace.
  - `sonar` (`sonar-scanner-cli`): corre `sonar-scanner` sobre el workspace. `requires: validar`, `context: sonarcloud`.
  - `deploy` (`cimg/base`): curl al Deploy Hook de Render + smoke test a `/health`. `requires: validar + sonar`, `filters: branches only master`.
- Modelo demostrado de punta a punta:
  - Camino VERDE: cambio valido -> validar + sonar OK -> deploy a Render.
  - Camino ROJO: romper `Sum` -> `validar` falla -> sonar y deploy se saltan -> NO se deploya (Quality Gate OK).

### Secretos cargados en CircleCI
- Context `sonarcloud`: `SONAR_TOKEN`.
- Project Env Var: `RENDER_DEPLOY_HOOK_URL`.

## Que FALTA (donde retomar)

1. **Feedback a Telegram + Trello** (la ultima pieza del diagrama):
   - Crear bot de Telegram (obtener `TELEGRAM_TOKEN`, `TELEGRAM_CHAT_ID`).
   - Crear tablero Trello (obtener `TRELLO_KEY`, `TRELLO_TOKEN`, IDs de listas).
   - Cargar esos secretos como Project Env Vars en CircleCI.
   - Agregar al `deploy` (y a un manejo de fallo) los `curl` de notificacion:
     - steps con `when: on_success` / `when: on_fail`.
     - Mover tarjeta de Trello segun resultado.
   - Plantillas curl ya estan en `plan.md` seccion 8.

2. **Verificar el estado actual de `master`**: la ultima prueba dejo `Sum` roto (`a - b`)
   para demostrar el camino rojo. Confirmar que se revirtio a `a + b` y que `master`
   quedo verde con `version = "1.0.1"` deployado.

## Backlog de mejoras (priorizado)

Orden sugerido para retomar: 1 (pendiente) -> 2 -> 3.

### 1. Feedback a Telegram + Trello (pendiente principal)
Ver detalle arriba en "Que FALTA". Es la ultima pieza del diagrama.

### 2. Estrategia de branches + branch protection
El `.circleci/config.yml` ya filtra el `deploy` a `master`; falta la disciplina + proteccion:
- GitHub Flow: dejar de commitear directo a `master`. Trabajar en ramas `feature/...`,
  PR a `master`, merge. Push a feature -> solo `validar` + `sonar` (sin deploy).
  Merge a `master` -> recien ahi `deploy`. El deploy pasa a ser deliberado, no por commit.
- Branch protection en GitHub (Settings -> Branches): exigir que el check de CircleCI
  pase antes de mergear (+ review opcional). Mueve el Quality Gate al nivel de GitHub.

### 3. No correr/desperdiciar en cada commit
- `[skip ci]` en el mensaje del commit para cambios triviales (CircleCI lo respeta).
- Filtrado por path: que cambios solo a `docs/**` o `*.md` no disparen el pipeline pesado.
- Cache de Go (modulo + build cache) entre corridas -> mas rapido, menos creditos.

### 4. Quality Gate de Sonar que bloquee de verdad
Hoy el job `sonar` pasa apenas sube el analisis; NO espera el veredicto del gate.
Agregar `sonar.qualitygate.wait=true` para que el job falle si el gate falla.
Agujero de correctitud real: hoy Sonar no frena nada. (Alto valor, bajo esfuerzo.)

### 5. Inyectar el commit SHA real en el binario
Hoy el badge "commit" dice `dev`. Pasar `COMMIT` como build-arg a Render (o leer
`RENDER_GIT_COMMIT` en runtime). Permite que el smoke test verifique la version nueva.

### 6. Tests de los handlers HTTP (`httptest`)
Hoy `cmd/server` tiene 0% de cobertura; solo `Sum` esta testeada. Sumar tests de
`/health` y `/sum` sube cobertura y atrapa regresiones del servidor.

### 7. `govulncheck` en el pipeline
Escaneo de vulnerabilidades conocidas de Go. Encaja con el "DevSecOps" del plan.

### 8. Entorno de staging / preview por PR
Render preview environments: deployar el PR a un entorno aparte antes de prod.
Es el "Pruebas vs Produccion" del diagrama, que hoy esta colapsado en uno.

### 9. Mantener viva la app
Cron o UptimeRobot que pingee `/health` cada ~10 min para que el free tier no la
duerma. Smoke tests y demos mas confiables.

## Extensiones opcionales (fuera de alcance, ver plan.md seccion 10)
- Inyectar el SHA real del commit en el binario (hoy el badge "commit" dice `dev`).
- Smoke test que verifique la version nueva via API de Render (hoy solo liveness).
- Rollback automatico, entorno de staging, Postgres con migraciones.

## Datos utiles
- URL app: https://utn-ics.onrender.com  (`/`, `/health`, `/sum?a=2&b=3`)
- Repo: https://github.com/jugodemilanesa/utn-ics
- Comandos: `go test ./...`, `go run ./cmd/server`, `docker build -t utn-ics .`
