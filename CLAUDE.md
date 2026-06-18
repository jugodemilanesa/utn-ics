# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Propósito: aprendizaje ante todo

**Este es un proyecto para aprender. El aprendizaje del usuario es la prioridad #1**,
por encima de la velocidad o de "terminar". Esto cambia cómo trabajar acá:

- Explicar el *por qué* de cada decisión, no solo el *qué*. Preferir que el usuario
  entienda a entregar rápido.
- No resolver todo de forma autónoma: cuando hay algo que el usuario debería aprender
  a hacer, guiarlo paso a paso (o darle los comandos para que los corra él) en vez de
  hacerlo por él.
- Ante una decisión técnica, mostrar las alternativas y el razonamiento, no solo la
  conclusión.

## Estado del proyecto

Proyecto de la materia ICS (UTN). Actualmente en **fase de planificación**: el único
contenido es `docs/plan.md`, que es la **fuente de verdad** del diseño. Todavía no hay
código de aplicación ni repositorio git inicializado.

El objetivo es construir un **pipeline CI/CD completo** y una **app de demostración
mínima** ("conejillo de indias") que sirva para ejercitarlo de punta a punta. La app
no es el objetivo; el pipeline sí.

Antes de implementar cualquier cosa, leer `docs/plan.md` — define arquitectura, stack,
flujo y decisiones ya tomadas.

## Arquitectura objetivo (resumen; detalle en docs/plan.md)

Flujo: **GitHub** (VCS + trigger) → **Semaphore** (lint + SonarCloud + `go test`) →
**Render** (deploy + hosting) → feedback a **Telegram** (alertas) + **Trello** (kanban).

Nota: el servidor de IC es **Semaphore** (`.semaphore/semaphore.yml` + `deploy.yml`).
Historia: se descartó Harness (pasó a pedir tarjeta), Cirrus CI (cerró jun-2026) y
GitLab CI (pide tarjeta para shared runners). Se usó CircleCI un tiempo, pero se migró a
Semaphore (2026-06-18) por UI más clara y, sobre todo, porque expone el número de PR de
forma nativa (`SEMAPHORE_GIT_PR_NUMBER`), lo que habilita correr Sonar en modo PR.
GitHub Actions era la otra opción válida equivalente. Detalle:
`docs/superpowers/specs/2026-06-18-migracion-semaphore-branching-design.md`.

Decisiones clave que condicionan toda implementación:

- **App de demo en Go (stdlib).** Endpoints: `GET /` (landing con versión/commit
  visible), `GET /health` (smoke test), `GET /sum?a=&b=` (usa una función pura
  `Sum` testeable). Sin dependencias externas.
- **Front con Three.js SIN build step.** Un único `web/index.html` con Three.js por
  CDN, embebido en el binario con `//go:embed`. No agregar npm/bundler al pipeline
  (mantiene el CI pure-Go).
- **La imagen Docker la construye Render, no el CI.** El CI solo hace
  `go build` + `go test`; al terminar invoca el Deploy Hook de Render, que reconstruye
  desde el `Dockerfile`. No hay registry ni builder de imágenes en CI.
- **Docker y Podman son intercambiables y solo para uso local.** El `Dockerfile` debe
  usar nombres de imagen totalmente calificados (`FROM docker.io/library/golang:...`)
  para buildear igual en Podman, Docker y Render.
- **Modelo de ramas:** trunk-based. La rama principal es **`master`** (tronco siempre
  desplegable, protegida sin push directo). Cada cambio va en una feature branch corta
  (`feat/...`, `fix/...`) y entra por **Pull Request**. En PR corre el block Validate
  (gofmt/vet/build/test) + Sonar en **modo PR** (gatea el merge vía branch protection).
  En `master` corre Validate + Sonar (modo main) + deploy a Render (por promotion, solo
  si todo pasa). Razón del modo PR: el plan Free de SonarCloud solo analiza la main
  branch en modo branch (las demás dan 403), pero **sí** permite analizar PRs cuyo
  target es la main branch.
- **Secretos:** se cargan como **Secrets de Semaphore** y se referencian por nombre en
  los blocks: `sonarcloud` (contiene `SONAR_TOKEN`) y `render` (contiene
  `RENDER_DEPLOY_HOOK_URL`); Telegram/Trello cuando se implementen. Nunca en el repo.

## Convenciones de trabajo

- **Sin emojis en el proyecto.** No usar emojis en docs, código, comentarios,
  mensajes de commit ni en ningún archivo del repo. Para estados usar texto plano
  (`OK`, `FALLA`, `EXITO`, `error`). Las flechas tipográficas (`→`, `─►`) en
  diagramas ASCII están permitidas: no son emojis.
- **No agregarse como coautor en los commits.** No incluir líneas
  `Co-Authored-By: Claude ...` ni similares en los mensajes de commit.
- Hacer commit o push solo cuando el usuario lo pida.
- **Identidad git de este repo:** la cuenta es `jugodemilanesa` (GitHub), no
  `misteccapital`. Configurar **localmente** (sin `--global`, porque el usuario tiene
  dos identidades):
  - `user.name` = `jugodemilanesa`
  - `user.email` = `181919739+jugodemilanesa@users.noreply.github.com` (noreply de
    GitHub; es el email el que linkea el commit a la cuenta, no el nombre).

## Entorno (WSL2)

- Instalar herramientas por `apt`, no por `snap` (snap trae problemas de confinamiento
  con el sandbox y con git).
