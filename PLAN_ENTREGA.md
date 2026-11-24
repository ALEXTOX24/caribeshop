# Plan de entrega — CaribeShop (Taller integrador)

Se entregan **3 cosas**: enlace al repositorio de GitHub, informe en PDF (máx. 12 páginas) y enlace de YouTube del video (6–8 min).

## Estado actual

| Parte | Estado |
|---|---|
| Código Terraform, app, cloud-init, Locust, pipeline | ✅ Listo (Checkov: 0 fallas, skips justificados) |
| Textos del informe (arquitectura, SLA, trazabilidad, riesgos, preguntas 3–6) | ✅ Borrador listo en `report/` |
| Evidencias de configuración (S2, S3, S4, S5, E1) | ⚠️ Existen del primer despliegue (`evidencias/despliegue_anterior/`), pero en la cuenta de otra persona |
| S6 (KQL), E4, E5 (correo), P1, P2, P3 | ❌ Faltan: hay que correr las pruebas |
| D1: dos PR cerrados (uno que falla por Checkov) | ❌ Falta |
| Informe final PDF, costos, video | ❌ Falta (depende de los resultados) |

Todas las pruebas que faltan están **automatizadas** en `scripts/`. Cada script guarda sus resultados en `evidencias/`.

---

## Paso 1 — Azure: desplegar en TU suscripción (recomendado)

Las pruebas necesitan correr comandos contra el despliegue, y el firewall del despliegue anterior solo deja entrar la IP de quien lo creó. Lo más rápido y que no depende de nadie es desplegar de nuevo en tu cuenta (Azure for Students sirve). Tarda ~20 min y lo hace un script.

> Si existe un despliegue anterior en otra cuenta, su dueño debe borrar esos grupos de recursos (`rg-caribeshop-*`) para no seguir gastando crédito.

## Paso 2 — Preparar tu Windows (una sola vez, ~20 min)

1. Abre **PowerShell como administrador** y ejecuta `wsl --install -d Ubuntu`. Reinicia el PC.
2. Abre **Ubuntu** desde el menú Inicio, crea usuario y contraseña.
3. Configura Windows para que **no se suspenda** mientras corren las pruebas (Configuración → Sistema → Inicio/apagado y suspensión → Nunca, con el cargador conectado).
4. En Ubuntu, clona tu repositorio y copia encima el contenido de este zip:

```bash
cd ~
git clone https://github.com/USUARIO/REPO.git caribeshop
# Copia el zip desde Descargas de Windows (cambia TU_USUARIO_WINDOWS):
cp /mnt/c/Users/TU_USUARIO_WINDOWS/Downloads/CaribeShop_entrega.zip ~/
sudo apt-get install -y unzip && unzip -o ~/CaribeShop_entrega.zip -d ~/tmp_cs
cp -a ~/tmp_cs/caribeshop-solution/. ~/caribeshop/
cd ~/caribeshop
bash scripts/00-instalar-herramientas.sh
```

5. Inicia sesión: `az login` (se abre el navegador) y `gh auth login` (GitHub.com → HTTPS → login with browser).
6. Sube esta versión a GitHub:

```bash
bash scripts/repo-safety-check.sh      # debe decir OK
git add -A && git commit -m "Versión integrada con scripts de pruebas" && git push
```

## Paso 3 — Desplegar (~20 min)

```bash
cd ~/caribeshop
ALERT_EMAIL=tucorreo@utb.edu.co bash scripts/01-desplegar.sh
```

Al final muestra la URL y `/secret-check` con longitud y hash del secreto (nunca el valor). **Confirma el correo de suscripción a alertas que llega de Azure Monitor**.

## Paso 4 — Pruebas (≈ 3,5 horas en total; se pueden hacer en dos sesiones)

Correr **en este orden**, uno tras otro, en la misma ventana de Ubuntu. No cerrar la ventana mientras corren.

| # | Comando | Qué cubre | Tiempo |
|---|---|---|---|
| 1 | `bash scripts/pruebas/10-evidencias-base.sh` | S1, S2, S3, S4, S5, S6 (KQL), E1, E2, E3, E5, D3 | 10–25 min |
| 2 | `bash scripts/pruebas/20-p1-capacidad.sh` | P1.1 capacidad de 1 instancia | 30–40 min |
| 3 | `bash scripts/pruebas/30-p1-escalonado.sh` | P1.2/P1.3 scale-out y scale-in, E3, E5 | ~55 min |
| 4 | `bash scripts/pruebas/40-p2-falla-logica.sh` | P2.1 falla lógica + E4 reparación automática | ~40 min |
| 5 | `bash scripts/pruebas/50-p2-falla-abrupta.sh` | P2.2 falla abrupta | ~15 min |
| 6 | `bash scripts/pruebas/60-p3-seguridad.sh` | P3.2 egress, P3.3 Policy, y comando para P3.1 | ~5 min |
| 7 | `source .venv/bin/activate && python3 scripts/analizar_resultados.py` | Gráficos y números para el informe | 1 min |

### Capturas manuales (no se pueden automatizar)

Guardarlas en la carpeta indicada (desde Windows: `\\wsl$\Ubuntu\home\TU_USUARIO\caribeshop\evidencias\`).

- [ ] **P3.1**: en https://shell.azure.com pegar el comando de `evidencias/P3/P3_1_COMANDO_CLOUD_SHELL.txt` → captura del error de firewall → `evidencias/P3/P3_1_cloud_shell_bloqueado.png`
- [ ] **E5**: captura del **correo de la alerta** de CPU (llega durante la prueba 3) → `evidencias/base/E5_correo_alerta.png`
- [ ] **E3**: portal → Monitor → Autoscale → `autoscale-caribeshop` → **Run history** → captura → `evidencias/P1/escalonado/E3_run_history.png`
- [ ] **E2** (opcional, ya se exporta en JSON): portal → Load Balancer → Métricas → *Health Probe Status* → captura

## Paso 5 — Pull requests de D1 (~10 min)

```bash
bash scripts/03-pr-evidencia-d1.sh     # PR que falla por Checkov → captura → corrección → merge
bash scripts/04-pr-evidencias.sh       # segundo PR con evidencias (al final de todo)
```

Tomar captura de la pestaña **Checks** del PR en rojo y luego en verde → `evidencias/D1/`.

## Paso 6 — Informe

Con las carpetas `evidencias/` llenas, se completa `report/INFORME.md` con los números de `evidencias/RESUMEN_RESULTADOS.md` y los gráficos de `evidencias/graficos/`, y se exporta a PDF (máx. 12 páginas sin anexos). Falta además:

- [ ] Nombres de los integrantes, enlace del repo y del video.
- [ ] Cotización de **Azure Pricing Calculator** (D2as_v4 en Belgium Central ×2 y ×4, discos, Load Balancer, IP pública, Key Vault, Log Analytics) → exportar y anexar.

## Paso 7 — Video (6–8 min, todos participan)

Guion en `report/GUION_VIDEO.md`. **Truco**: hacer la llamada de Teams y grabar **mientras corre la prueba 3** (se ve aparecer la instancia nueva) y luego correr la **prueba 5** en vivo (falla abrupta). Subir a YouTube como **Público**.

## Paso 8 — Destruir (¡no olvidar!)

```bash
bash scripts/99-destruir.sh
```

Y verificar en el portal que no quede ningún grupo de recursos de CaribeShop.

## Paso 9 — Entregar en Savio

- [ ] Enlace del repositorio (público o con acceso para el profesor)
- [ ] Informe PDF
- [ ] Enlace de YouTube

## Si algo falla

- **"Client address is not authorized" al correr Terraform**: cambió tu IP de internet. Vuelve a correr `bash scripts/01-desplegar.sh` (agrega la IP nueva al firewall).
- **Error de cuota (vCPU)**: `az vm list-usage -l belgiumcentral -o table`. Prueba otra región o SKU: `LOCATION=swedencentral VM_SKU=Standard_D2as_v5 bash scripts/01-desplegar.sh`.
- **Una prueba se interrumpió**: vuelve a correr ese mismo script; sobrescribe su carpeta. La prueba de capacidad restaura sola el autoscale y las 2 instancias al terminar o al cancelarla con Ctrl+C.
