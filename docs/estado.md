# Estado de implementacion

Resumen de que esta hecho y donde retomar. Fecha de corte: 2026-06-18.
Para el diseno completo ver `plan.md`.

## Que esta implementado y funcionando

### Repositorio / VCS
- Repo git en GitHub: `jugodemilanesa/utn-ics` (publico). Rama principal: **`master`**.
- Identidad git local: `jugodemilanesa` + noreply (ver CLAUDE.md). Sin co-autoria en commits.
- Modelo trunk-based: `master` protegida (sin push directo); cada cambio entra por PR.

### App de demo (Go) - las 4 piezas completas
- `internal/calc/sum.go` + `sum_test.go`: funcion pura `Sum` con tests table-driven (100% cobertura).
- `cmd/server/main.go`: servidor HTTP con `GET /` (landing), `GET /health`, `GET /sum?a=&b=`. Lee `PORT`.
- `web/index.html` + `web/embed.go`: landing con fondo Three.js (sin build step), embebida con `//go:embed`. Incluye un **sumador funcional** (inputs a + b → boton → resultado) que le pega al endpoint real `GET /sum` y muestra el resultado. Muestra version y commit.
- `Dockerfile` multi-stage (build `golang:1.22-alpine` → runtime `scratch`) + `.dockerignore`. Build local verificado.
- `go.mod`: directiva `go 1.22`. Sin dependencias externas (solo stdlib), por eso no hay `go.sum`.

### Entorno de entrega (Render)
- Servicio web vivo: **https://utn-ics.onrender.com** (free tier, duerme a los 15 min).
- **Auto-Deploy: OFF** → deploya solo cuando el CI (Semaphore) le pega al Deploy Hook.
- Deploy Hook cargado como secreto `render` en Semaphore (ver abajo).
- La imagen Docker la construye Render desde el `Dockerfile` (el CI no la construye).

### Calidad (SonarCloud)
- Proyecto creado, Automatic Analysis apagado (usamos CI-based).
- `sonar-project.properties` en el repo (org + projectKey confirmados, cobertura via `coverage.out`).
- **Quality Gate bloqueante**: `sonar.qualitygate.wait=true` → el scanner espera el veredicto y
  falla el block si el gate falla (antes pasaba apenas subia el analisis; ya no es decorativo).

### Servidor de IC (Semaphore)
Proyecto conectado al repo. Pipeline versionado en `.semaphore/`. Migrado desde CircleCI el
2026-06-18 (motivo: expone `SEMAPHORE_GIT_PR_NUMBER` nativo, que habilita Sonar en modo PR).
Machine type **`f1-standard-2`** / `ubuntu2204` (la org solo ofrece F1 x86 y R1 ARM).

- **`semaphore.yml`** (pipeline de CI). Triggers: push **y** pull request, ambos prendidos. Para
  no duplicar trabajo, cada block se asigna a un solo tipo de pipeline via `run/when`:
  - Block **Validate** (`run.when: "pull_request !~ '.*'"`): gofmt, `go vet`, `go build`,
    `go test -coverprofile`. Corre en **todo build de push** (cualquier rama + master, incluso
    sin PR abierto) y se skipea en el build de PR. → hay tests en cada push.
  - Block **Sonar** (`run.when: "branch = 'master' OR pull_request =~ '.*'"`): corre en build
    de PR (modo PR, con `$SEMAPHORE_GIT_PR_NUMBER` nativo) o push a master (modo main). En una
    rama feature queda skippeado (en modo branch daria 403 del free tier de SonarCloud).
  - `fail_fast: stop` y `auto_cancel: running` (en ramas != master).
- **`deploy.yml`** (pipeline de deploy, por **promotion**). `auto_promote` cuando
  `result = 'passed' AND branch = 'master' AND pull_request !~ '.*'`. Le pega al Deploy Hook de
  Render + **smoke test funcional** (`scripts/smoke.sh`: liveness `/health` + correctitud `/sum`).
  El filtro `pull_request !~` evita un deploy desde un build de
  PR (en un PR, `SEMAPHORE_GIT_BRANCH = master` porque es la rama destino); ademas hay un guard
  de runtime en el job que sale si `SEMAPHORE_GIT_REF_TYPE = pull-request`.

Modelo demostrado de punta a punta:
- Camino VERDE: cambio valido → Validate + Sonar OK → (al mergear a master) deploy a Render.
- Camino ROJO: romper `Sum` → Validate falla → check rojo → branch protection bloquea el merge
  (mergeState BLOCKED) → NO se deploya.

### Branch protection en master (GitHub, via API)
- Require PR, 0 approvals, `enforce_admins=true`, sin push directo.
- Checks requeridos (los tres): **`ci/semaphoreci/push: CI utn-ics`** (gatea tests, del build de
  push) + **`ci/semaphoreci/pr: CI utn-ics`** (gatea Sonar, del build de PR) +
  **`SonarCloud Code Analysis`**.

### Feedback / Alertas (Telegram)
- Notificaciones a Telegram desde el pipeline, via `after_pipeline` (corre siempre, incluso si
  un job fue cancelado por `fail_fast`) + el script `.semaphore/scripts/notify-telegram.sh`.
- Avisa: deploy `EXITO`/`FALLA`, CI roto en master, y resultado del pipeline de PR. Verificado e2e.
- El script tiene tests locales (`test-notify-telegram.sh`, dry-run) y nunca rompe el build.
- Trello (la otra mitad del mecanismo de alertas) queda pendiente; ver "Que FALTA".

### Secretos cargados en Semaphore
- Secret `sonarcloud`: `SONAR_TOKEN`.
- Secret `render`: `RENDER_DEPLOY_HOOK_URL`.
- Secret `telegram`: `TELEGRAM_TOKEN`, `TELEGRAM_CHAT_ID`.

### Tooling de desarrollo (local)
- `Makefile` como puerta de entrada (`make help` lista todo). Targets: `check` (espejo del block
  Validate: gofmt/vet/build/test + tests del script de notificacion), `fmt`, `run` (go run),
  `build` (imagen Docker), `docker-run` (build + corre el contenedor local, como Render), `smoke`.
- `scripts/check.sh`: corre local lo mismo que gatea el CI → feedback antes de pushear.
- `scripts/smoke.sh <url>`: smoke funcional. Lo usa `deploy.yml` contra Render y se corre local
  contra `go run`/`docker run`. Una sola logica de smoke, en CI y en local.

## Que FALTA (donde retomar)

**Feedback a Trello** (lo que resta del "Mecanismo de Alertas"; Telegram ya esta hecho):
- Crear tablero Trello (obtener `TRELLO_KEY`, `TRELLO_TOKEN`, IDs de listas).
- Cargar esos secretos como **Secret de Semaphore** y referenciarlo en el `after_pipeline`.
- Decidir el modelo: crear una tarjeta por evento (feed) vs mover una tarjeta fija entre listas.
- Reutiliza el patron de `notify-telegram.sh` (after_pipeline + script). Plantilla curl en
  `plan.md` seccion 8.

## Backlog de mejoras (priorizado)

### 1. Pinear la imagen del scanner
`docker run ... sonarsource/sonar-scanner-cli` corre sin tag → resuelve a `latest`. Un `latest`
con un cambio incompatible rompe el CI sin que toques nada. Pinear a una version fija = builds
reproducibles. Bajo esfuerzo.

### 2. Extraer el bash de Sonar a un script versionado
El block Sonar tiene la logica de modo (PR vs main) embebida en el YAML. Moverla a
`.semaphore/scripts/sonar.sh` permite correrla local y pasarle `shellcheck`. YAML fino, logica
testeable.

### 3. `govulncheck` en el pipeline
Escaneo de vulnerabilidades conocidas de Go (incluye CVEs de la stdlib de la version usada).
Encaja con el "DevSecOps" del plan. Opcional sumar `staticcheck`.

### 4. Inyectar el commit SHA real en el binario
Hoy el badge "commit" dice `dev`. El `Dockerfile` ya acepta `ARG COMMIT` con `-ldflags`; falta
pasarlo desde Render (o leer `RENDER_GIT_COMMIT` en runtime). Permitiria que el smoke test ademas
verifique la **version** desplegada (hoy ya chequea `/health` y `/sum`, pero no la version).

### 5. Tests de los handlers HTTP (`httptest`)
Hoy `cmd/server` tiene 0% de cobertura; solo `Sum` esta testeada. Sumar tests de `/health` y
`/sum` sube cobertura y atrapa regresiones del servidor.

### 6. No correr/desperdiciar en cambios triviales
`change_in('/', {exclude: ['/docs', ...]})` para que cambios solo-docs no disparen el pipeline
pesado. Ojo: footgun con branch protection (un check requerido que se skipea puede dejar el PR en
"pending" para siempre); hay que probarlo con cuidado. Cache de Go: NO aplica (cero dependencias).

### 7. Entorno de staging / preview por PR
Render preview environments: deployar el PR a un entorno aparte antes de prod. Es el
"Pruebas vs Produccion" del diagrama, que hoy esta colapsado en uno.

### 8. Mantener viva la app
Cron o UptimeRobot que pingee `/health` cada ~10 min para que el free tier no la duerma. Smoke
tests y demos mas confiables.

## Hecho desde la version anterior de este doc
- Migracion CircleCI → Semaphore (e2e, 2026-06-18).
- Branch protection en master (3 checks requeridos).
- Quality Gate de Sonar bloqueante (`sonar.qualitygate.wait=true`).
- Deteccion de PR nativa (sin `curl` a la API de GitHub) + deploy protegido contra builds de PR.
- Validate corre en cada push (una sola vez); Sonar solo en PR/master.
- Feedback a Telegram (deploy, CI roto en master, pipeline de PR), verificado e2e.
- Tooling de dev: `Makefile` + `scripts/check.sh` + `scripts/smoke.sh`.
- Smoke del deploy ahora **funcional** (`/health` + `/sum`), no solo liveness.
- Sumador funcional en la UI; sacado el copy de "conejillo de indias".

## Datos utiles
- URL app: https://utn-ics.onrender.com  (`/`, `/health`, `/sum?a=2&b=3`)
- Repo: https://github.com/jugodemilanesa/utn-ics
- Comandos: `make help` (lista todo), `make check`, `make run`, `make smoke URL=...`.
  Directo: `go test ./...`, `go run ./cmd/server`, `docker build -t utn-ics .`
