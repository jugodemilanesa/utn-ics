#!/usr/bin/env bash
# Espejo local del block Validate del CI + los tests del script de notificacion.
# Corre lo mismo que gatea Semaphore, asi te enteras ANTES de pushear.
# Uso: bash scripts/check.sh   (o: make check)
set -euo pipefail

# Pararse en la raiz del repo (este script vive en scripts/).
cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "==> gofmt (formato)"
fmt_out="$(gofmt -l .)"
if [ -n "$fmt_out" ]; then
  echo "Archivos mal formateados (corregi con 'make fmt' o 'gofmt -w .'):" >&2
  echo "$fmt_out" >&2
  exit 1
fi

echo "==> go vet"
go vet ./...

echo "==> go build"
go build ./...

echo "==> go test"
go test ./...

echo "==> tests del script de notificacion"
bash .semaphore/scripts/test-notify-telegram.sh

echo "OK: todo paso (equivalente al block Validate del CI)"
