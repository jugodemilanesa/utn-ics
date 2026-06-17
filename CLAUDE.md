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

Flujo: **GitHub** (VCS + trigger) → **Harness CI** (lint + SonarCloud + `go test`) →
**Render** (deploy + hosting) → feedback a **Telegram** (alertas) + **Trello** (kanban).

Decisiones clave que condicionan toda implementación:

- **App de demo en Go (stdlib).** Endpoints: `GET /` (landing con versión/commit
  visible), `GET /health` (smoke test), `GET /sum?a=&b=` (usa una función pura
  `Sum` testeable). Sin dependencias externas.
- **Front con Three.js SIN build step.** Un único `web/index.html` con Three.js por
  CDN, embebido en el binario con `//go:embed`. No agregar npm/bundler al pipeline
  (mantiene el CI pure-Go).
- **La imagen Docker la construye Render, no Harness.** Harness solo hace
  `go build` + `go test`; al terminar invoca el Deploy Hook de Render, que reconstruye
  desde el `Dockerfile`. No hay registry ni builder de imágenes en CI.
- **Docker y Podman son intercambiables y solo para uso local.** El `Dockerfile` debe
  usar nombres de imagen totalmente calificados (`FROM docker.io/library/golang:...`)
  para buildear igual en Podman, Docker y Render.
- **Modelo de ramas:** PR valida (lint + Sonar + test, sin deploy); merge a `main`
  despliega.
- **Secretos** (Telegram/Trello/Render/Sonar) viven como Harness Secrets, nunca en el
  repo.

## Convenciones de trabajo

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
