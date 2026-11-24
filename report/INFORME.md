# Informe — CaribeShop: plataforma segura, escalable y altamente disponible

**Curso:** Infraestructura para TI  
**Integrantes:** [NOMBRES]  
**Fecha:** [FECHA]  
**Repositorio:** [ENLACE GITHUB]  
**Video:** [ENLACE YOUTUBE]

## 1. Resumen ejecutivo

CaribeShop presentaba tres riesgos prioritarios: saturación ante promociones, dependencia de una única VM y exposición de credenciales/administración. Se diseñó una arquitectura Azure declarada completamente con Terraform que distribuye la aplicación en un VM Scale Set multi-zona detrás de un Standard Load Balancer, usa Managed Identity para leer secretos desde Key Vault y aplica controles preventivos con NSG, RBAC, Azure Policy y Checkov. La solución incorpora autoscale, reparación automática, diagnóstico y alertamiento.

El diseño evita IP pública en las VMs y no expone SSH/RDP. La entrada pública llega únicamente al Load Balancer. El Key Vault usa RBAC, purge protection y firewall `Deny` con autorización para la subnet de aplicación y la IP del operador. La identidad del VMSS recibe únicamente `Key Vault Secrets User`. La aplicación demuestra la lectura del secreto devolviendo solo longitud y un hash truncado.

## 2. Arquitectura y decisiones de diseño

```text
Internet
   |
Standard Public IP (zone-redundant)
   |
Standard Load Balancer -- HTTP probe /health
   |
+---------------- snet-app / NSG ----------------+
| Linux VM Scale Set: zones 1+2, min=2, max=4    |
| Managed Identity / no public IP / no SSH        |
+-------------------------+------------------------+
                          |
                  service endpoint
                          |
               Key Vault (RBAC + firewall)
                          |
              Diagnostic Settings
                          v
                   Log Analytics

Azure Monitor: autoscale + alerta por correo
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

## 3. Trazabilidad S1–D3

La relación entre requisitos, recursos y evidencias está en `TRAZABILIDAD.md`. Los campos de evidencia se completan con los archivos generados durante el despliegue y las pruebas.

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

Configuración temporal: autoscale deshabilitado y VMSS con una instancia.

| Corrida | Usuarios | RPS | p95 (ms) | Error % | ¿p95 > 1 s? |
|---|---:|---:|---:|---:|---|
| 1 | [ ] | [ ] | [ ] | [ ] | [ ] |
| 2 | [ ] | [ ] | [ ] | [ ] | [ ] |
| 3 | [ ] | [ ] | [ ] | [ ] | [ ] |

**RPS máximo sostenible antes de p95 > 1 s:** `[MEDIDO] RPS`.

**RPS con p95 < 500 ms:** `[MEDIDO] RPS`.

### 5.2 Perfil escalonado ≥25 min

Locust ejecutó 25 minutos con cinco etapas: baja, media, pico sostenido, reducción media y regreso a baja. Se guardaron CSV y HTML.

La figura de resultados debe alinear en un mismo eje temporal:

- cantidad de instancias;
- RPS;
- p95;
- eventos de scale-out/scale-in.

**Resultado observado:** `[DESCRIBIR CON DATOS: umbral, hora de scale-out, hora instancia healthy, scale-in y efecto en p95]`.

## 6. P2 — pruebas de falla

### 6.1 Falla lógica `/health = 503`

| Métrica | Resultado |
|---|---:|
| T0: instancia marcada no sana | [ ] |
| T1: deja de recibir tráfico | [ ] |
| Tiempo T1−T0 | [ ] s |
| Peticiones totales en ventana | [ ] |
| Peticiones fallidas | [ ] |
| Error % | `[fallidas/totales×100]` |

**Análisis:** `[Comparar el tiempo medido con la frecuencia de la sonda y sus dos fallos consecutivos. Usar el valor observado, no una estimación.]`

### 6.2 Falla abrupta — eliminación de instancia

| Métrica | Resultado |
|---|---:|
| T0: delete instance | [ ] |
| Recuperación capacidad mínima | [ ] |
| Tiempo de recuperación | [ ] s/min |
| Peticiones totales | [ ] |
| Peticiones fallidas | [ ] |
| Error % | [ ] |

**Análisis:** `[EXPLICAR QUÉ HIZO LB/VMSS Y SI HUBO PÉRDIDA DE CAPACIDAD/P95.]`

## 7. P3 — pruebas de seguridad

1. **Key Vault desde Cloud Shell/no autorizada:** el usuario conserva permisos RBAC, pero la red no pertenece a `ip_rules` ni a la subnet autorizada; la lectura es rechazada. Evidencia: `[ARCHIVO]`.
2. **Egress arbitrario:** llamadas a `example.com`/otro destino fallan desde la VM, mientras `/secret-check` sigue funcionando contra Key Vault. Evidencia: `[ARCHIVO]`.
3. **Policy Deny:** un Storage Account con HTTPS-only desactivado se rechaza. Evidencia: `[ARCHIVO]`.

## 8. Riesgos aceptados

`RIESGOS.md` contiene la justificación de cada `#checkov:skip`, el impacto que permanece y el control aplicado en este laboratorio.

## 9. Estimación de costo mensual

El precio real debe exportarse de **Azure Pricing Calculator** para `Standard_D2as_v4` en `belgiumcentral`. No se incluye una cifra estimada porque la tarifa depende de la región, el sistema operativo, el disco y el consumo de red.

### Compute

- mínimo 2 instancias 24×7: `2 × 70,08 = USD 140,16/mes` solo compute;
- fijo en 4 instancias 24×7: `4 × 70,08 = USD 280,32/mes` solo compute;
- escenario autoscale ilustrativo: 20 h/día con 2 instancias + 4 h/día con 4 → promedio 2,33 instancias → `≈ USD 163,52/mes` compute;
- ahorro de ese escenario frente a mantener 4 fijas: `≈ 41,7 %` en compute.

Agregar desde Azure Pricing Calculator:

| Componente | Configuración | USD/mes |
|---|---|---:|
| VMSS compute | D2s_v5, promedio medido/proyectado | [ ] |
| OS disks | Premium_LRS por instancia | [ ] |
| Standard Load Balancer | reglas + data processed | [ ] |
| Standard Public IP | 1 | [ ] |
| Key Vault | operaciones de secretos | [ ] |
| Log Analytics | GB ingeridos/retención | [ ] |
| Backend state Storage | ZRS, pocos MB | [ ] |
| Egress de datos | según tráfico | [ ] |
| **Total** | | **[ ]** |

El ahorro principal proviene de mantener dos instancias como base y aumentar la capacidad solo cuando las métricas activan el autoscale. Los precios de la tabla deben reemplazarse por la cotización exportada desde Azure Pricing Calculator.

## 10. Respuestas de análisis

Las respuestas y los cálculos que dependen de P1 y P2 están en `PREGUNTAS_ANALISIS.md`. Los marcadores `[MEDIDO]` se sustituyen después de ejecutar las pruebas.

## 11. Conclusiones

La solución corrige directamente las fallas del escenario: elimina la VM única mediante VMSS multi-zona, absorbe demanda con autoscale, evita secretos en código mediante Managed Identity + Key Vault y cierra administración pública de las instancias. Los controles se aplican en varias capas: IaC, pipeline, Azure Policy, RBAC, firewall, NSG, Load Balancer, reparación automática y observabilidad.

La validación final debe basarse en evidencia empírica: CSV/HTML de Locust, historial de autoscale, porcentaje de error durante fallas, KQL de Key Vault, correo de alerta y rechazo de Policy. Esos datos son los que convierten el diseño en una entrega demostrable y no solo descriptiva.
