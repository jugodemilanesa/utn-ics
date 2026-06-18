# Diseno: Feedback a Telegram desde el pipeline

Fecha: 2026-06-18. Estado: aprobado, listo para plan de implementacion.

## Objetivo

Cerrar la pieza "Mecanismo de Alertas" del diagrama (plan.md seccion 2.F): que el
pipeline de Semaphore avise por Telegram el resultado de los eventos relevantes, de
forma vistosa para la demo pero sin spamear.

## Alcance

- **Dentro:** notificaciones a Telegram para deploy (exito/falla), CI roto en master,
  y resultado del pipeline de PR (Sonar).
- **Fuera (fase siguiente):** Trello. Se descarto a proposito para hacer Telegram
  primero, incremental. El script de notificacion queda como pieza reutilizable para
  esa fase.

## Decisiones de diseno (con el porque)

1. **`after_pipeline` en vez de `epilogue`.** El `epilogue` de un task NO corre si el
   job fue stopped/canceled/timed-out. Como el pipeline tiene `fail_fast: stop`, si
   Validate falla en master, Sonar queda *canceled* y su epilogue no correria. El
   `after_pipeline` corre SIEMPRE (passed/failed/stopped/canceled) y expone el
   resultado del pipeline, asi que es el mecanismo correcto para notificar fallos.

2. **Un script compartido, no curl inline.** La logica del mensaje (estado, evento,
   commit, link, URL de la app, decision de a quien notificar) vive en un unico
   `.semaphore/scripts/notify-telegram.sh`, versionado, testeable con `shellcheck` y
   corrible local. Los dos pipelines solo hacen `checkout` + llaman al script. Evita
   duplicar la logica entre `semaphore.yml` y `deploy.yml`.

3. **Las notificaciones no gatean.** Una notificacion que falla no debe romper el
   build: el `curl` no usa `-f` y el script siempre sale 0. Ademas un `after_pipeline`
   que falla no tumba el pipeline. El objetivo es avisar, no bloquear.

4. **Toda la decision en el script (YAML fino).** El `after_pipeline` de cada pipeline
   llama al script con un modo (`ci` o `deploy`); el script inspecciona el contexto y
   decide que mensaje mandar (o ninguno).

## Componentes

### Secret de Semaphore: `telegram`
Contiene `TELEGRAM_TOKEN` y `TELEGRAM_CHAT_ID`. Se referencia por nombre en el task del
`after_pipeline` de ambos pipelines. Nunca en el repo. (Lo crea el usuario en la UI,
igual que `sonarcloud` y `render`.)

### Script: `.semaphore/scripts/notify-telegram.sh <modo>`
`<modo>` es `ci` o `deploy`. Logica:

| Modo | Condicion | Notifica |
|------|-----------|----------|
| `ci` | build de PR (`SEMAPHORE_GIT_REF_TYPE = pull-request`) | `PR #<n>: analisis EXITO/FALLA` |
| `ci` | push a master (`branch = master`, no PR) y resultado != passed | `FALLA / CI en master` |
| `ci` | push a master con resultado passed | nada (exit 0); de eso avisa el deploy |
| `ci` | cualquier otra (push a rama sin PR) | nada (exit 0) |
| `deploy` | resultado = passed | `EXITO / Deploy` + URL de la app |
| `deploy` | resultado != passed | `FALLA / Deploy` |

Estado derivado de `SEMAPHORE_PIPELINE_RESULT`: `passed` -> `EXITO`, cualquier otro
(`failed`/`stopped`/`canceled`) -> `FALLA`.

### Hooks `after_pipeline`
- En `semaphore.yml`: un `after_pipeline` con un job que hace `checkout` y corre
  `bash .semaphore/scripts/notify-telegram.sh ci`. Task con `secrets: [telegram]`.
- En `deploy.yml`: idem con `bash .semaphore/scripts/notify-telegram.sh deploy`.

## Formato del mensaje

Texto plano, sin emojis (convencion del proyecto; estados en texto: `EXITO`/`FALLA`).
Ejemplo deploy OK:

```
[EXITO] Deploy
rama: master
commit: 52314e5
workflow: https://utn-ics.semaphoreci.com/workflows/<id>
app: https://utn-ics.onrender.com
```

Ejemplo PR:

```
[FALLA] PR #7: analisis
rama: feat/notify-telegram
commit: 273e1e3
workflow: https://utn-ics.semaphoreci.com/workflows/<id>
```

La URL de la app solo aparece en el deploy con exito. Se manda con `parse_mode=HTML` y
`--data-urlencode` para el texto (multilinea seguro).

## Variables de entorno usadas (confirmadas en docs)

- `SEMAPHORE_PIPELINE_RESULT`: resultado del pipeline (`passed`/`failed`/`stopped`/`canceled`). Solo en `after_pipeline`.
- `SEMAPHORE_GIT_REF_TYPE`: `branch` / `pull-request` / `tag`.
- `SEMAPHORE_GIT_BRANCH`: rama (en build de PR = rama destino, p.ej. master).
- `SEMAPHORE_GIT_PR_NUMBER`: numero de PR (solo en build de PR).
- `SEMAPHORE_GIT_SHA`: commit (se corta a 7 con `cut -c1-7`).
- `SEMAPHORE_ORGANIZATION_URL` + `SEMAPHORE_WORKFLOW_ID`: link al workflow.

## Manejo de errores

- `curl` sin `-f`; el script termina con `exit 0` pase lo que pase con la red.
- Si faltara `TELEGRAM_TOKEN`/`CHAT_ID` (secret mal cargado), el script loguea un aviso
  y sale 0 (no rompe el pipeline).

## Testing

- `shellcheck .semaphore/scripts/notify-telegram.sh`.
- Render local: correr el script con env vars falsas (simular cada caso de la tabla) y
  un flag/var de "dry-run" que imprima el mensaje y el curl en vez de mandarlo, para
  ver los textos sin depender del pipeline ni mandar mensajes reales.
- Camino real EXITO/Deploy: se verifica en el proximo merge a master.
- Camino real PR: se verifica abriendo el PR de esta misma feature (deberia llegar el
  mensaje "PR #N: analisis ...").
- Camino FALLA/CI-en-master: dificil de probar sin romper master a proposito; se valida
  por la logica del script en local (dry-run con `SEMAPHORE_PIPELINE_RESULT=failed` y
  `branch=master`), no rompiendo el tronco.

## Prerrequisitos del usuario (antes de implementar)

1. Crear el bot con `@BotFather` (`/newbot`) -> obtener `TELEGRAM_TOKEN`.
2. Mandarle un mensaje al bot y obtener el `CHAT_ID` (p.ej. `getUpdates` y leer
   `chat.id`).
3. Cargar el secret `telegram` en Semaphore con ambas claves.

## Fase siguiente (fuera de este spec)

Trello: representar el resultado en un tablero. Decision pendiente: crear una tarjeta
por evento (feed) vs mover una tarjeta fija entre listas. Reutilizara el patron del
`after_pipeline` + script.
