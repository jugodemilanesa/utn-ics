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
