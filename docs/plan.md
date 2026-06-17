# Especificación de Infraestructura Técnica y Plan de Pipeline CI/CD

Este documento detalla la arquitectura de infraestructura y el flujo secuencial
automatizado del proyecto. El diseño está optimizado bajo un enfoque **100% Cloud**,
sin costos de mantenimiento (Free Tier) y centrado en la **inmutabilidad de los
despliegues**.

Incluye además una **aplicación de demostración mínima** (un "conejillo de indias")
cuyo único propósito es permitir ejercitar y mostrar el pipeline de punta a punta:
con un cambio de una línea se puede disparar tanto el camino exitoso como el camino
de error.

---

## 1. Mapa de la Infraestructura Final

El siguiente esquema representa cómo interactúan los componentes de desarrollo, el
cerebro de integración, el servidor de despliegue y los canales de feedback del equipo:

```text
 ┌────────────────────────────────────────────────────────┐
 │                   ENTORNO DEL EQUIPO                    │
 │   [ Editor Zed ] + [ Claude Code ] ──> [ GitHub ]      │
 │              (Ramas, Pull Requests y Merges)           │
 └─────────────────────────────────────┬──────────────────┘
                                        │
                                Webhook │ (Trigger Automático)
                                        ▼
 ┌────────────────────────────────────────────────────────┐
 │                       CIRCLECI                          │
 │                                                         │
 │  1. Clone Code                                          │
 │  2. Lint  (gofmt / go vet)                              │
 │  3. SonarCloud Scan ───> [ Quality Gate ]              │
 │  4. go build + go test (executor cimg/go)              │
 │  5. Deploy (Webhook HTTP a Render) ──────────┐         │
 │  6. Smoke Test post-deploy (GET /health) ────┤         │
 │  7. Scripts de Feedback (APIs HTTP) ─────────┼───┐     │
 │     (la imagen Docker la construye Render)    │   │     │
 └───────────────────────────────────────────────┼───┼─────┘
                                                 │   │
                 ┌───────────────────────────────┘   └──────────┐
                 ▼                                              ▼
 ┌───────────────────────────────┐            ┌───────────────────────────────┐
 │      ENTORNO DE ENTREGA        │            │     MECANISMOS DE FEEDBACK     │
 │                                │            │                               │
 │     [ Render Cloud Server ]    │            │     [ Telegram Bot ] (Chat)   │
 │   (App Go + Postgres opcional) │            │     [ Trello Board ] (Kanban) │
 └───────────────────────────────┘            └───────────────────────────────┘
```

---

## 2. Stack Tecnológico y Justificación por Etapa

### A. Gestión del Ciclo de Vida y Entorno Local

- **Editor de Código: Zed.** Elegido por su rendimiento ultra ligero y consumo
  mínimo de recursos frente a entornos basados en Electron.
- **Asistente de IA: Claude Code.** Integrado en la terminal para agilizar
  refactorizaciones y generación de pruebas unitarias.
- **Build local de contenedores: Docker o Podman (intercambiables).** El artefacto
  que se versiona es un `Dockerfile` (formato OCI), portable entre ambos runtimes.
  Podman es la opción recomendada en local por ser *daemonless* y *rootless*
  (`alias docker=podman`); la elección **no afecta** al pipeline, ya que Render
  compila la imagen con su propio runtime (CircleCI ni siquiera la construye). En
  WSL2, instalar Podman por
  `apt`, no por `snap`. **Gotcha de portabilidad:** Podman exige nombres de imagen
  totalmente calificados, así que el `Dockerfile` debe usar
  `FROM docker.io/library/golang:1.22-alpine` (no `FROM golang:1.22`) para construir
  igual en Podman, Docker y Render.
- **Tablero Kanban: Trello.** Gestor visual del progreso. Se actualiza
  automáticamente mediante llamadas a su API REST desde el pipeline.

### B. Control de Versiones (VCS)

- **Plataforma: GitHub.** Repositorio central de código. Funciona como disparador
  automático (Trigger): CircleCI está integrado con GitHub y arranca un pipeline en
  cada **push** (incluidos los de ramas con Pull Request abierto y el merge a la rama
  principal `master`).

### C. Servidor de Integración Continua (IC)

- **Motor Cloud: CircleCI.** Plataforma de CI/CD en la nube. Su plan **Free no
  requiere tarjeta de crédito** y otorga ~30.000 créditos/mes (~3.000 minutos en
  Linux Medium), de sobra para este proyecto. Se eligió tras descartar Harness (pasó a
  pedir tarjeta), Cirrus CI (cerró en jun-2026) y GitLab CI (pide tarjeta para los
  *shared runners*). *(Verificar límites vigentes del Free Tier al configurar.)*
  La definición del pipeline vive **versionada en el repo** en `.circleci/config.yml`.
- **Aislamiento.** Cada *job* de CircleCI corre dentro de su propio contenedor
  efímero en la nube. Usamos el *executor* Docker con la imagen oficial **`cimg/go`**
  (trae la toolchain de Go lista). Este runtime lo gestiona CircleCI: **no** se usa el
  Docker/Podman local del desarrollador.
- **Quién construye la imagen de producción: Render.** CircleCI solo ejecuta
  `go build` + `go test`; al terminar invoca el *Deploy Hook* de Render, que
  reconstruye la imagen desde el `Dockerfile`. Así el pipeline no necesita un
  *builder* de imágenes (ni registry), lo que simplifica la configuración y mantiene a
  Podman/Docker como herramienta **exclusivamente local**.
  *(Trade-off: un error en el `Dockerfile` no lo detecta CircleCI sino el build de
  Render / el smoke test. Como el `Dockerfile` es mínimo y estable, el riesgo es bajo;
  `go build` ya cubre los errores de compilación del código.)*

### D. Análisis de Calidad y Seguridad (DevSecOps)

- **Plataforma: SonarCloud.** SaaS oficial de SonarQube, gratuito para repositorios
  públicos de GitHub. Ejecuta análisis estático (SAST) buscando fallas de seguridad,
  *code smells* y valida el umbral de calidad (**Quality Gate**). Decora el Pull
  Request con sus hallazgos.

### E. Entorno de Entrega (CD / Deployment)

- **Hosting: Render.** PaaS con capa gratuita real para servicios web y bases de
  datos PostgreSQL. No exige tarjeta de crédito para registrarse.
- **Empaquetado: Dockerización Inmutable.** La aplicación se define mediante un
  `Dockerfile` *multi-stage*. Al recibir el estímulo del pipeline, Render instancia
  el contenedor garantizando que corra exactamente igual que en local.
- **Modelo de entornos: un único servicio de producción.** Tras el deploy se ejecuta
  un *smoke test* (ver §6). Render conserva la versión anterior de forma inmutable,
  por lo que el **rollback es 1 click** desde su panel.

### F. Mecanismo de Alertas

- **Notificaciones: Telegram Bot.** Bot dedicado al chat del equipo. Notifica éxito
  o fallo del deploy al instante mediante peticiones HTTP POST.

---

## 3. Aplicación de Demostración (el "conejillo de indias")

El proyecto de prueba es deliberadamente trivial: su objetivo **no** es la aplicación
en sí, sino ser fácil de modificar para ejercitar el pipeline.

### Stack: Go (biblioteca estándar)

Justificación frente a Node/Python/Bun:

- **Produce un binario literal** → encarna el concepto de "Binarios" del modelo de IC.
- **Imagen Docker ~10MB** (`scratch`/`distroless`) → mínima superficie, build y push
  veloces, "Dockerización Inmutable" en su forma más pura.
- **Cold start casi instantáneo** → el *smoke test* post-deploy en Render Free
  (que duerme el servicio tras 15 min de inactividad) es confiable.
- **Cero dependencias de test** → `go test` viene en la toolchain; menos `install`,
  menos créditos de CircleCI consumidos, menos puntos de fallo ajenos al código.

### Endpoints

- `GET /` → sirve una **landing animada con Three.js** que muestra de forma
  prominente la **versión y el commit**. Es la *perilla visible*: cambiar la versión,
  pushear y ver la animación nueva en producción demuestra que el deploy llegó.
- `GET /health` → `200 OK`. Habilita el *smoke test* post-deploy.
- `GET /sum?a=2&b=3` → responde usando una **función pura** `Sum(a, b)`.

### Front animado (Three.js sin build step)

Regla de oro: **no se agrega un build de frontend** (nada de npm/vite/webpack) para
mantener el CI pure-Go, rápido y barato.

- Un único `web/index.html` que importa **Three.js por CDN** (ESM + `importmap`
  desde jsdelivr/unpkg).
- Se incrusta en el binario con `//go:embed` → sigue siendo **una sola imagen Docker**,
  sin pasos adicionales en el pipeline.
- *(Extensión futura, fuera de alcance: si se quisiera un front con bundler real,
  se sumaría una etapa de CI dedicada al build del frontend.)*

### Las dos "perillas" de la demo

1. **Camino verde:** cambiar el string de versión en `/` → push → el deploy llega y
   la animación nueva aparece en prod. Telegram notifica OK, Trello → "Done".
2. **Camino rojo:** romper `Sum` o su test → push → `go test` falla → el pipeline se
   detiene, no despliega. Telegram notifica el fallo, Trello → "Bugs".

### Estructura sugerida del repositorio

```text
/cmd/server/main.go          # servidor HTTP: rutas / , /health , /sum
/internal/calc/sum.go        # func Sum(a, b int) int  (función pura)
/internal/calc/sum_test.go   # tests unitarios de Sum
/web/index.html              # landing con Three.js (servida vía go:embed)
/Dockerfile                  # multi-stage: build golang -> runtime scratch/distroless
/sonar-project.properties    # configuración de SonarCloud
/.circleci/config.yml        # definición del pipeline de CircleCI (versionada en el repo)
```

---

## 4. Modelo de Ramas y Disparadores

Se usa el **Pull Request como Quality Gate**. CircleCI dispara en cada push; la
separación validación/entrega se logra con **filtros de rama** en el workflow:

- **En cualquier rama / push de PR** → CircleCI corre el job de validación:
  `lint` → `SonarCloud` → `go build` + `go test`. **No despliega.** El check aparece en
  el PR y, si falla, el PR no debería mergearse.
- **En push a `master`** (el merge) → además del job de validación, corre el job de
  `deploy` (filtrado con `filters: branches: only: master`, y `requires` el job de
  validación): deploy a Render + smoke test + feedback.

Esto separa nítidamente **validación** (toda rama) de **entrega** (solo `master`),
reflejando el "Ramas y Merges" del modelo.

---

## 5. Plan de Flujo Secuencial (Paso a Paso)

```text
push de PR ─► [gofmt/vet] ─► [SonarCloud] ─► [go build + go test] ─► OK: mergeable
                                  │ falla
                                  └─► FALLA: Telegram + Trello "Bugs", PR bloqueado

push a master ─► [Trello: "QA / Verifying"] ─► [gofmt/vet] ─► [SonarCloud Quality Gate]
   ─► [go build + go test] ─► [deploy Render (Render buildea la imagen)] ─► [smoke test GET /health]
        ├─ EXITO ─► Trello "Done / Production" + Telegram notifica OK
        └─ FALLA ─► Telegram notifica el fallo + Trello "Bugs"; Render queda en versión anterior
```

Detalle por fase:

1. **Fase de Commit.** El equipo sube cambios a GitHub. GitHub dispara a CircleCI.
2. **Fase de Inicialización.** CircleCI mueve la tarjeta de Trello correspondiente a
   la columna **"QA / Verifying"**.
3. **Fase de Lint.** `gofmt -l` y `go vet` validan formato y errores estáticos básicos.
4. **Fase de Auditoría (SonarCloud).** Se inspecciona el código. Si no pasa el
   Quality Gate, el job falla y se salta a la fase de error.
5. **Fase de Build & Test.** En el executor `cimg/go` se ejecuta `go build`
   (chequea compilación) y `go test`.
6. **Fase de Despliegue** *(solo en `master`)*. Si todo dio verde, CircleCI invoca el
   *Deploy Hook* de Render vía `curl`. **Render reconstruye la imagen desde el
   `Dockerfile`** y actualiza la app.
7. **Fase de Smoke Test** *(solo en `master`)*. Ver §6.
8. **Fase de Feedback Final:**
   - **On Success:** Trello mueve la tarjeta a "Done / Production" con un comentario.
     Telegram: `Pipeline Exitoso. Desplegado correctamente en Render.`
   - **On Failure:** Trello regresa la tarjeta a "In Progress" / "Bugs" detallando el
     error. Telegram: `Pipeline Fallido. Revisar logs en CircleCI.`

---

## 6. Smoke Test Post-Deploy y Rollback

Tras el deploy, CircleCI verifica que la aplicación **realmente levantó** (no solo que
compiló). Esto cubre la flecha de "resultados de la instalación" del modelo de IC.

```bash
# Smoke test: reintenta para tolerar el cold start del Free Tier de Render
curl --fail --retry 5 --retry-delay 10 --retry-connrefused \
  "https://<tu-app>.onrender.com/health"
```

- Si el smoke test **pasa** → se dispara el feedback de éxito.
- Si **falla** → feedback de error. Como Render conserva la versión anterior de forma
  inmutable, el **rollback es manual (1 click)** desde el panel de Render. *(Extensión
  opcional: rollback automático invocando la API de Render desde CircleCI.)*

---

## 7. Manejo de Secretos

Ningún token vive en el repositorio. Todos se configuran en CircleCI como variables
de entorno y se inyectan en los pasos del pipeline:

- **`SONAR_TOKEN`** → en un **Context** de CircleCI llamado `sonarcloud` (es lo que
  espera el orb de SonarCloud).
- El resto → como **Project Environment Variables** del proyecto en CircleCI
  (*Project Settings → Environment Variables*).

| Secreto | Uso | Dónde |
|---|---|---|
| `SONAR_TOKEN` | Autenticación con SonarCloud | Context `sonarcloud` |
| `RENDER_DEPLOY_HOOK_URL` | Disparar el deploy en Render | Project Env Var |
| `TELEGRAM_TOKEN` / `TELEGRAM_CHAT_ID` | Enviar notificaciones | Project Env Var |
| `TRELLO_KEY` / `TRELLO_TOKEN` | Mover tarjetas vía API | Project Env Var |
| `TRELLO_LIST_*` (IDs de columnas) | Destino de las tarjetas según el estado | Project Env Var |

---

## 8. Plantillas de Conectividad (Scripts de Consola)

Estructuras `curl` para usar dentro de los `run` steps del `.circleci/config.yml`.
CircleCI expone variables propias: `CIRCLE_SHA1` (commit), `CIRCLE_BUILD_URL` (link al
build), `CIRCLE_BRANCH`, etc. El "estado" del pipeline se maneja con steps separados:
uno con `when: on_success` y otro con `when: on_fail`.

### Disparar el deploy en Render

```bash
curl -X POST "${RENDER_DEPLOY_HOOK_URL}"
```

### Notificación a Telegram Bot

```bash
curl -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
  -d "chat_id=${TELEGRAM_CHAT_ID}" \
  -d "parse_mode=HTML" \
  --data-urlencode "text=Pipeline en rama ${CIRCLE_BRANCH}
Commit: ${CIRCLE_SHA1}
Link: ${CIRCLE_BUILD_URL}"
```

### Mover una tarjeta en Trello (cambia la columna `idList`)

```bash
curl -X PUT "https://api.trello.com/1/cards/${CARD_ID}" \
  --data-urlencode "key=${TRELLO_KEY}" \
  --data-urlencode "token=${TRELLO_TOKEN}" \
  --data-urlencode "idList=${TRELLO_LIST_DONE}"
```

---

## 9. Base de Datos (Teórico — fuera del flujo activo)

PostgreSQL queda **documentado pero no implementado** en esta primera versión. Si la
app lo usara, así encajaría en el modelo (cumpliendo el "Scripts Bases D." que viaja en
ambas flechas del diagrama):

- Los scripts de schema (`migrations/*.sql`) se **versionan en el repositorio**, junto
  al código.
- En el pipeline, **antes o durante el deploy**, se ejecutaría una herramienta de
  migraciones (p. ej. `golang-migrate` o `goose`) que aplica las migraciones
  pendientes contra la base de Render: `migrate -path ./migrations -database "$DATABASE_URL" up`.
- Así, un cambio de schema viaja por el mismo pipeline que el código: queda
  versionado, auditado por Sonar y desplegado de forma reproducible.
- El rollback de datos se contemplaría con migraciones reversibles (`up`/`down`).

---

## 10. Estado del Plan — Checklist de Implementación

Para tener "todo hecho", en orden:

- [x] `git init` + crear repositorio público en GitHub *(es la primera pieza del
      propio pipeline)*.
- [x] App de demo Go: `main.go`, `internal/calc/sum.go` + test, `web/index.html`
      (Three.js), `Dockerfile` multi-stage.
- [x] Verificar build local de la imagen con Docker y `GET /health` respondiendo.
- [x] Crear el servicio en Render desde el `Dockerfile` (app viva) y obtener el
      *Deploy Hook*.
- [x] Conectar el repo a SonarCloud y agregar `sonar-project.properties` (scan local OK).
- [ ] Crear el proyecto en CircleCI conectando el repo de GitHub.
- [ ] Escribir `.circleci/config.yml`: job de validación (lint → Sonar → `go build` +
      `go test`) y job de `deploy` (filtrado a `master`, `requires` validación) con
      deploy a Render + smoke test + feedback.
- [ ] Cargar secretos: Context `sonarcloud` con `SONAR_TOKEN`; Project Env Vars con
      `RENDER_DEPLOY_HOOK_URL`, Telegram y Trello.
- [ ] Crear el bot de Telegram y el tablero de Trello.
- [ ] Prueba de extremo a extremo: ejercitar la **perilla verde** y la **perilla roja**.

### Extensiones opcionales (fuera de alcance inicial)

- Rollback automático vía API de Render ante smoke test fallido.
- Entorno de *staging* separado de producción.
- Base de datos PostgreSQL con migraciones (ver §9).
- Front con build real (bundler) como etapa de CI dedicada.
