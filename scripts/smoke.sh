#!/usr/bin/env bash
# Smoke test post-deploy: verifica que la app desplegada esta viva Y responde bien.
# No es solo liveness (/health): tambien ejercita la logica real (/sum).
# Uso: bash scripts/smoke.sh <base_url>
#   ej: bash scripts/smoke.sh https://utn-ics.onrender.com
#       bash scripts/smoke.sh http://localhost:8080
set -euo pipefail

BASE="${1:-}"
if [ -z "$BASE" ]; then
  echo "uso: $0 <base_url>" >&2
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

echo "OK: smoke test paso contra $BASE"
