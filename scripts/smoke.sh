#!/usr/bin/env bash
# Smoke test post-deploy: verifica que la app desplegada esta viva Y responde bien.
# No es solo liveness (/health): tambien ejercita la logica real (/sum) y, si se le
# pasa el commit esperado, espera a que esa VERSION sea la viva en prod (trazabilidad).
# Uso: bash scripts/smoke.sh <base_url> [commit_esperado]
#   ej: bash scripts/smoke.sh https://utn-ics.onrender.com
#       bash scripts/smoke.sh https://utn-ics.onrender.com "$SEMAPHORE_GIT_SHA"
#       bash scripts/smoke.sh http://localhost:8080
# Env:
#   SMOKE_VERSION_SOFT=1   -> un mismatch de version solo ADVIERTE (no rompe el smoke).
#   SMOKE_VERSION_TRIES=N  -> intentos del poll de /version (default 40, x15s = 10 min).
set -euo pipefail

BASE="${1:-}"
EXPECTED_COMMIT="${2:-}"   # opcional: si se pasa, se espera/verifica /version
if [ -z "$BASE" ]; then
  echo "uso: $0 <base_url> [commit_esperado]" >&2
  exit 2
fi
BASE="${BASE%/}"   # saca la barra final si la hubiera

# fetch: --retry tolera el cold start del free tier (reintenta ante connrefused/5xx).
fetch() { curl --fail --silent --show-error --retry 12 --retry-delay 15 --retry-connrefused "$@"; }
# get: UN intento rapido, sin reintento largo. Lo usa el poll de /version (que tiene su
# propio loop), porque ahi necesitamos reintentar ante un 200 con el commit VIEJO, cosa
# que 'curl --retry' no hace (solo reintenta ante error de conexion o 5xx).
get() { curl --fail --silent --show-error --max-time 15 "$@"; }

# --- 1. Esperar a la version nueva (solo si nos pasaron el commit esperado) ---
# Render (free tier) puede tardar varios minutos en reconstruir y SWAPEAR el trafico.
# Mientras tanto sigue sirviendo la version VIEJA, que responde 200 -> por eso hay que
# POOLEAR /version hasta que aparezca el commit nuevo (o cortar por timeout). Hacerlo
# aca, ANTES de /health y /sum, garantiza que esos dos validan la version NUEVA.
if [ -n "$EXPECTED_COMMIT" ]; then
  short="${EXPECTED_COMMIT:0:7}"
  tries="${SMOKE_VERSION_TRIES:-40}"   # 40 x 15s = 10 min de margen para rebuild+swap
  echo "==> esperando a que /version sea $short (hasta ${tries}x15s)"
  matched=""
  version_json=""
  for i in $(seq 1 "$tries"); do
    version_json="$(get "$BASE/version" || true)"
    if printf '%s' "$version_json" | grep -q "\"commit\":\"$short\""; then
      echo "ok (commit=$short, intento $i)"
      matched=1
      break
    fi
    [ "$i" -lt "$tries" ] && sleep 15
  done
  if [ -z "$matched" ]; then
    msg="/version no llego al commit '$short' tras ${tries} intentos (ultimo: '${version_json:-sin respuesta}')"
    if [ "${SMOKE_VERSION_SOFT:-0}" = "1" ]; then
      echo "WARN: $msg (modo soft, no rompe)." >&2
    else
      echo "FALLA: $msg." >&2
      echo "       El deploy no tomo a tiempo o sirve una version vieja." >&2
      exit 1
    fi
  fi
fi

# --- 2. Validar la version viva: liveness (/health) + correctitud (/sum) ---
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

echo "OK: smoke test paso contra $BASE"
