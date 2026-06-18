# Runbook: deploy roto / master roto

Que hacer cuando un deploy a prod sale mal. La idea central: **rollback de deploy y
rollback de codigo son dos cosas distintas**, y hacen falta las dos.

- **Rollback de deploy** = revertir lo que corre en prod. Para la hemorragia (segundos).
- **Revert PR** = deshacer el commit roto en master. Restaura la invariante "master
  siempre desplegable". master no se arregla sola con el rollback de prod.

## Como nos enteramos

- Alerta de Telegram (del pipeline de deploy o del script de rollback).
- El smoke test post-deploy en rojo (en Semaphore, pipeline "Deploy a Render").

## Que pasa automaticamente

Segun lo que rompio:

1. **La app no levanta / crashea / `/health` no da 200.** El health-check gate de Render
   no switchea el trafico: deja viva la version anterior. Prod nunca ve la version rota.
   (Requiere Health Check Path = `/health` configurado en Render.)
2. **La app levanta pero responde mal** (regresion logica que el `/health` no atrapa).
   El smoke funcional falla. Si el rollback por API esta activado
   (`.semaphore/scripts/rollback-render.sh`), revierte prod al deploy anterior.

En ambos casos llega una alerta a Telegram con el comando de revert.

## Que tenes que hacer vos (en orden)

1. **Confirmar que prod esta sano.** Abrir https://utn-ics.onrender.com/health (200)
   y https://utn-ics.onrender.com/version (que el commit sea el bueno, no el roto).
   Si prod sigue roto, hacer rollback manual: Render dashboard > el servicio > pestania
   "Events" o "Deploys" > "Rollback" en el ultimo deploy bueno.
2. **Restaurar master con un revert PR** (esto es lo que la gente olvida):
   ```
   git fetch origin master
   git switch -c fix/revert-<algo> origin/master
   git revert -m 1 <sha-del-merge-roto>   # -m 1 si es un merge commit; sin -m si es commit normal
   git push -u origin fix/revert-<algo>
   ```
   Abrir el PR. Pasa por el MISMO pipeline (Validate + Security + Sonar + smoke) y al
   mergear re-deploya la version buena desde master. NO usar `push --force` a master
   (esta protegida y reescribir historia compartida es peor que el incidente).
3. **Agregar un test de regresion** que reproduzca la falla. Si el CI estaba verde y aun
   asi rompio, es que faltaba un test: sin el, vas a tropezar con la misma piedra.
4. **Fix-forward** real en otro PR, con calma, cuando entiendas la causa raiz.

## Por que no automatizamos el revert PR

Automatizar reverts es delicado (un falso positivo del smoke revertiria un cambio bueno).
Preferimos: rollback automatico de deploy (reversible, de bajo riesgo) + alerta clara con
el comando exacto + revert manual. El humano decide el revert.
