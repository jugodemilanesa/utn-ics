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
