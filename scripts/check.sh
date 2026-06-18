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

# Espejo del block Security del CI. govulncheck es opcional en local (es un binario que
# hay que instalar): si esta, lo corremos; si no, avisamos y seguimos (no rompemos el
# check por no tenerlo). 'make vuln' lo instala y corre.
echo "==> govulncheck (vulns conocidas)"
if command -v govulncheck >/dev/null 2>&1; then
  govulncheck ./...
else
  echo "  (govulncheck no instalado; corre 'make vuln' para instalarlo. Se omite.)"
fi

echo "==> tests del script de notificacion"
bash .semaphore/scripts/test-notify-telegram.sh

echo "OK: todo paso (equivalente a los blocks Validate + Security del CI)"
