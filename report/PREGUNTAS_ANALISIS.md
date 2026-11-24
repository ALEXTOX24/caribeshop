# Respuestas a las preguntas de análisis (sección 6)

> Las respuestas 1 y 2 dependen de datos medidos. No reemplace los campos `[MEDIDO]` con valores inventados. La fórmula y el razonamiento ya están listos.

## 1. ¿Cuántas instancias para 300 RPS con p95 < 500 ms? ¿La cuota alcanza?

Definimos `RPS_500` como el máximo de RPS que **una instancia** sostuvo en P1 manteniendo p95 < 500 ms.

**Capacidad teórica mínima:**

`N_teorico = ceil(300 / RPS_500)`

Para no operar al 100 % de la capacidad medida y conservar margen frente a una falla, recomendamos agregar 20–30 % de holgura o aplicar criterio N+1:

`N_recomendado = max(ceil(300 × 1.25 / RPS_500), N_teorico + 1)`

En el informe sustituyan:

- `RPS_500 = [MEDIDO] RPS`
- `N_teorico = ceil(300 / [MEDIDO]) = [RESULTADO]`
- `N_recomendado = [RESULTADO CON MARGEN]`

**Ejemplo ilustrativo, no resultado del laboratorio:** si una instancia soportara 75 RPS a p95 < 500 ms, `ceil(300/75)=4`, pero se recomendarían 5 o 6 instancias para margen y tolerancia de falla.

La viabilidad de cuota se valida con:

```bash
az vm list-usage -l belgiumcentral -o table
```

`Standard_D2as_v4` usa 2 vCPU por instancia. La cuota de vCPU necesaria para el VMSS es aproximadamente `2 × N_recomendado`, además de cualquier otro recurso de la suscripción. El despliegue actual usa dos instancias y puede crecer hasta cuatro. El valor final debe compararse con la cuota disponible y con el `RPS_500` medido.

## 2. El autoscale tardó cierto tiempo. ¿Qué haría para un pico súbito a las 8:00 p. m.?

Medimos:

- `T_threshold = [MEDIDO]`: instante en que se supera el umbral de scale-out.
- `T_healthy = [MEDIDO]`: instante en que las nuevas instancias quedan sanas y reciben tráfico.
- `Tiempo_reaccion = T_healthy - T_threshold = [MEDIDO]`.

Un pico conocido a las 8:00 p. m. no debería depender únicamente de reacción por CPU. Configuraría un **perfil programado** que eleve la capacidad mínima 10–20 minutos antes (por ejemplo 7:40 p. m.), mantenga capacidad elevada durante la ventana de campaña y luego devuelva el mínimo gradualmente. Con suficiente historial, evaluaría autoscale predictivo para anticipar patrones repetitivos.

Para picos no programados mantendría histéresis: scale-out agresivo (umbral menor o ventana más corta si las pruebas muestran demora), pero scale-in conservador (umbral 30 %, ventana y cooldown de 10 min) para evitar oscilaciones. La configuración final debe basarse en el tiempo real de arranque observado, no en una cifra teórica.

## 3. ¿Qué componente es ahora el punto único de falla? ¿Cuánto costaría eliminarlo?

Después de distribuir el VMSS en al menos dos zonas y usar Standard Load Balancer/IP zonal-redundante, el principal dominio de falla restante es **la región Azure**. Una caída regional puede afectar simultáneamente compute, entrada y servicios regionales como Key Vault.

Para eliminar ese SPOF se requiere arquitectura multi-región: segundo VMSS/LB o plataforma equivalente, réplica/estrategia de secretos y datos, y un balanceador global como Azure Front Door o Traffic Manager. En orden de magnitud, el costo de la capa regional de cómputo se acerca a duplicarse, más el servicio global y la replicación de datos. El valor definitivo debe salir de Azure Pricing Calculator con los mismos SKU y el patrón de tráfico real.

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
- El NSG bloquea salida arbitraria a Internet y tráfico lateral general; solo se permiten dependencias necesarias como Key Vault, DNS de plataforma e IMDS.
- El Load Balancer retira una instancia con `/health` 503 y la reparación automática puede reemplazarla.

Esto demuestra defensa en profundidad, pero también una conclusión importante: **Managed Identity no evita que un proceso comprometido use los permisos de esa identidad**. Por eso el rol debe ser mínimo y el secreto debe rotarse inmediatamente tras una intrusión.

## 5. ¿Por qué Checkov en el pipeline no sustituye Azure Policy, ni viceversa?

**Checkov** actúa antes del despliegue sobre el código IaC. Da retroalimentación rápida en el PR y detecta configuraciones inseguras antes de que lleguen a Azure. Sin embargo, puede ser omitido, mal configurado, no ver cambios hechos fuera de Terraform o no cubrir todos los controles de la plataforma.

**Azure Policy** actúa en el plano de control de Azure y puede denegar una operación aunque alguien intente crear el recurso desde Portal, CLI u otro pipeline. Por eso controla también cambios fuera del repositorio. En cambio, Policy no reemplaza la revisión temprana del código, no comprende toda la lógica de scripts/app y su mensaje llega más tarde, al intentar crear/modificar el recurso.

La estrategia correcta es **shift-left + guardrail en runtime/control plane**: Checkov previene y enseña durante el PR; Azure Policy impide que una configuración prohibida exista aunque el pipeline sea eludido.

## 6. El estado Terraform contiene secretos. ¿Cómo se protegió y qué pasaría si se filtrara?

Se protege con:

- Azure Blob como backend remoto, no archivo local compartido.
- autenticación Microsoft Entra ID (`use_azuread_auth=true`), no Access Key en código;
- `shared_access_key_enabled=false` en el Storage Account;
- rol `Storage Blob Data Contributor` limitado al operador autorizado;
- firewall con `default_action=Deny` y solo la IP pública del operador;
- HTTPS obligatorio, TLS 1.2, ZRS, versionado y soft delete;
- `.gitignore` bloqueando `*.tfstate`, `*.tfvars`, planes y llaves.

Aun así, el estado debe considerarse **sensible**: `random_password.db.result` y el valor aplicado a `azurerm_key_vault_secret` pueden quedar almacenados en el state. Si se filtra, se asume comprometido todo secreto presente: rotar inmediatamente `db-password`, revocar accesos sospechosos, revisar Activity/Storage/Key Vault logs, corregir la vía de filtración y generar un nuevo estado/credencial cuando corresponda. Marcar un output como `sensitive` solo oculta la pantalla; no elimina el dato del state.
