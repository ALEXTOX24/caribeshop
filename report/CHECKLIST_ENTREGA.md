# Checklist final

## Antes de pruebas

- [ ] `az vm list-usage -l <region> -o table` revisado.
- [ ] `terraform fmt -check -recursive` pasa.
- [ ] `terraform validate` pasa en `bootstrap/` e `infra/`.
- [ ] Checkov sin fallos no justificados.
- [ ] `scripts/repo-safety-check.sh` pasa.
- [ ] Backend remoto creado y estado migrado.

## Seguridad

- [ ] Ninguna VM tiene IP pública.
- [ ] No existe Allow 22/3389 desde Internet.
- [ ] `/secret-check` demuestra lectura sin mostrar secreto.
- [ ] Managed Identity solo tiene `Key Vault Secrets User` sobre el vault.
- [ ] Key Vault: RBAC + purge protection + firewall + secreto expiración.
- [ ] Policy Deny probada con rechazo real.
- [ ] KQL muestra `SecretGet` del VMSS.

## Escalamiento y HA

- [ ] Al menos dos instancias en al menos dos zonas.
- [ ] Probe `/health` y métrica de salud evidenciados.
- [ ] Scale-out y scale-in observados.
- [ ] Reparación automática evidenciada.
- [ ] Alerta por correo/historial evidenciada.

## P1/P2/P3

- [ ] Capacidad de una instancia medida hasta p95 > 1 s.
- [ ] RPS máximo sostenible registrado.
- [ ] Prueba escalonada ≥25 min con CSV + HTML.
- [ ] Gráficos RPS/p95/instancias alineados en tiempo.
- [ ] Falla lógica: retiro de tráfico + error %.
- [ ] Falla abrupta: recuperación + error %.
- [ ] Cloud Shell/no autorizada no puede leer Key Vault.
- [ ] Egress arbitrario bloqueado o justificado.
- [ ] Policy S5 violada y rechazada.

## Repositorio / informe / video

- [ ] Código Terraform organizado, variables/outputs sin secretos.
- [ ] `locustfile.py` incluido.
- [ ] Dos PR cerrados; uno muestra fallo de seguridad y corrección.
- [ ] README contiene arquitectura, desplegar/destruir, variables y checklist.
- [ ] Informe ≤12 páginas sin anexos.
- [ ] Trazabilidad S1…D3 completa.
- [ ] SLA compuesto calculado y fuentes SLA citadas.
- [ ] Costos actualizados desde Azure Pricing Calculator.
- [ ] Preguntas de análisis contestadas con datos propios donde aplica.
- [ ] Video 6–8 min; todos participan.
- [ ] Recursos destruidos y verificados en Portal.
