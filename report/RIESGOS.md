# Riesgos aceptados y mitigaciones

Cada excepción de Checkov incluida en Terraform aparece en esta tabla con su motivo y el control que permanece activo.

| Checkov / riesgo | Motivo de aceptación en el laboratorio | Impacto | Mitigación aplicada |
|---|---|---|---|
| `CKV_AZURE_160` — HTTP público | La arquitectura de referencia expone HTTP y el laboratorio evalúa identidad, red, autoscale y HA | El tráfico cliente no está cifrado | No se usan datos reales y los secretos no se devuelven al cliente |
| `CKV_AZURE_97` — cifrado en host | Azure for Students no tiene habilitada la feature `Microsoft.Compute/EncryptionAtHost` | El cifrado en host no se añade a los discos del VMSS | Secure Boot, vTPM y discos `Premium_LRS` permanecen activos |
| `CKV_AZURE_182` — dos DNS endpoints | Se utiliza el DNS administrado de Azure; no se despliega un resolver adicional | Dependencia del resolvedor administrado | La aplicación usa el servicio DNS de la VNet y el NSG restringe el tráfico saliente |
| `CKV_AZURE_183` — DNS local/custom | El DNS personalizado no forma parte de la arquitectura entregada | Menor control sobre resolución y filtrado DNS | Se mantiene el resolvedor de Azure y se restringe el egress |
| `CKV_AZURE_189` — Key Vault con endpoint público habilitado | S3 exige probar firewall por **subred + IP del operador** desde una red autorizada y otra no autorizada | Existe endpoint público protegido por reglas de red | `default_action=Deny`, subnet del VMSS, IP del operador y RBAC |
| `CKV2_AZURE_32` — Key Vault sin Private Endpoint | El laboratorio usa el firewall público para la prueba negativa | El endpoint público sigue siendo una superficie de exposición | Acceso limitado por subnet/IP y denegado por defecto |
| `CKV_AZURE_33`, `CKV_AZURE_59`, `CKV_AZURE_206`, `CKV2_AZURE_1`, `CKV2_AZURE_33` — backend Terraform | El backend debe ser accesible por los operadores y usa el endpoint público con allowlist | No se aplican logging Blob, CMK ni Private Endpoint | OAuth/Entra ID, Shared Key deshabilitada, TLS 1.2, ZRS, firewall y versionado |
| `CKV2_AZURE_21` — logging del contenedor de estado | El contenedor solo almacena el estado de Terraform | Menor trazabilidad de operaciones Blob | Contenedor privado, RBAC, versionado y retención |
| Estado Terraform contiene el secreto generado | Terraform crea el secreto y el estado puede contener valores sensibles | Una filtración del estado podría revelar el secreto | Backend remoto, Entra ID, firewall, ZRS, versionado y `.gitignore` |
| Ejecución de código en una VM | Una RCE podría consultar IMDS y utilizar la identidad administrada | Podría leer el secreto asignado al VMSS | Rol de solo lectura, egress restringido, sin IP pública ni SSH |
| Región Azure como dominio de falla | El alcance exige redundancia entre zonas, no entre regiones | Una caída regional interrumpe el servicio | VMSS en dos zonas y Standard Load Balancer |

## Riesgos aceptados por el despliegue en Azure for Students

| Riesgo | Causa | Impacto | Control / mitigación |
|---|---|---|---|
| Firewall del Storage del estado Terraform en `default_action=Allow` | Las reglas de IP del Storage no aplican al tráfico desde GitHub Codespaces (red interna de Azure); con `Deny` Terraform recibía 403 | Se pierde la capa de red sobre el backend del estado | Acceso solo con identidad Entra ID y rol `Storage Blob Data Contributor`; shared keys deshabilitadas; HTTPS/TLS 1.2. En producción: Private Endpoint o runner con IP fija |
| Región única `chilecentral` | Política de la suscripción (5 regiones permitidas) y disponibilidad de SKU/capacidad | Una caída regional interrumpe el servicio | VMSS en 2 zonas + LB/IP zonal-redundante |
| Máximo 3 instancias | Cuota de 6 vCPU regionales | Techo de escalado para picos grandes | Perfil programado ante campañas; solicitar cuota en producción |
| VMs serie B (burstable) | Familias D con cuota 0 | Rendimiento dependiente de créditos de CPU | Créditos monitoreados durante P1 (no se agotaron) |
| Umbrales de autoscale 35/15 % y alerta 40 % | La app Python de un proceso usa 1 de 2 vCPU (GIL) | `Percentage CPU` no supera ~50 % | Umbrales recalculados sobre la CPU utilizable; alternativa: varios procesos por VM |
| Capacidad no restaurada tras eliminar una instancia | `az vmss delete-instances` reduce la capacidad deseada y el autoscale no lo detectó (`ObservedCapacity` = 2) | Operación con 1 instancia hasta intervención manual | Alerta recomendada sobre instancias sanas < 2; restauración con `az vmss scale` |
