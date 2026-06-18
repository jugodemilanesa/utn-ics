# Atajos de desarrollo del proyecto. La logica pesada vive en scripts/ (lo mismo que
# corre el CI), el Makefile solo es la "puerta de entrada" descubrible: 'make help'.
# Nota: las recetas (lineas indentadas) arrancan con un TAB, no espacios.

.PHONY: help fmt check test run build docker-run smoke

help: ## Lista los targets disponibles
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-8s\033[0m %s\n", $$1, $$2}'

fmt: ## Formatea el codigo (gofmt -w)
	gofmt -w .

check: ## Corre lo mismo que el block Validate del CI (gofmt, vet, build, test)
	bash scripts/check.sh

test: ## Corre los tests de Go
	go test ./...

run: ## Levanta el servidor local en http://localhost:8080
	go run ./cmd/server

build: ## Construye la imagen Docker localmente
	docker build -t utn-ics .

docker-run: build ## Construye y corre el contenedor local (como Render) en http://localhost:8080
	docker run --rm -e PORT=8080 -p 8080:8080 utn-ics

smoke: ## Smoke test contra una URL. Uso: make smoke URL=http://localhost:8080
	bash scripts/smoke.sh $(URL)
