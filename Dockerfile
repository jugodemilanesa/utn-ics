# syntax=docker/dockerfile:1

# ============================================================================
# Etapa 1: BUILD — compilamos el binario con la toolchain completa de Go.
# Usamos el nombre TOTALMENTE CALIFICADO (docker.io/library/...) para que la
# imagen se construya igual con Docker, Podman y Render (gotcha de Podman).
# ============================================================================
FROM docker.io/library/golang:1.22-alpine AS build

WORKDIR /src

# Copiamos primero go.mod (y go.sum cuando exista) para aprovechar la cache de
# capas de Docker: si las dependencias no cambian, Docker reutiliza esta capa y
# no vuelve a bajarlas. Por eso va ANTES de copiar el resto del código.
COPY go.mod ./
RUN go mod download

# Ahora sí, el resto del código fuente.
COPY . .

# El SHA del commit entra como build-arg y se estampa en el binario (la técnica de
# CI que vimos con -ldflags). En local podés pasarlo; si no, queda "dev".
ARG COMMIT=dev

# CGO_ENABLED=0  -> binario 100% estático (sin libc), requisito para correr en scratch.
# GOOS=linux     -> target Linux (el contenedor).
# -ldflags "-s -w" -> elimina tabla de símbolos e info de debug => binario más chico.
# -X main.commit  -> inyecta el commit.
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags "-s -w -X main.commit=${COMMIT}" \
    -o /app ./cmd/server

# ============================================================================
# Etapa 2: RUNTIME — imagen final mínima. scratch = imagen vacía (0 bytes).
# Solo copiamos el binario; el HTML ya viaja DENTRO de él (go:embed).
# ============================================================================
FROM scratch

COPY --from=build /app /app

# Documental: la app escucha el puerto que le diga la variable PORT (8080 por
# defecto). EXPOSE no abre nada por sí solo, solo declara la intención.
EXPOSE 8080

# ENTRYPOINT define el ejecutable que corre al levantar el contenedor.
ENTRYPOINT ["/app"]
