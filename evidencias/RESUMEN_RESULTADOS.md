# Resumen de resultados (generado automáticamente)

## P1.1 Capacidad de una instancia

| Usuarios | RPS | p95 (ms) | p50 (ms) | Error % |
|---:|---:|---:|---:|---:|
| 10 | 26.9 | 230 | 220 | 0.00 |
| 20 | 53.5 | 230 | 220 | 0.00 |
| 40 | 107.3 | 230 | 220 | 0.00 |
| 60 | 160.6 | 230 | 220 | 0.00 |
| 80 | 213.4 | 230 | 220 | 0.00 |
| 100 | 266.5 | 230 | 220 | 0.00 |
| 130 | 343.5 | 240 | 230 | 0.00 |
| 160 | 415.1 | 260 | 230 | 0.00 |
| 200 | 344.4 | 540 | 440 | 0.00 |
| 250 | 368.3 | 630 | 540 | 0.00 |
| 300 | 387.3 | 730 | 640 | 0.00 |

- **RPS máximo sostenible con p95 < 1 s:** 415.1 RPS
- **RPS máximo con p95 < 500 ms:** 415.1 RPS
- p95 mínimo observado (carga baja): 230 ms → piso de latencia de red cliente↔región
- Gráfico: `evidencias/graficos/p1_capacidad_una_instancia.png`

### Pregunta 1 (300 RPS)
- Base usada: 415.1 RPS por instancia (p95<500 ms)
- N teórico = ceil(300 / 415.1) = **1** instancias
- N recomendado (25 % holgura o N+1) = **2** instancias = 4 vCPU (D2as_v4)

## P1.2 Perfil escalonado

- Duración de Locust: 35.0 min · 513300 peticiones · 4 fallas (0.00 %)
- RPS pico: 398.2 · p95 máximo: 1400 ms · instancias máximas: 3
- Eventos de autoscale: 18:00:52 (min -44.9) scale-? None→None; 18:10:55 (min -34.8) scale-? None→None; 18:41:28 (min -4.3) scale-? None→None; 18:51:32 (min 5.8) scale-? None→None; 18:59:47 (min 14.0) scale-out 2→3; 19:18:19 (min 32.6) scale-in 3→2
- CPU promedio 5 min > 70 % desde: None · scale-out: 18:59:47 · nuevas instancias sanas: 19:01:35
- Tiempo de reacción umbral→scale-out: None s · umbral→instancias sanas: None s
- Scale-in: 19:18:19
- Gráfico: `evidencias/graficos/p1_escalonado_alineado.png`

## P2 Falla lógica (/health = 503)

- instancia: **vmss-caribeshop_5**
- t0: **19:25:38**
- t1_ultima_peticion_a_instancia: **sin peticiones a la instancia después de T0**
- tiempo_hasta_dejar_de_recibir_s: **0.0**
- reparacion_automatica_s: **703.0**
- instancias_tras_reparacion: **6 8**
- ventana_falla: **19:25:38 – 19:25:53**
- locust_peticiones_ventana: **7047**
- locust_fallas_ventana: **0**
- locust_error_pct_ventana: **0.0**
- sonda_peticiones_ventana: **13**
- sonda_fallas_ventana: **12**
- sonda_error_pct_ventana: **92.31**
- locust_total_peticiones: **276653**
- locust_total_fallas: **0**
- locust_error_pct_total: **0.0**
- Gráfico: `evidencias/graficos/p2_falla_logica.png`

## P2 Falla abrupta (instancia eliminada)

- instancia: **vmss-caribeshop_6**
- t0: **19:51:53**
- ultima_falla_sonda: **20:03:09**
- errores_hasta_s: **676.2**A
- recuperacion_capacidad_minima_s: **None**
- ventana_falla: **19:51:53 – 20:03:24**
- locust_peticiones_ventana: **240424**
- locust_fallas_ventana: **912**
- locust_error_pct_ventana: **0.38**
- sonda_peticiones_ventana: **1172**
- sonda_fallas_ventana: **425**
- sonda_error_pct_ventana: **36.26**
- locust_total_peticiones: **302564**
- locust_total_fallas: **912**
- locust_error_pct_total: **0.301**
- Gráfico: `evidencias/graficos/p2_falla_abrupta.png`

