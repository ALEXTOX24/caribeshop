# Informe — CaribeShop: plataforma segura, escalable y altamente disponible

**Curso:** Infraestructura para TI  
**Integrantes:** Alejandro Sánchez, Laura Torres, María Ahumada, María Serna  
**Fecha:** 24/11/2026  
**Repositorio:** https://github.com/ALEXTOX24/caribeshop  

## 1. Resumen ejecutivo

CaribeShop presentaba tres riesgos prioritarios: saturación ante promociones, dependencia de una única VM y exposición de credenciales/administración. Se diseñó una arquitectura Azure declarada completamente con Terraform que distribuye la aplicación en un VM Scale Set multi-zona detrás de un Standard Load Balancer, usa Managed Identity para leer secretos desde Key Vault y aplica controles preventivos con NSG, RBAC, Azure Policy y Checkov. La solución incorpora autoscale, reparación automática, diagnóstico y alertamiento.

El diseño evita IP pública en las VMs y no expone SSH/RDP. La entrada pública llega únicamente al Load Balancer. El Key Vault usa RBAC, purge protection y firewall `Deny` con autorización para la subnet de aplicación y la IP del operador. La identidad del VMSS recibe únicamente `Key Vault Secrets User`. La aplicación demuestra la lectura del secreto devolviendo solo longitud y un hash truncado.

La solución se desplegó y probó en una suscripción **Azure for Students**, lo que obligó a ajustar región, tamaño de VM, capacidad máxima y umbrales (sección 2.1). Todos los resultados de este informe provienen de ese despliegue real (`rg-caribeshop-gmb25`, región `chilecentral`).

## 2. Arquitectura y decisiones de diseño

```text
Internet
   |
Standard Public IP (zone-redundant, zonas 1-2-3)
   |
Standard Load Balancer -- HTTP probe /health
   |
+---------------- snet-app / NSG ----------------+
| Linux VM Scale Set: zones 1+2, min=2, max=3    |
| Standard_B2ls_v2 (x64), Ubuntu 22.04 Gen2      |
| Secure Boot + vTPM / Managed Identity          |
| no public IP / no SSH                          |
+-------------------------+------------------------+
                          |
                  service endpoint
                          |
               Key Vault (RBAC + firewall)
                          |
              Diagnostic Settings
                          v
                   Log Analytics

Azure Monitor: autoscale (CPU >35 % / <15 %) + alerta por correo (CPU >40 %)
Azure Policy: Deny Storage sin HTTPS
GitHub Actions: fmt + validate + Checkov bloqueante
```

### Decisiones

1. **VMSS multi-zona:** elimina la VM única como punto de falla y permite autoscale.
2. **Standard Load Balancer:** distribuye solicitudes y retira backends cuyo `/health` no devuelve 200.
3. **Managed Identity + Key Vault:** elimina contraseñas embebidas en repo/cloud-init.
4. **Firewall + RBAC:** autorización de identidad y autorización de red se exigen simultáneamente.
5. **Egress restringido:** la subnet permite Key Vault, DNS de plataforma e IMDS y bloquea Internet arbitrario.
6. **IaC + DevSecOps:** Terraform hace reproducible la plataforma; Checkov previene errores en PR y Policy impone un guardrail incluso fuera del pipeline.

### 2.1 Ajustes por restricciones de Azure for Students

| Restricción encontrada | Evidencia | Ajuste aplicado |
|---|---|---|
| Política de la suscripción que solo permite 5 regiones (`francecentral`, `northcentralus`, `canadacentral`, `spaincentral`, `chilecentral`); `belgiumcentral` rechazada con `RequestDisallowedByAzure` | `az policy assignment list` | Se evaluó cada región permitida |
| `northcentralus` no tiene Availability Zones (`LocationNotSupportAvailabilityZones`) | error de Terraform en `pip-caribeshop` | Descartada: el diseño exige ≥2 zonas |
| Cuota de **6 vCPU** por región; familias D con cuota 0 | `az vm list-usage` | Solo serie B; máximo **3 instancias de 2 vCPU** |
| Los tamaños ARM (`B2pls_v2`) no soportan Trusted Launch; en `canadacentral` solo había ARM | `az vm list-skus` (`TrustedLaunchDisabled=True`) | Se mantuvieron Secure Boot y vTPM (control compensatorio de CKV_AZURE_97) y se cambió a x64 |
| `spaincentral` sin capacidad para `B2ls_v2` y `B2as_v2` (`SkuNotAvailable`) | error de Terraform en el VMSS | Región final: **`chilecentral`** |
| Con máximo 3 y mínimo 2 solo cabe 1 instancia por acción de escalado | error `InvalidActionValue` | Scale-out y scale-in de **±1 instancia** |

Configuración final: `chilecentral`, `Standard_B2ls_v2` (x64, 2 vCPU, 4 GB), imagen `22_04-lts-gen2`, VMSS en zonas 1 y 2, mínimo 2 y máximo 3 instancias.

### 2.2 Ajustes derivados de las pruebas

1. **HTTP/1.1 keep-alive en la aplicación (`app/app.py`).** La app respondía en HTTP/1.0 y cerraba la conexión tras cada respuesta. El generador de carga (GitHub Codespace) sale a Internet por SNAT con un número limitado de puertos por destino; con una conexión nueva por petición el cliente no superaba ~4 conexiones nuevas/s y las pruebas mostraban `ConnectTimeoutError` con las VMs al **<1 % de CPU**. Con `protocol_version = "HTTP/1.1"` las conexiones se reutilizan y la carga llega realmente a las VMs.
2. **Umbrales de autoscale y alerta ajustados a la CPU utilizable.** La app es un solo proceso Python (`ThreadingHTTPServer`); por el GIL solo usa 1 de los 2 vCPU, de modo que la métrica `Percentage CPU` del VMSS se estabiliza en **~42–43 %** aun con más trabajo por petición. Un umbral de 70 % era inalcanzable. Se mantuvo la intención del diseño aplicada al 50 % utilizable: **scale-out > 35 %** (70 % de 50), **scale-in < 15 %** (30 % de 50) y **alerta > 40 %** (80 % de 50).
3. **Backend de Terraform.** La regla de IP del firewall del Storage del estado no aplica a clientes que se conectan desde la red interna de Azure (el Codespace corre en Azure), por lo que se dejó `default-action Allow`; el acceso sigue exigiendo autenticación Entra ID. El firewall del Key Vault se actualiza con la IP pública del operador en cada despliegue.

## 3. Trazabilidad S1–D3

La relación entre requisitos, recursos y evidencias está en `TRAZABILIDAD.md`. Las evidencias del despliegue real están en `evidencias/` (`base/`, `P1/`, `P2/`, `P3/`, `D1/`).

## 4. SLA compuesto estimado

Para una estimación académica se modelan como dependencias seriales del servicio HTTP:

- capa de entrada Standard Load Balancer: **99,99 %** (supuesto a verificar contra SLA oficial vigente);
- capa de cómputo con 2+ VMs distribuidas entre Availability Zones: **99,99 %** (supuesto a verificar);
- Key Vault: **99,99 %** (supuesto a verificar).

Entonces:

`SLA_compuesto = 0.9999 × 0.9999 × 0.9999 = 0.99970003 ≈ 99.9700 %`

Indisponibilidad teórica mensual para 30 días:

`43.200 min × (1 - 0.99970003) ≈ 12,96 min/mes`

Este cálculo es conservador y simplificado. Log Analytics, Azure Policy y el backend de Terraform no se incluyen en el recorrido de cada solicitud. Como la aplicación almacena temporalmente la huella del secreto, Key Vault se consulta durante la carga o renovación de esa información, no en cada petición. Las cifras de SLA utilizadas deben quedar acompañadas por su fuente de Microsoft.

## 5. P1 — prueba de carga y escalamiento

### 5.1 Capacidad de una instancia

Configuración temporal: autoscale deshabilitado y VMSS con una instancia `Standard_B2ls_v2`. Carga: `/work?iterations=3500` (90 %) y `/` (10 %), 3 minutos por nivel, cliente Locust en GitHub Codespace. Evidencia: `evidencias/P1/capacidad/`.

| Corrida | Usuarios | RPS | p95 (ms) | Error % | ¿p95 > 1 s? |
|---|---:|---:|---:|---:|---|
| 1 | 10 | 26,9 | 230 | 0,00 | No |
| 2 | 20 | 53,5 | 230 | 0,00 | No |
| 3 | 40 | 107,3 | 230 | 0,00 | No |
| 4 | 60 | 160,6 | 230 | 0,00 | No |
| 5 | 80 | 213,4 | 230 | 0,00 | No |
| 6 | 100 | 266,5 | 230 | 0,00 | No |
| 7 | 130 | 343,5 | 240 | 0,00 | No |
| 8 | 160 | 415,1 | 260 | 0,00 | No |
| 9 | 200 | 344,4 | 540 | 0,00 | No |
| 10 | 250 | 368,3 | 630 | 0,00 | No |
| 11 | 300 | 387,3 | 730 | 0,00 | No |

**RPS máximo sostenible antes de p95 > 1 s:** `415,1 RPS` (160 usuarios). Hasta 300 usuarios el p95 no superó 1 s.

**RPS con p95 < 500 ms:** `415,1 RPS`.

**Interpretación.** Entre 10 y 160 usuarios el RPS crece linealmente con latencia constante (~230 ms, casi toda latencia de red entre el cliente y `chilecentral`). Por encima de 160 usuarios el RPS deja de crecer y el p95 sube. Durante la prueba escalonada, con ~400 RPS repartidos en 2 VMs, la CPU de las VMs estuvo en ~34 %; por eso el límite de ~415 RPS corresponde al **generador de carga** (Codespace de 2 núcleos), no a la VM. La capacidad real de una instancia es **≥ 415 RPS** para esta carga.

### 5.2 Perfil escalonado ≥25 min

Locust ejecutó 35 minutos (subida → pico sostenido → bajada → cola de carga baja) con pico de **450 usuarios** y `LOCUST_WORK_ITERATIONS=9000` para que la carga generada por el cliente produjera suficiente CPU en el servidor. Se guardaron CSV, HTML e historial de instancias. Evidencia: `evidencias/P1/escalonado/` y `evidencias/graficos/p1_escalonado_alineado.png`.

| Hora (UTC) | Evento | CPU promedio VMSS |
|---|---|---:|
| 18:47–18:51 | Etapa baja | ~20 % |
| 18:52–18:56 | Etapa media | ~34 % |
| 18:57 | CPU supera el umbral de 35 % | 37,0 % |
| 18:58–19:01 | Pico con 2 instancias | ~42 % |
| 18:59:47 | **Scale-out 2 → 3** | |
| 19:01:35 | **Tercera instancia sana** | |
| 19:02–19:09 | Pico con 3 instancias | ~28 % |
| 19:03 / 19:06 | Alerta de CPU activada / resuelta (correo) | |
| 19:11–19:18 | Cola de carga baja | < 15 % |
| 19:18:19 | **Scale-in 3 → 2** | |

**Resultado observado:** con umbral de scale-out de 35 % (promedio de 5 min), la CPU superó el umbral a las 18:57; el autoscale decidió escalar a las 18:59:47 (~2,8 min) y la tercera instancia quedó sana a las 19:01:35 (~4,6 min desde el umbral). Al entrar la tercera instancia, la CPU promedio bajó de ~42 % a ~28 %. Con la carga baja final (< 15 % durante la ventana de 10 min) el autoscale hizo scale-in a las 19:18:19. En total: **513 300 peticiones, 4 fallas (0,0008 %)**, RPS pico 398, p95 global 1 200 ms y p95 máximo 1 400 ms durante el pico. Las 4 fallas (3 respuestas 503 y 1 conexión reiniciada en `/`) coinciden con los cambios de capacidad.

## 6. P2 — pruebas de falla

### 6.1 Falla lógica `/health = 503`

Carga moderada de 180 usuarios Locust. Evidencia: `evidencias/P2/falla_logica/` y `evidencias/graficos/p2_falla_logica.png`.

| Métrica | Resultado |
|---|---:|
| T0: instancia marcada no sana (`vmss-caribeshop_5`) | 19:25:38 UTC |
| T1: deja de recibir tráfico | sin peticiones a la instancia después de T0 |
| Tiempo T1−T0 | ≈ 0 s (resolución de la sonda) |
| Peticiones totales en ventana (Locust) | 7 047 |
| Peticiones fallidas | 0 |
| Error % | 0,00 % |
| Reparación automática (reemplazo) | 703 s (~11,7 min) |
| Instancias tras la reparación | 6 y 8 |

**Análisis:** el Load Balancer retiró la instancia al fallar su sonda `/health` y Locust no registró ninguna falla en toda la prueba (276 653 peticiones, 0 fallas). La reparación automática del VMSS reemplazó la instancia en ~11,7 min, consistente con el período de gracia configurado (`PT10M`) más el tiempo de creación de la nueva VM. La sonda de tráfico auxiliar (`sonda.csv`) registró errores de conexión porque abre una conexión nueva por petición y se ve afectada por el límite SNAT del cliente (sección 2.2); por eso se toma Locust como medición principal.

### 6.2 Falla abrupta — eliminación de instancia

Carga moderada de 180 usuarios Locust; se eliminó `vmss-caribeshop_6` con `az vmss delete-instances`. Evidencia: `evidencias/P2/falla_abrupta/` y `evidencias/graficos/p2_falla_abrupta.png`.

| Métrica | Resultado |
|---|---:|
| T0: delete instance | 19:51:53 UTC |
| Recuperación capacidad mínima | No automática (restaurada manualmente) |
| Ventana con fallas (Locust) | 152 s (T0+5 s a T0+157 s) |
| Peticiones totales | 302 564 |
| Peticiones fallidas | 912 |
| Error % | 0,30 % |

**Análisis:** antes de T0 el sistema atendía ~470 RPS con 0 fallas y p95 de 240–260 ms. Al eliminar la instancia, el RPS bajó a ~300–325 (−32 %) y durante 152 s hubo ~6 fallas/s (≈2 %), producidas por las conexiones keep-alive que apuntaban a la instancia eliminada hasta que el cliente se reconectó a la instancia sana. **El servicio no se interrumpió** y el p95 se mantuvo por debajo de 320 ms. La capacidad mínima **no se recuperó automáticamente**: `az vmss delete-instances` reduce la capacidad deseada del VMSS a 1 y el autoscale siguió reportando `ObservedCapacity = 2` sin iniciar ninguna acción (`ScaleActionsInitiated = 0` durante 40 min), por lo que se restauró manualmente con `az vmss scale --new-capacity 2`. Una caída real de hardware no reduce la capacidad deseada y queda cubierta por la reparación automática demostrada en 6.1; para el escenario de eliminación se recomienda una alerta sobre el número de instancias sanas.

## 7. P3 — pruebas de seguridad

1. **Key Vault desde Cloud Shell/no autorizada:** el mismo usuario (con rol RBAC sobre el Key Vault) ejecutó `az keyvault secret show` desde Azure Cloud Shell (IP `48.221.10.88`); la lectura fue rechazada con `Forbidden / ForbiddenByFirewall`. Evidencia: `evidencias/P3/P3_1_cloud_shell_bloqueado.png`, `P3_1_cloud_shell_bloqueado.txt` y `P3_1_desde_ip_autorizada.txt`.
2. **Egress arbitrario:** desde la instancia 8 (Run Command, sin SSH) las llamadas a `example.com`, `www.google.com` y `github.com` quedaron bloqueadas, mientras Key Vault fue alcanzable y la app leyó el secreto (`key_vault_read: ok`). Evidencia: `evidencias/P3/P3_2_egress.txt`.
3. **Policy Deny:** la creación de un Storage Account con `--https-only false` fue rechazada con `RequestDisallowedByPolicy` por la asignación `deny-insecure-storage`. Evidencia: `evidencias/P3/P3_3_policy_deny.txt`.
4. **Pipeline bloqueante (D1):** el PR #1 agregó a propósito una regla NSG con SSH abierto a Internet; Checkov falló con `CKV_AZURE_10` (29 checks aprobados, 1 fallido) y el PR solo pasó a verde al eliminar la regla. Evidencia: `evidencias/D1/`.

Además, la consulta KQL de S6 devolvió 20 registros `SecretGet` del Key Vault en Log Analytics (`evidencias/base/S6_kql_resultado.txt`).

## 8. Riesgos aceptados

`RIESGOS.md` contiene la justificación de cada `#checkov:skip`, el impacto que permanece y el control aplicado en este laboratorio. Se suman los riesgos derivados de la suscripción de estudiante: región única (`chilecentral`), máximo 3 instancias por la cuota de 6 vCPU, VMs de la serie B (burstable) y la no recuperación automática de capacidad ante la eliminación manual de instancias (sección 6.2).

## 9. Estimación de costo mensual

Cotización exportada de **Azure Pricing Calculator** el 24/11/2026 (precios de pago por uso en USD, región `chilecentral`). Archivo: `report/Cotizacion_Azure_CaribeShop.xlsx`.

| Componente | Configuración | USD/mes |
|---|---|---:|
| VMSS compute + OS disks | 2 × `B2ls v2` Linux × 730 h + 2 discos Premium SSD P4 | 98,45 |
| Standard Load Balancer | 1 regla + 50 GB procesados | 18,50 |
| Standard Public IP | 1 IP estática × 730 h | 3,65 |
| Key Vault | 100 000 operaciones de secretos | 0,30 |
| Log Analytics (Azure Monitor) | 0,2 GB/día de registros de análisis, 31 días de retención | 3,21 |
| Backend state Storage | Blob en bloques, GPv2, ZRS, 1 GB | 1,84 |
| Egress de datos | 50 GB a Internet (dentro del volumen gratuito) | 0,00 |
| **Total (base de 2 instancias)** | | **125,95** |

### Compute

Precio de `B2ls v2` Linux en `chilecentral`: **0,058 USD/hora** por instancia.

- mínimo 2 instancias 24×7: `2 × 730 h × 0,058 ≈ 84,68 USD/mes`;
- fijo en 3 instancias 24×7 (máximo permitido): `3 × 730 h × 0,058 ≈ 127,02 USD/mes`;
- escenario autoscale ilustrativo: 20 h/día con 2 instancias + 4 h/día con 3 → promedio 2,17 instancias → `≈ 91,74 USD/mes`;
- ahorro de ese escenario frente a mantener 3 fijas: `≈ 27,8 %` en compute (≈ 35,28 USD/mes).

El ahorro principal proviene de mantener dos instancias como base y aumentar la capacidad solo cuando las métricas activan el autoscale. El cómputo y sus discos representan ~78 % del costo total, por lo que la capacidad mínima es la palanca de costo más importante.

## 10. Respuestas de análisis

Las respuestas y los cálculos que dependen de P1 y P2 están en `PREGUNTAS_ANALISIS.md`, actualizadas con los valores medidos en este informe.

## 11. Conclusiones

La solución corrige directamente las fallas del escenario: elimina la VM única mediante VMSS multi-zona, absorbe demanda con autoscale, evita secretos en código mediante Managed Identity + Key Vault y cierra administración pública de las instancias. Los controles se aplican en varias capas: IaC, pipeline, Azure Policy, RBAC, firewall, NSG, Load Balancer, reparación automática y observabilidad.

Las pruebas lo demostraron con datos del despliegue real: el autoscale pasó de 2 a 3 instancias y volvió a 2 con 0,0008 % de error en 513 300 peticiones; la falla lógica no produjo errores y la instancia se reemplazó automáticamente en ~11,7 min; la eliminación abrupta de una instancia causó 0,30 % de error sin interrumpir el servicio; y los controles de red, Policy y pipeline bloquearon cada intento inseguro. Las pruebas también revelaron dos límites que se documentan como aprendizaje: la CPU utilizable por una app Python de un solo proceso (que obligó a recalibrar los umbrales) y la necesidad de vigilar la capacidad ante eliminaciones manuales de instancias.
