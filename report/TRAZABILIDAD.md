# Matriz de trazabilidad CaribeShop

| ID | Archivo / recurso Terraform | Evidencia (generada por los scripts) |
|---|---|---|
| S1 | `bootstrap/` (Storage + contenedor `tfstate`); `infra/versions.tf` → `backend "azurerm"`; `.gitignore` | `evidencias/base/S1_estado_remoto.txt` (blobs de estado remoto, `.gitignore`, historial de Git limpio) |
| S2 | `infra/network.tf`: `azurerm_virtual_network.main`, `azurerm_subnet.app`, `azurerm_network_security_group.app`; `infra/compute.tf`: NIC sin IP pública | `evidencias/base/S2_red_sin_ip_publica.txt` (IPs públicas vacío + reglas NSG) |
| S3 | `infra/keyvault.tf`: `azurerm_key_vault.main` (RBAC, purge protection, `network_acls`), `azurerm_key_vault_secret.db` (expiración 90 d); `app/app.py` (IMDS + REST) | `evidencias/base/S3_keyvault_secreto.txt` (`/secret-check` con longitud y SHA-256 truncado) |
| S4 | `infra/compute.tf`: `azurerm_role_assignment.vmss_keyvault_reader` (`Key Vault Secrets User`) | `evidencias/base/S4_roles_identidad_vmss.txt` |
| S5 | `infra/policy.tf`: definición + `azurerm_resource_group_policy_assignment.deny_insecure_storage` | `evidencias/base/S5_policy_deny.txt`, `evidencias/P3/P3_3_policy_deny.txt` (`RequestDisallowedByPolicy`) |
| S6 | `infra/keyvault.tf`: `azurerm_monitor_diagnostic_setting.keyvault` (`AuditEvent` → Log Analytics) | `evidencias/base/S6_consulta.kql`, `S6_kql_resultado.txt` (OID = `vmss_principal_id`) |
| E1 | `infra/compute.tf`: `zones = ["1","2"]`, `zone_balance = true`, mínimo 2 | `evidencias/base/E1_instancias_zonas.txt` |
| E2 | `infra/loadbalancer.tf`: `azurerm_lb_probe.health` (HTTP `/health`, 5 s) | `evidencias/base/E2_sonda.txt`, `E2_health_probe_status.json` (métrica *Health Probe Status*) |
| E3 | `infra/autoscale-monitoring.tf`: >70 % (5 min, +2, cooldown 5 min) / <30 % (10 min, −2, cooldown 10 min); `ignore_changes = [instances]` | `evidencias/P1/escalonado/` (instancias en el tiempo, eventos de autoscale) + `evidencias/graficos/p1_escalonado_alineado.png` |
| E4 | `infra/compute.tf`: `automatic_instance_repair` (`Replace`, gracia 10 min) | `evidencias/P2/falla_logica/eventos.json` (`reparada_epoch`), `E4_activity_log.txt` |
| E5 | `infra/autoscale-monitoring.tf`: `azurerm_monitor_action_group.ops`, `azurerm_monitor_metric_alert.high_cpu` | `evidencias/P1/escalonado/E5_alertas_disparadas.txt` + captura del correo |
| D1 | `.github/workflows/terraform-security.yml` | `evidencias/D1/` (PR fallido por `CKV_AZURE_10` y su corrección) |
| D2 | `#checkov:skip` en `infra/*.tf` y `bootstrap/main.tf` | `report/RIESGOS.md` |
| D3 | `infra/cloud-init.yaml.tftpl` + `app/caribeshop.service` | `evidencias/base/D3_cloudinit_app.txt` (instancias nuevas sirven sin pasos manuales) |
