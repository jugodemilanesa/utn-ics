#!/usr/bin/env bash
# Logica del block Sonar, extraida del YAML para poder versionarla, correrla local y
# pasarle shellcheck (antes vivia embebida como un bloque de bash dentro del YAML).
#
# Decide el modo de analisis segun el tipo de build:
#   - build de PR (SEMAPHORE_GIT_PR_NUMBER presente) -> modo Pull Request.
#   - push a master                                  -> modo main (sin PR_ARGS).
# En una rama feature sin PR no deberia ejecutarse (lo gatea el run/when del YAML);
# en modo branch el free tier de SonarCloud daria 403.
set -euo pipefail

# Pin de la imagen del scanner: 'latest' = build NO reproducible (un cambio
# incompatible upstream rompe el CI sin que toquemos nada). Pineamos a un tag fijo y
# completo. Para bumpear, ver tags en hub.docker.com/r/sonarsource/sonar-scanner-cli
SCANNER_IMAGE="${SONAR_SCANNER_IMAGE:-sonarsource/sonar-scanner-cli:12.1.0.3233_8.0.1}"

# La toolchain de Go ya la fija el caller con 'sem-version go 1.25' (es un comando del
# toolbox de Semaphore, solo disponible en el shell del job, no en este bash hijo).
# Regeneramos el coverage: cada block corre en su propia VM y NO hereda el coverage.out
# del block Validate; es barato regenerarlo.
go test -coverprofile=coverage.out ./...

# Construimos los args de modo PR en un array (en vez de una string con word-splitting)
# para que shellcheck no se queje y el quoting sea correcto.
PR_ARGS=()
if [ -n "${SEMAPHORE_GIT_PR_NUMBER:-}" ]; then
  # PR_BRANCH = rama origen del PR; GIT_BRANCH = rama destino (master).
  PR_ARGS=(
    "-Dsonar.pullrequest.key=${SEMAPHORE_GIT_PR_NUMBER}"
    "-Dsonar.pullrequest.branch=${SEMAPHORE_GIT_PR_BRANCH}"
    "-Dsonar.pullrequest.base=${SEMAPHORE_GIT_BRANCH}"
  )
fi

docker run --rm \
  -e SONAR_TOKEN \
  -e SONAR_HOST_URL \
  -v "$(pwd):/usr/src" \
  "$SCANNER_IMAGE" \
  "${PR_ARGS[@]}"
