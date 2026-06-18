#!/usr/bin/env bash
# Rollback automatico de Render cuando el smoke test post-deploy falla.
# Se invoca desde el epilogue 'on_fail' del block Deploy (deploy.yml).
#
# Importante: rollback de DEPLOY != rollback de CODIGO. Esto revierte lo que corre en
# prod, pero master sigue con el commit roto. Por eso la alerta incluye el comando de
# revert PR: el rollback es el freno de mano, el revert PR vuelve a poner master en la
# calzada (ver docs/runbook-incidentes.md).
#
# Logica (con cuidado de no degradar prod si ya esta sano):
#   1. Pregunta a la API de Render cual es el deploy VIVO y su commit.
#   2. Si el vivo es el que ACABAMOS de desplegar (el que rompio el smoke) -> revierte
#      al deploy exitoso anterior.
#   3. Si el vivo NO es el nuestro (ej. el health-check gate de Render ya retuvo la
#      version anterior buena) -> NO revierte (seria un downgrade): solo alerta.
#   4. Siempre manda una alerta accionable a Telegram.
#
# Secretos requeridos (Secrets de Semaphore 'render-api' + 'telegram'):
#   RENDER_API_KEY, RENDER_SERVICE_ID, TELEGRAM_TOKEN, TELEGRAM_CHAT_ID
set -euo pipefail

API="https://api.render.com/v1"
DEPLOYED_SHA="${SEMAPHORE_GIT_SHA:-}"
SHORT="${DEPLOYED_SHA:0:7}"

# notify manda un mensaje a Telegram. No rompe el job si el envio falla (best-effort).
notify() {
  local msg="$1"
  if [ -n "${TELEGRAM_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
    curl -fsS -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
      --data-urlencode "text=${msg}" >/dev/null || echo "WARN: no se pudo notificar a Telegram" >&2
  fi
}

# Guard: sin credenciales de la API no podemos revertir. Alertamos y salimos limpio
# (exit 0) para no enmascarar el fallo real del smoke, que ya marco el job en rojo.
if [ -z "${RENDER_API_KEY:-}" ] || [ -z "${RENDER_SERVICE_ID:-}" ]; then
  echo "WARN: faltan RENDER_API_KEY/RENDER_SERVICE_ID; no se intenta rollback." >&2
  notify "DEPLOY FALLA en utn-ics (commit ${SHORT}). Smoke rojo. Rollback NO configurado (faltan secretos render-api). Revisar prod a mano."
  exit 0
fi

# jq parsea la respuesta de la API. En la VM de Semaphore suele venir; si no, se instala.
if ! command -v jq >/dev/null 2>&1; then
  sudo apt-get update -qq && sudo apt-get install -y -qq jq
fi

auth=(-H "Authorization: Bearer ${RENDER_API_KEY}" -H "Accept: application/json")

# 1. Ultimos deploys (mas nuevos primero). Cada item es {deploy:{...}, cursor:...}.
deploys="$(curl -fsS "${auth[@]}" "${API}/services/${RENDER_SERVICE_ID}/deploys?limit=20")"

# Commit del deploy VIVO actual (status == live).
live_commit="$(printf '%s' "$deploys" | jq -r '[.[].deploy | select(.status=="live")][0].commit.id // ""')"
live_short="${live_commit:0:7}"

# 2. Si el vivo NO es el que desplegamos, el gate de Render ya retuvo la version buena.
if [ -n "$SHORT" ] && [ -n "$live_short" ] && [ "$live_short" != "$SHORT" ]; then
  echo "Vivo=${live_short} != desplegado=${SHORT}: el gate de Render ya retuvo la version buena. No se revierte."
  notify "$(printf 'DEPLOY FALLA en utn-ics (commit %s): el health-check gate de Render RETUVO la version buena (%s). Prod sigue sano, pero master quedo con un commit que no pasa smoke.\nAccion: abrir revert PR -> git revert -m 1 %s' "$SHORT" "$live_short" "$SHORT")"
  exit 0
fi

# 3. El vivo ES el roto: buscar el deploy exitoso anterior (el deactivated mas reciente).
prev_id="$(printf '%s' "$deploys" | jq -r '[.[].deploy | select(.status=="deactivated")][0].id // ""')"
if [ -z "$prev_id" ]; then
  echo "No se encontro un deploy anterior para revertir." >&2
  notify "DEPLOY FALLA en utn-ics (commit ${SHORT}). Smoke rojo y NO hay deploy anterior para rollback automatico. Intervenir a mano."
  exit 0
fi

echo "Revirtiendo al deploy anterior: ${prev_id}"
curl -fsS -X POST "${auth[@]}" -H "Content-Type: application/json" \
  -d "{\"deployId\":\"${prev_id}\"}" \
  "${API}/services/${RENDER_SERVICE_ID}/rollback" >/dev/null

notify "$(printf 'ROLLBACK automatico en utn-ics: el commit %s rompio el smoke; prod revertido al deploy anterior (%s).\nmaster quedo ROTA.\nAccion requerida: abrir revert PR -> git revert -m 1 %s' "$SHORT" "$prev_id" "$SHORT")"
echo "Rollback disparado OK."
