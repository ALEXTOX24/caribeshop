# Respuestas a las preguntas de análisis (sección 6)

> Las respuestas 1 y 2 usan los datos medidos en el despliegue real (`rg-caribeshop-gmb25`, `chilecentral`, `Standard_B2ls_v2`). Evidencias en `evidencias/P1/`.

## 1. ¿Cuántas instancias para 300 RPS con p95 < 500 ms? ¿La cuota alcanza?

Definimos `RPS_500` como el máximo de RPS que **una instancia** sostuvo en P1 manteniendo p95 < 500 ms.

**Capacidad teórica mínima:**

`N_teorico = ceil(300 / RPS_500)`

Para no operar al 100 % de la capacidad medida y conservar margen frente a una falla, recomendamos agregar 20–30 % de holgura o aplicar criterio N+1:

`N_recomendado = max(ceil(300 × 1.25 / RPS_500), N_teorico + 1)`

Valores medidos:

- `RPS_500 = 415,1 RPS` (160 usuarios, p95 = 260 ms; `evidencias/P1/capacidad/resumen_capacidad.csv`)
- `N_teorico = ceil(300 / 415,1) = 1`
- `N_recomendado = max(ceil(375 / 415,1), 1 + 1) = max(1, 2) = 2` instancias

**Importante:** 415,1 RPS es una **cota inferior**. En la prueba escalonada, con ~400 RPS repartidos en 2 instancias, la CPU del VMSS estuvo en ~34 %, lo que indica que el límite lo puso el generador de carga (GitHub Codespace de 2 núcleos) y no la VM. Aun así, el criterio N+1 manda: con 1 instancia se cumpliría el rendimiento, pero no la tolerancia a falla, porque la prueba de falla abrupta (P2.2) mostró que al perder una instancia la otra debe absorber toda la carga.

La viabilidad de cuota se validó con:

```bash
az vm list-usage -l chilecentral -o table
```

`Standard_B2ls_v2` usa 2 vCPU por instancia. La cuota necesaria es `2 × N_recomendado = 4 vCPU`. La suscripción Azure for Students tiene **6 vCPU regionales** (familia Bsv2: 10), así que **la cuota alcanza** para las 2 instancias recomendadas y permite crecer hasta un máximo de **3** (6 vCPU), que es el máximo configurado en el VMSS.

## 2. El autoscale tardó cierto tiempo. ¿Qué haría para un pico súbito a las 8:00 p. m.?

Medimos (prueba escalonada, umbral de scale-out 35 % sobre el promedio de 5 min):

- `T_threshold = 18:57 UTC`: primer minuto con CPU promedio > 35 % (37,0 %).
- Decisión de scale-out: `18:59:47 UTC` (~2,8 min después).
- `T_healthy = 19:01:35 UTC`: la tercera instancia queda sana y recibe tráfico.
- `Tiempo_reaccion = T_healthy - T_threshold ≈ 4,6 min (~275 s)`.

Durante esos ~4,6 min el sistema atendió el pico con 2 instancias (CPU ~42 %, p95 máximo 1 400 ms). Para un pico súbito no basta con reaccionar por CPU.

Un pico conocido a las 8:00 p. m. no debería depender únicamente de reacción por CPU. Configuraría un **perfil programado** que eleve la capacidad mínima al menos **10 minutos antes** (por ejemplo 7:50 p. m., más del doble del tiempo de reacción medido), mantenga capacidad elevada durante la ventana de campaña y luego devuelva el mínimo gradualmente. Con la cuota actual el máximo es 3 instancias; para campañas mayores habría que pedir más cuota o usar una suscripción con más capacidad. Con suficiente historial, evaluaría autoscale predictivo para anticipar patrones repetitivos.

Para picos no programados mantendría histéresis: scale-out más agresivo (ventana de 5 min reducida o umbral menor, porque la medición mostró ~2,8 min solo para decidir), pero scale-in conservador (umbral 15 %, ventana de 10 min y cooldown de 10 min, que en la prueba devolvió el VMSS a 2 instancias sin oscilaciones).

## 3. ¿Qué componente es ahora el punto único de falla? ¿Cuánto costaría eliminarlo?

Después de distribuir el VMSS en al menos dos zonas y usar Standard Load Balancer/IP zonal-redundante, el principal dominio de falla restante es **la región Azure** (`chilecentral`). Una caída regional puede afectar simultáneamente compute, entrada y servicios regionales como Key Vault.

Para eliminar ese SPOF se requiere arquitectura multi-región: segundo VMSS/LB o plataforma equivalente, réplica/estrategia de secretos y datos, y un balanceador global como Azure Front Door o Traffic Manager. En orden de magnitud, el costo de la capa regional de cómputo se acerca a duplicarse, más el servicio global y la replicación de datos. El valor definitivo debe salir de Azure Pricing Calculator con los mismos SKU y el patrón de tráfico real. En la suscripción Azure for Students, además, la segunda región tendría que ser otra de las permitidas con zonas, capacidad para el SKU y soporte de Trusted Launch, condiciones que en este laboratorio solo cumplió `chilecentral` (ver INFORME, sección 2.1).

No consideramos Log Analytics, Policy ni el backend de Terraform parte del *hot path* HTTP: su falla afecta observabilidad, gobierno o despliegue, pero no necesariamente cada solicitud ya atendida por instancias existentes.

## 4. Si un atacante obtiene ejecución de código en una instancia, ¿qué puede y qué no puede hacer?

### Lo que sí podría hacer

1. Consultar IMDS desde la VM y obtener un token de la **Managed Identity** del VMSS.
2. Usar ese token para leer el secreto permitido por `Key Vault Secrets User` desde la subnet autorizada.
3. Manipular el proceso local, generar carga, marcar `/health` no sano o intentar afectar disponibilidad de esa instancia.
4. Si controla la respuesta HTTP de la aplicación, podría intentar exfiltrar datos por una conexión entrante ya establecida; por eso el filtrado de egress reduce riesgo, pero no sustituye controles del proceso y aplicación.

### Lo que los controles impiden o limitan

- No tiene rol para crear, cambiar o borrar secretos de Key Vault.
- La identidad del VMSS no puede asignar roles ni crear recursos Azure.
- No puede leer el backend Terraform por esa identidad porque no tiene rol de Storage sobre el estado.
- No existe IP pública por VM ni SSH/RDP abierto a Internet.
- El NSG bloquea salida arbitraria a Internet y tráfico lateral general; solo se permiten dependencias necesarias como Key Vault, DNS de plataforma e IMDS. La prueba P3.2 lo comprobó: desde la instancia 8, `example.com`, `www.google.com` y `github.com` quedaron bloqueados y Key Vault siguió alcanzable.
- El Load Balancer retira una instancia con `/health` 503 y la reparación automática la reemplaza (P2.1: 0 fallas en Locust y reemplazo en ~11,7 min).

Esto demuestra defensa en profundidad, pero también una conclusión importante: **Managed Identity no evita que un proceso comprometido use los permisos de esa identidad**. Por eso el rol debe ser mínimo y el secreto debe rotarse inmediatamente tras una intrusión.

## 5. ¿Por qué Checkov en el pipeline no sustituye Azure Policy, ni viceversa?

**Checkov** actúa antes del despliegue sobre el código IaC. Da retroalimentación rápida en el PR y detecta configuraciones inseguras antes de que lleguen a Azure. En D1 bloqueó el PR #1 que abría SSH a Internet (`CKV_AZURE_10`). Sin embargo, puede ser omitido, mal configurado, no ver cambios hechos fuera de Terraform o no cubrir todos los controles de la plataforma.

**Azure Policy** actúa en el plano de control de Azure y puede denegar una operación aunque alguien intente crear el recurso desde Portal, CLI u otro pipeline. En P3.3 rechazó con `RequestDisallowedByPolicy` un Storage Account sin HTTPS creado directamente con Azure CLI, fuera del pipeline. En cambio, Policy no reemplaza la revisión temprana del código, no comprende toda la lógica de scripts/app y su mensaje llega más tarde, al intentar crear/modificar el recurso.

La estrategia correcta es **shift-left + guardrail en runtime/control plane**: Checkov previene y enseña durante el PR; Azure Policy impide que una configuración prohibida exista aunque el pipeline sea eludido.

## 6. El estado Terraform contiene secretos. ¿Cómo se protegió y qué pasaría si se filtrara?

Se protege con:

- Azure Blob como backend remoto, no archivo local compartido.
- autenticación Microsoft Entra ID (`use_azuread_auth=true`), no Access Key en código;
- `shared_access_key_enabled=false` en el Storage Account;
- rol `Storage Blob Data Contributor` limitado al operador autorizado;
- HTTPS obligatorio, TLS 1.2, ZRS, versionado y soft delete;
- `.gitignore` bloqueando `*.tfstate`, `*.tfvars`, planes y llaves; `scripts/repo-safety-check.sh` lo verificó antes de cada push.

El diseño original incluía firewall con `default_action=Deny` y solo la IP del operador. En el despliegue real, el operador trabajó desde GitHub Codespaces, que corre dentro de Azure; las reglas de IP del Storage no aplican a ese tráfico interno y Terraform recibía `403 AuthorizationFailure` aun con la IP autorizada. Se cambió a `default_action=Allow`: el acceso al estado sigue exigiendo identidad Entra ID con el rol de datos, pero se pierde la capa de red. Es un riesgo aceptado del laboratorio; en producción se usaría un Private Endpoint o un runner con IP fija fuera de Azure.

Aun así, el estado debe considerarse **sensible**: `random_password.db.result` y el valor aplicado a `azurerm_key_vault_secret` pueden quedar almacenados en el state. Si se filtra, se asume comprometido todo secreto presente: rotar inmediatamente `db-password`, revocar accesos sospechosos, revisar Activity/Storage/Key Vault logs, corregir la vía de filtración y generar un nuevo estado/credencial cuando corresponda. Marcar un output como `sensitive` solo oculta la pantalla; no elimina el dato del state.
