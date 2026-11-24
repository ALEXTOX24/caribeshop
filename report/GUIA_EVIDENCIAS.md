# Guía de evidencias

Guarde todo en `evidencias/` con nombres consistentes. Esta carpeta está ignorada por Git salvo `.gitkeep`; si el docente exige evidencias en el repositorio, quite esa exclusión **solo para archivos no sensibles**.

## Seguridad

- `S1_backend_remoto.png` — Storage/container del estado + RBAC/firewall.
- `S1_gitignore.png` — `.gitignore` y búsqueda sin `.tfstate`/secretos.
- `S2_vmss_sin_ip_publica.txt` — salida de `az vmss list-instance-public-ips` vacía.
- `S2_nsg.png` — reglas de entrada/salida; sin 22/3389.
- `S3_secret_check.json` — `/secret-check` con longitud/hash, sin valor.
- `S3_kv_firewall.png` — subnet + IP operador + default Deny.
- `S4_role_vmss.txt` — rol `Key Vault Secrets User`.
- `S5_policy_deny.txt` — error de Policy al intentar Storage sin HTTPS.
- `S6_kql_secretget.png` — KQL con `SecretGet` y OID.

## Escalamiento / HA

- `E1_zonas_vmss.txt` — lista de instancias y zona.
- `E2_health_probe.png` — código/métrica del probe.
- `E3_autoscale_history.png` — scale-out/scale-in.
- `E4_auto_repair_before_after.png` — ID de instancia antes y después del reemplazo.
- `E5_alert_email.png` — correo de alerta o historial de Azure Monitor.

## DevSecOps

- `D1_pr_checkov_falla.png` — PR con hallazgo intencional.
- `D1_pr_corregido.png` — mismo PR/commit corregido y verde.
- `D3_cloud_init.png` — código + servicio funcionando sin login manual.

## P1

- `P1_capacity_*.csv` y `.html` — barrido de capacidad de una instancia.
- `P1_step25_*.csv` y `.html` — perfil escalonado 25 min.
- `P1_instances_vs_rps_p95.png` — gráfico temporal alineado.

## P2

- `P2_logical.csv` — timestamp, total, fallidas, porcentaje error, tiempo de retiro.
- `P2_abrupt.csv` — timestamp, total, fallidas, porcentaje error, recuperación.

## P3

- `P3_kv_denied_cloudshell.txt` — acceso negado por firewall.
- `P3_egress_blocked.txt` — destinos arbitrarios bloqueados.
- `P3_policy_deny.txt` — rechazo de Azure Policy.

## Datos que NO deben entrar al repositorio/informe

- valor real del secreto;
- `.tfstate` o copias;
- llaves privadas SSH;
- tokens/access keys/SAS;
- `.tfvars` con datos reales si contienen información sensible.
