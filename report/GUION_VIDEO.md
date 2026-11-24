# Guion del video (6–8 minutos)

Repartir las partes entre todos los integrantes. El objetivo no es explicar cada línea de Terraform, sino demostrar que la plataforma ya desplegada cumple los controles y reacciona a carga/falla.

## 0:00–0:45 — contexto y arquitectura

- Mostrar diagrama.
- Explicar en una frase cada riesgo inicial: saturación, VM única, secreto en repo/SSH expuesto.
- Señalar: Standard LB → VMSS multi-zona → Managed Identity → Key Vault; Log Analytics/Monitor; Policy; GitHub Actions.

## 0:45–1:45 — seguridad

- Mostrar VMSS sin IP pública.
- Mostrar NSG sin 22/3389.
- Ejecutar `curl <URL>/secret-check`: resaltar que solo devuelve longitud/hash.
- Mostrar rol `Key Vault Secrets User` de la Managed Identity.

## 1:45–2:30 — DevSecOps

- Abrir GitHub Actions.
- Mostrar PR donde Checkov falló por la vulnerabilidad intencional.
- Mostrar corrección y ejecución verde.
- Mencionar que Azure Policy complementa el pipeline.

## 2:30–4:45 — carga y scale-out

- Tener Locust listo antes de grabar.
- Iniciar la carga escalonada o una carga más corta que ya sepan que cruza CPU 70 %.
- Mostrar Azure Monitor/VMSS y la aparición de nuevas instancias.
- Explicar el umbral, ventana y cooldown configurados.
- Si el scale-out real tarda demasiado para el video, pueden mostrar el historial de una ejecución previa y, simultáneamente, una prueba corta en vivo. No simulen datos.

## 4:45–6:15 — prueba de falla

- Elegir una instancia.
- Ejecutar Run Command que crea `/tmp/caribeshop-unhealthy`.
- Mostrar `/health` 503 en esa instancia / Health Probe degradado y que el LB mantiene servicio con otras instancias.
- Opcionalmente mostrar una eliminación abrupta de instancia si el tiempo lo permite.
- Mencionar el porcentaje de error medido en la prueba formal.

## 6:15–7:15 — observabilidad y gobierno

- Mostrar KQL `SecretGet` en Log Analytics.
- Mostrar historial/correo de la alerta.
- Mostrar la prueba de Azure Policy Deny.

## 7:15–8:00 — cierre

- Resumir resultados medidos: RPS, p95, tiempo de scale-out, error % de fallas.
- Mostrar `terraform destroy` ya preparado o explicar que se ejecutará al terminar evidencias.
- Confirmar que todos los integrantes participaron.
