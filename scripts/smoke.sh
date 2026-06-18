#!/usr/bin/env bash
# Smoke test post-deploy: verifica que la app desplegada esta viva Y responde bien.
# No es solo liveness (/health): tambien ejercita la logica real (/sum) y, si se le
# pasa el commit esperado, confirma que la VERSION viva en prod es la recien desplegada.
# Uso: bash scripts/smoke.sh <base_url> [commit_esperado]
#   ej: bash scripts/smoke.sh https://utn-ics.onrender.com
#       bash scripts/smoke.sh https://utn-ics.onrender.com "$SEMAPHORE_GIT_SHA"
#       bash scripts/smoke.sh http://localhost:8080
set -euo pipefail

BASE="${1:-}"
EXPECTED_COMMIT="${2:-}"   # opcional: si se pasa, se verifica /version
if [ -z "$BASE" ]; then
  echo "uso: $0 <base_url> [commit_esperado]" >&2
  exit 2
fi
BASE="${BASE%/}"   # saca la barra final si la hubiera

# --retry tolera el cold start del free tier de Render (la app puede tardar en levantar).
fetch() { curl --fail --silent --show-error --retry 12 --retry-delay 15 --retry-connrefused "$@"; }

echo "==> GET $BASE/health"
health="$(fetch "$BASE/health")"
if [ "$health" != "ok" ]; then
  echo "FALLA: /health devolvio '$health', esperaba 'ok'" >&2
  exit 1
fi
echo "ok"

echo "==> GET $BASE/sum?a=2&b=3"
sum="$(fetch "$BASE/sum?a=2&b=3")"
# /sum devuelve JSON: {"a":2,"b":3,"result":5}. Verificamos el resultado.
if ! printf '%s' "$sum" | grep -q '"result":5'; then
  echo "FALLA: /sum?a=2&b=3 devolvio '$sum', esperaba contener \"result\":5" >&2
  exit 1
fi
echo "ok (result=5)"

# --- Verificacion de version (trazabilidad), solo si nos pasaron el commit esperado ---
# Confirma que el binario vivo en prod es el del commit que se acaba de desplegar, y no
# una version cacheada o un deploy que silenciosamente no tomo. Compara los primeros 7
# caracteres (short SHA), porque /version devuelve el commit acortado.
if [ -n "$EXPECTED_COMMIT" ]; then
  short="${EXPECTED_COMMIT:0:7}"
  echo "==> GET $BASE/version (esperando commit $short)"
  version_json="$(fetch "$BASE/version")"
  if ! printf '%s' "$version_json" | grep -q "\"commit\":\"$short\""; then
    # SMOKE_VERSION_SOFT=1 -> solo advierte (no rompe). Util la primera vez, hasta
    # confirmar que Render expone RENDER_GIT_COMMIT y /version muestra el SHA real.
    # Sin esa env (modo estricto, el default), un mismatch FALLA el smoke y gatea
    # el rollback: trazabilidad real (no se promueve una version que no es la nuestra).
    if [ "${SMOKE_VERSION_SOFT:-0}" = "1" ]; then
      echo "WARN: /version devolvio '$version_json', esperaba commit '$short' (modo soft, no rompe)." >&2
    else
      echo "FALLA: /version devolvio '$version_json', esperaba commit '$short'." >&2
      echo "       El deploy puede no haber tomado o estar sirviendo una version vieja." >&2
      exit 1
    fi
  else
    echo "ok (commit=$short)"
  fi
fi

echo "OK: smoke test paso contra $BASE"
