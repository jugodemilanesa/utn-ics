# Migracion a Semaphore CI + estrategia de ramas (trunk-based con PR)

Fecha: 2026-06-18
Estado: aprobado, pendiente de implementar

## 1. Problema y origen

El error original era el job de SonarCloud fallando en CircleCI con:

    ERROR Not authorized or project not found. Please check the 'SONAR_TOKEN'...

La investigacion sistematica descarto el token (es valido y tiene permiso Browse: lee
el Quality Gate de `master` con HTTP 200) y aislo la causa raiz real:

- SonarCloud tiene dos modos de analisis distintos: **branch analysis** (analizar una
  rama suelta) y **pull request analysis** (analizar el diff de un PR contra su target).
- El plan **Free** de SonarQube Cloud solo permite **branch analysis de la main branch**.
  Cualquier otra rama devuelve HTTP 403: "Organization is not allowed to access data
  from non main branches" (confirmado en la UI: la feature branch figura "Not analyzed"
  con badge "Upgrade").
- CircleCI corria el scanner en **modo branch** sobre una feature branch
  (`Branch name: chore/sonar-quality-gate, type: short` en el log) => 403 => el scanner
  lo reportaba con el mensaje generico de "not authorized".

Dato clave: el plan Free **si** permite **pull request analysis cuando el target es la
main branch**. Un PR `feat/x -> master` cae en ese caso, asi que Sonar puede gatear el
merge sin pagar, siempre que se invoque en modo PR (no en modo branch).

## 2. Decision de CI: CircleCI -> Semaphore

Para correr Sonar en modo PR hace falta pasarle `sonar.pullrequest.key` (numero de PR),
`sonar.pullrequest.branch` y `sonar.pullrequest.base`. CircleCI no entrega el numero de
PR de forma confiable (`CIRCLE_PULL_REQUEST` es fragil), lo que obliga a plomeria extra
(consultar la API de GitHub).

Drivers del cambio:
- **UX**: la UI de CircleCI resulto confusa y poco informativa (el incidente del
  `SONAR_TOKEN` invisible salio del modelo de Contexts vs Project Env Vars).
- **Contexto de PR nativo**: Semaphore expone `SEMAPHORE_GIT_PR_NUMBER`,
  `SEMAPHORE_GIT_PR_BRANCH`, `SEMAPHORE_GIT_PR_SHA`, lo que habilita Sonar en modo PR
  sin hacks.
- **Costo**: plan Free de Semaphore (~$15 de credito / ~2000 min al mes), sin tarjeta.

Se evaluo GitHub Actions como alternativa (tambien gratis, sin tarjeta, contexto de PR
nativo y UI integrada en GitHub). Se eligio Semaphore por preferencia explicita del
usuario sobre su UI; se acepta el costo de tener un tablero externo adicional.

## 3. Estrategia de ramas

Trunk-based development con feature branches de vida corta:

- `master` es el tronco, siempre desplegable. Sin push directo (lo bloquea branch
  protection en GitHub).
- Cada cambio en una rama corta (`feat/...`, `fix/...`, `chore/...`).
- Para entrar a `master`: Pull Request con checks en verde. Sin eso, GitHub no permite
  el merge.

Dos gates:
- **Gate del PR**: el check de Semaphore (Validate) y el check de SonarCloud
  (analisis de PR). Frenan el merge.
- **Gate del deploy**: el resultado del pipeline de CI en `master`. Si Sonar falla en
  master, el deploy no corre.

## 4. Pipeline de Semaphore

Estructura de archivos:

    .semaphore/
      semaphore.yml    # pipeline de CI: blocks Validate + Sonar
      deploy.yml       # pipeline de deploy, disparado por promotion

### 4.1. Pipeline de CI (`semaphore.yml`)

Corre en todo push y en PRs. Blocks:

- **Validate** (siempre): `gofmt -l` (falla si lista algo), `go vet ./...`,
  `go build ./...`, `go test -coverprofile=coverage.out ./...`.
- **Sonar**: decide el modo segun el tipo de ref.
  - Si `SEMAPHORE_GIT_REF_TYPE = pull-request` => modo PR:

        sonar.pullrequest.key=$SEMAPHORE_GIT_PR_NUMBER
        sonar.pullrequest.branch=$SEMAPHORE_GIT_PR_BRANCH
        sonar.pullrequest.base=master

  - Si `branch = master` => modo main (branch analysis de la main branch, con
    `sonar.qualitygate.wait=true`).

El block Sonar referencia el secret `SONAR_TOKEN` y usa `sonar-scanner`.

### 4.2. Deploy por promotion (`deploy.yml`)

Promotion en el pipeline de CI:

    promotions:
      - name: Deploy a Render
        pipeline_file: deploy.yml
        auto_promote:
          when: "branch = 'master' AND result = 'passed'"

Si Sonar (u otro block) falla en master, `result` no es `passed` y la promotion no
dispara: el deploy queda bloqueado.

`deploy.yml` (un block):
- `curl -fsS -X POST "$RENDER_DEPLOY_HOOK_URL"` (dispara el rebuild en Render).
- Smoke test: espera el cold start y reintenta `GET /health` contra
  `https://utn-ics.onrender.com/health`.

## 5. Secrets

En Semaphore (org Settings -> Secrets), referenciados por nombre en los blocks:
- `SONAR_TOKEN`: el User Token actual de SonarCloud (sirve igual; tiene Browse).
- `RENDER_DEPLOY_HOOK_URL`: el Deploy Hook de Render.

No van al repo. El token expuesto durante el debug (`7c9c...`) ya fue revocado.

## 6. Branch protection en GitHub

Settings -> Branches -> regla para `master`:
- Require a pull request before merging (sin push directo).
- Require status checks to pass:
  - check de Semaphore (validacion).
  - "SonarCloud Code Analysis" (el del analisis de PR).

## 7. A confirmar en la primera corrida

Misma disciplina de instrumentar el borde que se uso para el token (un `echo` de los
env vars en la primera corrida), para confirmar:
- El mapeo exacto de `SEMAPHORE_GIT_BRANCH` vs `SEMAPHORE_GIT_PR_BRANCH` para fijar
  bien `sonar.pullrequest.base`.
- El nombre exacto del status check de Semaphore a marcar como requerido en branch
  protection.
- El nombre exacto del agent machine / OS image del tier Free vigente de Semaphore.

## 8. Migracion y limpieza

- Borrar `.circleci/config.yml` (incluido el step temporal de debug del token).
- Crear `.semaphore/semaphore.yml` y `.semaphore/deploy.yml`.
- Conectar el repo en Semaphore via GitHub (sin tarjeta) y cargar los dos secrets.
- Configurar branch protection en `master`.
- Actualizar `docs/plan.md`: estructura de archivos (seccion 3), modelo de ramas
  (seccion 4) y la decision de CI (CircleCI -> Semaphore con su razonamiento).
- Actualizar `CLAUDE.md`: la linea de arquitectura objetivo que hoy nombra CircleCI.

Lo que NO cambia: la app Go, el `Dockerfile`, `sonar-project.properties` (el modo PR
se maneja por parametros del scanner), Render como builder de la imagen, el `SONAR_TOKEN`.

## 9. Criterios de aceptacion

- Un PR `feat/x -> master` dispara en Semaphore los blocks Validate y Sonar (modo PR);
  el analisis de Sonar aparece como check en el PR.
- Con branch protection activa, un PR con Validate o SonarCloud en rojo no se puede
  mergear.
- Al mergear a `master`, corre Validate + Sonar (modo main) y, si todo da passed, la
  promotion dispara el deploy a Render y el smoke test de `/health` pasa.
- Si Sonar falla en `master`, el deploy no corre.
- No queda configuracion de CircleCI en el repo.
