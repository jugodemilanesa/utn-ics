# Feedback a Telegram - Plan de Implementacion

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el pipeline de Semaphore notifique por Telegram el resultado del deploy, del CI roto en master, y del pipeline de PR.

**Architecture:** Un unico script bash (`.semaphore/scripts/notify-telegram.sh`) con toda la logica del mensaje y la decision de a quien notificar, invocado desde el `after_pipeline` de `semaphore.yml` (modo `ci`) y `deploy.yml` (modo `deploy`). `after_pipeline` se elige sobre `epilogue` porque corre siempre (incluso si un job fue cancelado por `fail_fast`).

**Tech Stack:** Bash, curl, API de Telegram Bot, Semaphore `after_pipeline`. Sin dependencias nuevas.

## Global Constraints

- Sin emojis en ningun archivo (codigo, comentarios, commits). Estados en texto plano: `EXITO` / `FALLA`.
- Comentarios y mensajes en espanol.
- Commits sin coautoria (no `Co-Authored-By`).
- Identidad git del repo: `jugodemilanesa` (ya configurada).
- El script NUNCA debe romper el build: ante error de red o secret faltante, sale 0.
- Toda la rama de trabajo es `feat/notify-telegram`; master esta protegida (entra por PR).
- Secret de Semaphore `telegram` con `TELEGRAM_TOKEN` y `TELEGRAM_CHAT_ID` (lo crea el usuario; prerrequisito para la verificacion e2e, NO para los tests locales).

---

### Task 1: Script de notificacion `notify-telegram.sh` (con tests locales)

**Files:**
- Create: `.semaphore/scripts/notify-telegram.sh`
- Test: `.semaphore/scripts/test-notify-telegram.sh`

**Interfaces:**
- Produces: funcion `build_message <modo>` (imprime el texto del mensaje, o vacio si no hay que notificar); funcion `send <text>` (manda a Telegram, o imprime si `NOTIFY_DRY_RUN=1`); entrypoint `main <modo>`. Modos: `ci`, `deploy`.

- [ ] **Step 1: Escribir los tests (fallan: el script no existe)**

Crear `.semaphore/scripts/test-notify-telegram.sh`:

```bash
#!/usr/bin/env bash
# Tests del armado de mensajes de notify-telegram.sh. No manda nada (usa build_message).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$DIR/notify-telegram.sh"

fail=0
assert_contains() { # $1 actual, $2 needle, $3 nombre
  if printf '%s' "$1" | grep -qF -- "$2"; then echo "ok: $3"
  else echo "FALLA: $3 | esperaba contener: [$2] | en: [$1]"; fail=1; fi
}
assert_empty() { # $1 actual, $2 nombre
  if [ -z "$1" ]; then echo "ok: $2"
  else echo "FALLA: $2 | esperaba vacio | en: [$1]"; fail=1; fi
}
base_env() {
  unset SEMAPHORE_GIT_REF_TYPE SEMAPHORE_GIT_BRANCH SEMAPHORE_GIT_PR_NUMBER \
        SEMAPHORE_PIPELINE_RESULT 2>/dev/null || true
  export SEMAPHORE_GIT_SHA="273e1e3abcdef"
  export SEMAPHORE_WORKFLOW_ID="wf-123"
  export SEMAPHORE_ORGANIZATION_URL="https://utn-ics.semaphoreci.com"
}

# ci / PR exito
base_env; export SEMAPHORE_GIT_REF_TYPE="pull-request" SEMAPHORE_GIT_PR_NUMBER="7" \
  SEMAPHORE_GIT_BRANCH="master" SEMAPHORE_PIPELINE_RESULT="passed"
out="$(build_message ci)"
assert_contains "$out" "[EXITO] PR #7: analisis" "ci PR exito"
assert_contains "$out" "commit: 273e1e3" "ci PR commit cortado a 7"
assert_contains "$out" "workflow: https://utn-ics.semaphoreci.com/workflows/wf-123" "ci PR link"

# ci / PR falla
base_env; export SEMAPHORE_GIT_REF_TYPE="pull-request" SEMAPHORE_GIT_PR_NUMBER="7" \
  SEMAPHORE_GIT_BRANCH="master" SEMAPHORE_PIPELINE_RESULT="failed"
out="$(build_message ci)"
assert_contains "$out" "[FALLA] PR #7: analisis" "ci PR falla"

# ci / master roto
base_env; export SEMAPHORE_GIT_REF_TYPE="branch" SEMAPHORE_GIT_BRANCH="master" \
  SEMAPHORE_PIPELINE_RESULT="failed"
out="$(build_message ci)"
assert_contains "$out" "[FALLA] CI en master" "ci master roto"

# ci / master OK -> silencio
base_env; export SEMAPHORE_GIT_REF_TYPE="branch" SEMAPHORE_GIT_BRANCH="master" \
  SEMAPHORE_PIPELINE_RESULT="passed"
out="$(build_message ci)"
assert_empty "$out" "ci master ok = silencio"

# ci / push rama sin PR -> silencio
base_env; export SEMAPHORE_GIT_REF_TYPE="branch" SEMAPHORE_GIT_BRANCH="feat/x" \
  SEMAPHORE_PIPELINE_RESULT="passed"
out="$(build_message ci)"
assert_empty "$out" "ci rama sin PR = silencio"

# deploy / exito -> incluye app
base_env; export SEMAPHORE_GIT_BRANCH="master" SEMAPHORE_PIPELINE_RESULT="passed"
out="$(build_message deploy)"
assert_contains "$out" "[EXITO] Deploy" "deploy exito"
assert_contains "$out" "app: https://utn-ics.onrender.com" "deploy exito incluye app"

# deploy / falla -> sin app
base_env; export SEMAPHORE_GIT_BRANCH="master" SEMAPHORE_PIPELINE_RESULT="failed"
out="$(build_message deploy)"
assert_contains "$out" "[FALLA] Deploy" "deploy falla"
if printf '%s' "$out" | grep -qF "app:"; then echo "FALLA: deploy falla NO debe incluir app"; fail=1; else echo "ok: deploy falla sin app"; fi

# send / dry-run imprime
NOTIFY_DRY_RUN=1 out="$(send "hola")"
assert_contains "$out" "hola" "send dry-run imprime"

[ "$fail" -eq 0 ] && echo "TODOS OK" || echo "HAY FALLAS"
exit "$fail"
```

- [ ] **Step 2: Correr los tests y confirmar que fallan**

Run: `bash .semaphore/scripts/test-notify-telegram.sh`
Expected: FALLA (el `source` no encuentra `notify-telegram.sh` -> error "No such file").

- [ ] **Step 3: Escribir el script `notify-telegram.sh`**

Crear `.semaphore/scripts/notify-telegram.sh`:

```bash
#!/usr/bin/env bash
# Notifica por Telegram el resultado del pipeline. Se invoca desde el after_pipeline
# de semaphore.yml (modo "ci") y deploy.yml (modo "deploy"). No rompe el build: ante
# cualquier problema de red o config, sale 0.
#
# Variables de Semaphore (inyectadas en after_pipeline):
#   SEMAPHORE_PIPELINE_RESULT  passed|failed|stopped|canceled
#   SEMAPHORE_GIT_REF_TYPE     branch|pull-request|tag
#   SEMAPHORE_GIT_BRANCH       rama (en PR = rama destino, p.ej. master)
#   SEMAPHORE_GIT_PR_NUMBER    numero de PR (solo en build de PR)
#   SEMAPHORE_GIT_SHA          commit (se corta a 7)
#   SEMAPHORE_ORGANIZATION_URL + SEMAPHORE_WORKFLOW_ID  -> link al workflow
# Secret 'telegram': TELEGRAM_TOKEN, TELEGRAM_CHAT_ID.
#
# NO se setea 'set -e' a nivel global: este archivo se 'source'-ea desde los tests
# y no queremos contaminar el shell del test. Las funciones usan ${VAR:-} por las dudas.

# Deriva el estado legible del resultado del pipeline.
estado_de_resultado() {
  if [ "${SEMAPHORE_PIPELINE_RESULT:-}" = "passed" ]; then
    echo "EXITO"
  else
    echo "FALLA"
  fi
}

# Arma el texto del mensaje segun el modo. Imprime vacio si no hay que notificar.
build_message() {
  local modo="$1"
  local estado titulo="" extra="" sha link
  estado="$(estado_de_resultado)"
  sha="${SEMAPHORE_GIT_SHA:-}"; sha="${sha:0:7}"
  link="${SEMAPHORE_ORGANIZATION_URL:-}/workflows/${SEMAPHORE_WORKFLOW_ID:-}"

  case "$modo" in
    ci)
      if [ "${SEMAPHORE_GIT_REF_TYPE:-}" = "pull-request" ]; then
        titulo="PR #${SEMAPHORE_GIT_PR_NUMBER:-?}: analisis"
      elif [ "${SEMAPHORE_GIT_BRANCH:-}" = "master" ] && \
           [ "${SEMAPHORE_PIPELINE_RESULT:-}" != "passed" ]; then
        titulo="CI en master"
      else
        return 0   # push a rama sin PR, o master OK: no se notifica
      fi
      ;;
    deploy)
      titulo="Deploy"
      if [ "$estado" = "EXITO" ]; then
        extra=$'\napp: https://utn-ics.onrender.com'
      fi
      ;;
    *)
      echo "notify-telegram: modo invalido '$modo'" >&2
      return 0
      ;;
  esac

  printf '[%s] %s\nrama: %s\ncommit: %s\nworkflow: %s%s\n' \
    "$estado" "$titulo" "${SEMAPHORE_GIT_BRANCH:-?}" "$sha" "$link" "$extra"
}

# Manda el texto a Telegram. En dry-run lo imprime. Nunca falla.
send() {
  local text="$1"
  if [ "${NOTIFY_DRY_RUN:-}" = "1" ]; then
    printf '%s\n' "$text"
    return 0
  fi
  if [ -z "${TELEGRAM_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
    echo "notify-telegram: faltan TELEGRAM_TOKEN/CHAT_ID; no se envia" >&2
    return 0
  fi
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${text}" >/dev/null \
    || echo "notify-telegram: fallo el envio (ignorado)" >&2
  return 0
}

main() {
  local text
  text="$(build_message "${1:-}")"
  if [ -n "$text" ]; then
    send "$text"
  fi
  return 0
}

# Solo corre main si se ejecuta directo (no si se hace 'source' desde los tests).
if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then
  main "$@"
fi
```

- [ ] **Step 4: Correr los tests y confirmar que pasan**

Run: `bash .semaphore/scripts/test-notify-telegram.sh`
Expected: cada linea `ok: ...` y al final `TODOS OK`; exit 0.

- [ ] **Step 5: Pasar shellcheck**

Run: `shellcheck .semaphore/scripts/notify-telegram.sh .semaphore/scripts/test-notify-telegram.sh`
Expected: sin output (sin warnings). Si `shellcheck` no esta instalado: `sudo apt install shellcheck` (no por snap).

- [ ] **Step 6: Commit**

```bash
git add .semaphore/scripts/notify-telegram.sh .semaphore/scripts/test-notify-telegram.sh
git commit -m "feat: script notify-telegram.sh con tests locales (dry-run)"
```

---

### Task 2: Enganchar el `after_pipeline` en los dos pipelines

**Files:**
- Modify: `.semaphore/semaphore.yml` (agregar `after_pipeline` a nivel pipeline)
- Modify: `.semaphore/deploy.yml` (agregar `after_pipeline` a nivel pipeline)

**Interfaces:**
- Consumes: `notify-telegram.sh` (Task 1) con modos `ci` y `deploy`.

- [ ] **Step 1: Agregar `after_pipeline` a `semaphore.yml`**

Agregar al final del archivo (a nivel raiz, despues del bloque `promotions:`), respetando la indentacion de nivel 0:

```yaml

# ---- Notificacion a Telegram (corre SIEMPRE, vea o no resultado el pipeline) ----
# after_pipeline (no epilogue) porque corre aunque un job haya sido cancelado por
# fail_fast. El script decide a quien notificar: build de PR -> 'PR #N: analisis';
# push a master roto -> 'CI en master'; master OK o rama sin PR -> nada.
after_pipeline:
  task:
    secrets:
      - name: telegram
    jobs:
      - name: Notificar Telegram
        commands:
          - checkout
          - bash .semaphore/scripts/notify-telegram.sh ci
```

- [ ] **Step 2: Agregar `after_pipeline` a `deploy.yml`**

Agregar al final del archivo (a nivel raiz, despues del bloque `blocks:`):

```yaml

# ---- Notificacion a Telegram del resultado del deploy ----
after_pipeline:
  task:
    secrets:
      - name: telegram
    jobs:
      - name: Notificar Telegram
        commands:
          - checkout
          - bash .semaphore/scripts/notify-telegram.sh deploy
```

- [ ] **Step 3: Validar el YAML localmente**

Run: `python3 -c "import yaml,sys; [yaml.safe_load(open(f)) for f in ['.semaphore/semaphore.yml','.semaphore/deploy.yml']]; print('YAML OK')"`
Expected: `YAML OK` (sin excepcion de parseo).

- [ ] **Step 4: Commit**

```bash
git add .semaphore/semaphore.yml .semaphore/deploy.yml
git commit -m "feat: enganchar notify-telegram en after_pipeline (ci y deploy)"
```

---

### Task 3: Verificacion end-to-end (requiere el secret cargado)

**Prerrequisito:** el usuario debe haber creado el bot y cargado el secret `telegram`
(`TELEGRAM_TOKEN` + `TELEGRAM_CHAT_ID`) en Semaphore. Sin eso, el script loguea
"faltan TELEGRAM_TOKEN/CHAT_ID" y no manda (no rompe nada, pero no llega el mensaje).

**Files:** ninguno (solo verificacion).

- [ ] **Step 1: Incluir el spec en la rama y abrir el PR**

```bash
git add docs/superpowers/specs/2026-06-18-feedback-telegram-design.md docs/superpowers/plans/2026-06-18-feedback-telegram.md
git commit -m "docs: spec y plan de feedback a Telegram"
git push -u origin feat/notify-telegram
gh pr create --base master --head feat/notify-telegram --title "feat: feedback a Telegram desde el pipeline" --body "Implementa notificaciones a Telegram (deploy, CI roto en master, pipeline de PR). Spec y plan en docs/superpowers/. Trello queda para una fase siguiente."
```

- [ ] **Step 2: Verificar el mensaje de PR**

Al abrir el PR corre el pipeline de PR (Sonar). Cuando termina, deberia llegar a Telegram:
`[EXITO] PR #<n>: analisis` con rama, commit y link.
Expected: el mensaje llega al chat. Si no llega, revisar: secret `telegram` cargado, y los logs del job "Notificar Telegram" en el after_pipeline del workflow de PR.

- [ ] **Step 3: Verificar el camino de deploy (al mergear)**

Mergear el PR (`gh pr merge <n> --merge --delete-branch`) dispara push a master -> deploy.
Expected: llega `[EXITO] Deploy` con la URL de la app. (El camino `FALLA / CI en master` no se prueba a proposito: se valido por los tests locales del Task 1.)

- [ ] **Step 4: Actualizar estado.md y memoria**

Marcar en `docs/estado.md` que el feedback a Telegram quedo HECHO (sacarlo de "Que FALTA", dejar Trello como pendiente). Actualizar la memoria `estado-pipeline-cicd`.

```bash
# (editar docs/estado.md)
git add docs/estado.md
git commit -m "docs: marcar feedback a Telegram como implementado"
```

---

## Notas de implementacion

- **parse_mode:** se manda texto plano (sin `parse_mode=HTML`) para evitar que un `<`,
  `>` o `&` rompa el formato. No necesitamos formato, solo texto.
- **checkout en after_pipeline:** el job arranca en una VM limpia; necesita `checkout`
  para tener el script en disco. Es el costo (segundos) de centralizar la logica en un
  script versionado en vez de duplicar curl inline.
