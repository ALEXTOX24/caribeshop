#!/usr/bin/env python3
"""Analiza las evidencias de P1 y P2 y genera gráficos + un resumen con los números del informe.

Uso (desde la raíz del repo, con el entorno .venv activo):
    python3 scripts/analizar_resultados.py

Salidas:
    evidencias/graficos/*.png
    evidencias/RESUMEN_RESULTADOS.md
    evidencias/resumen_resultados.json
"""

from __future__ import annotations

import csv
import json
import math
from datetime import datetime, timezone
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
EVID = ROOT / "evidencias"
GRAF = EVID / "graficos"
GRAF.mkdir(parents=True, exist_ok=True)

COL_RPS = "#2563eb"
COL_P95 = "#dc2626"
COL_INST = "#059669"
COL_ERR = "#b45309"
COL_GRAY = "#6b7280"

resumen: dict = {}
lineas: list[str] = ["# Resumen de resultados (generado automáticamente)", ""]


def fnum(x, default=math.nan) -> float:
    try:
        return float(x)
    except (TypeError, ValueError):
        return default


def iso_to_epoch(s: str) -> float:
    """Convierte ISO-8601 de Azure (fracciones de hasta 7 dígitos, sufijo Z) a epoch."""
    import re

    m = re.match(r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:?\d{2})?$", s.strip())
    if not m:
        return datetime.fromisoformat(s).timestamp()
    base, frac, tz = m.groups()
    tz = "+00:00" if tz in (None, "Z") else tz
    dt = datetime.fromisoformat(f"{base}{tz}")
    return dt.astimezone(timezone.utc).timestamp() + (float("0." + frac) if frac else 0.0)


def read_history(path: Path) -> list[dict]:
    if not path.exists():
        return []
    rows = []
    for r in csv.DictReader(path.open()):
        if r.get("Name") != "Aggregated":
            continue
        rows.append(
            {
                "t": int(r["Timestamp"]),
                "users": int(fnum(r["User Count"], 0)),
                "rps": fnum(r["Requests/s"], 0.0),
                "fps": fnum(r["Failures/s"], 0.0),
                "p95": fnum(r["95%"]),
                "p50": fnum(r["50%"]),
                "req": int(fnum(r["Total Request Count"], 0)),
                "fail": int(fnum(r["Total Failure Count"], 0)),
            }
        )
    return rows


def window_errors(hist: list[dict], t_a: float, t_b: float) -> tuple[int, int]:
    """Peticiones y fallas registradas por Locust entre t_a y t_b (conteos acumulados)."""
    before = [r for r in hist if r["t"] <= t_a]
    inside = [r for r in hist if r["t"] <= t_b]
    if not inside:
        return 0, 0
    a = before[-1] if before else hist[0]
    b = inside[-1]
    return b["req"] - a["req"], b["fail"] - a["fail"]


def read_sampler(path: Path) -> list[dict]:
    if not path.exists():
        return []
    out = []
    for r in csv.DictReader(path.open()):
        out.append({"t": int(r["epoch"]), "inst": int(fnum(r["instances"], 0)), "healthy": int(fnum(r["healthy"], 0)), "ids": r["ids"]})
    return out


def read_metric(path: Path) -> list[tuple[float, float]]:
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError:
        return []
    out = []
    for v in data.get("value", []):
        for ts in v.get("timeseries", []):
            for d in ts.get("data", []):
                val = next((d.get(k) for k in ("average", "maximum", "total", "count") if d.get(k) is not None), None)
                if val is not None:
                    out.append((iso_to_epoch(d["timeStamp"]), float(val)))
    return sorted(out)


def read_autoscale_events(path: Path) -> list[dict]:
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError:
        return []
    ev = []
    for e in data:
        op = (e.get("operationName") or {}).get("value", "")
        if "autoscale" not in op.lower():
            continue
        st = (e.get("status") or {}).get("value", "")
        if st and st.lower() not in ("succeeded", "started"):
            continue
        props = e.get("properties") or {}
        direction = "out" if "scaleup" in op.lower() else ("in" if "scaledown" in op.lower() else "?")
        ev.append(
            {
                "t": iso_to_epoch(e["eventTimestamp"]),
                "dir": direction,
                "status": st,
                "old": props.get("OldInstancesCount") or props.get("oldInstancesCount"),
                "new": props.get("NewInstancesCount") or props.get("newInstancesCount"),
            }
        )
    # Un mismo escalamiento genera "Started" y "Succeeded": se conserva el primero de cada par.
    ev.sort(key=lambda x: x["t"])
    dedup = []
    for e in ev:
        if dedup and dedup[-1]["dir"] == e["dir"] and abs(dedup[-1]["t"] - e["t"]) < 600 and dedup[-1]["new"] == e["new"]:
            continue
        dedup.append(e)
    return dedup


def hhmm(t: float) -> str:
    return datetime.fromtimestamp(t).strftime("%H:%M:%S")


# ---------------------------------------------------------------- P1.1 capacidad
cap_csv = EVID / "P1" / "capacidad" / "resumen_capacidad.csv"
if cap_csv.exists():
    rows = [
        {k: fnum(v) for k, v in r.items()}
        for r in csv.DictReader(cap_csv.open())
    ]
    rows = [r for r in rows if not math.isnan(r["usuarios"])]
    ok1s = [r for r in rows if r["p95_ms"] <= 1000 and r["error_pct"] <= 5]
    ok500 = [r for r in rows if r["p95_ms"] <= 500 and r["error_pct"] <= 5]
    rps_1s = max((r["rps"] for r in ok1s), default=0.0)
    rps_500 = max((r["rps"] for r in ok500), default=0.0)
    p95_min = min((r["p95_ms"] for r in rows), default=math.nan)
    resumen["P1_capacidad"] = {
        "corridas": rows,
        "rps_max_p95_menor_1s": rps_1s,
        "rps_max_p95_menor_500ms": rps_500,
        "p95_minimo_observado_ms": p95_min,
    }

    fig, ax1 = plt.subplots(figsize=(8, 4.2))
    u = [r["usuarios"] for r in rows]
    ax1.plot(u, [r["rps"] for r in rows], "o-", color=COL_RPS, label="RPS")
    ax1.set_xlabel("Usuarios concurrentes de Locust")
    ax1.set_ylabel("Peticiones por segundo", color=COL_RPS)
    ax2 = ax1.twinx()
    ax2.plot(u, [r["p95_ms"] for r in rows], "s-", color=COL_P95, label="p95")
    ax2.axhline(1000, color=COL_P95, ls="--", lw=1)
    ax2.axhline(500, color=COL_GRAY, ls=":", lw=1)
    ax2.text(u[0], 1010, "límite p95 = 1 s", color=COL_P95, fontsize=8, va="bottom")
    ax2.text(u[0], 510, "p95 = 500 ms", color=COL_GRAY, fontsize=8, va="bottom")
    ax2.set_ylabel("p95 (ms)", color=COL_P95)
    ax1.set_title("P1.1 — Capacidad de una instancia")
    ax1.grid(alpha=0.3)
    fig.tight_layout()
    fig.savefig(GRAF / "p1_capacidad_una_instancia.png", dpi=150)
    plt.close(fig)

    lineas += [
        "## P1.1 Capacidad de una instancia",
        "",
        "| Usuarios | RPS | p95 (ms) | p50 (ms) | Error % |",
        "|---:|---:|---:|---:|---:|",
        *[f"| {r['usuarios']:.0f} | {r['rps']:.1f} | {r['p95_ms']:.0f} | {r['p50_ms']:.0f} | {r['error_pct']:.2f} |" for r in rows],
        "",
        f"- **RPS máximo sostenible con p95 < 1 s:** {rps_1s:.1f} RPS",
        f"- **RPS máximo con p95 < 500 ms:** {rps_500:.1f} RPS" + ("" if rps_500 else " (ninguna corrida bajó de 500 ms; ver latencia de red)"),
        f"- p95 mínimo observado (carga baja): {p95_min:.0f} ms → piso de latencia de red cliente↔región",
        "- Gráfico: `evidencias/graficos/p1_capacidad_una_instancia.png`",
        "",
    ]
    if rps_500 or rps_1s:
        base = rps_500 or rps_1s
        n_teo = math.ceil(300 / base)
        n_rec = max(math.ceil(300 * 1.25 / base), n_teo + 1)
        resumen["pregunta_1"] = {"rps_base": base, "base": "p95<500ms" if rps_500 else "p95<1s", "n_teorico": n_teo, "n_recomendado": n_rec, "vcpu_necesarias": 2 * n_rec}
        lineas += [
            "### Pregunta 1 (300 RPS)",
            f"- Base usada: {base:.1f} RPS por instancia ({'p95<500 ms' if rps_500 else 'p95<1 s, porque ninguna corrida bajó de 500 ms'})",
            f"- N teórico = ceil(300 / {base:.1f}) = **{n_teo}** instancias",
            f"- N recomendado (25 % holgura o N+1) = **{n_rec}** instancias = {2*n_rec} vCPU (D2as_v4)",
            "",
        ]

# ---------------------------------------------------------------- P1.2 escalonado
esc = EVID / "P1" / "escalonado"
hist = read_history(esc / "step_stats_history.csv")
if hist:
    samp = read_sampler(esc / "instancias.csv")
    obs = read_metric(esc / "autoscale_observed_capacity.json")
    cpu = read_metric(esc / "vmss_cpu.json")
    events = read_autoscale_events(esc / "autoscale_activity_log.json")
    t0 = hist[0]["t"]
    t_end = max([hist[-1]["t"]] + [s["t"] for s in samp])
    m = lambda t: (t - t0) / 60  # noqa: E731

    fig, axes = plt.subplots(4, 1, figsize=(10, 10), sharex=True, gridspec_kw={"height_ratios": [1, 1.2, 1.2, 1]})
    a_inst, a_rps, a_p95, a_cpu = axes
    if samp:
        a_inst.step([m(s["t"]) for s in samp], [s["inst"] for s in samp], where="post", color=COL_INST, label="instancias (muestreo)")
        a_inst.step([m(s["t"]) for s in samp], [s["healthy"] for s in samp], where="post", color=COL_INST, ls="--", alpha=0.6, label="instancias sanas")
    if obs:
        oo = [(t, v) for t, v in obs if t0 - 300 <= t <= t_end + 60]
        a_inst.step([m(t) for t, _ in oo], [v for _, v in oo], where="post", color="black", alpha=0.5, lw=1, label="ObservedCapacity (autoscale)")
    a_inst.set_ylabel("Instancias")
    a_inst.set_ylim(0, 5)
    a_inst.legend(loc="upper left", fontsize=7)
    a_rps.plot([m(r["t"]) for r in hist], [r["rps"] for r in hist], color=COL_RPS, lw=1)
    a_rps.set_ylabel("RPS")
    ax_u = a_rps.twinx()
    ax_u.plot([m(r["t"]) for r in hist], [r["users"] for r in hist], color=COL_GRAY, lw=1, ls=":")
    ax_u.set_ylabel("usuarios", color=COL_GRAY)
    a_p95.plot([m(r["t"]) for r in hist if not math.isnan(r["p95"])], [r["p95"] for r in hist if not math.isnan(r["p95"])], color=COL_P95, lw=1)
    a_p95.set_ylabel("p95 (ms)")
    if cpu:
        cc = [(t, v) for t, v in cpu if t0 - 300 <= t <= t_end + 60]
        a_cpu.plot([m(t) for t, _ in cc], [v for _, v in cc], color="#7c3aed")
        a_cpu.axhline(70, color=COL_P95, ls="--", lw=1)
        a_cpu.axhline(30, color=COL_RPS, ls="--", lw=1)
        a_cpu.text(0, 71, "scale-out > 70 %", fontsize=7, color=COL_P95)
        a_cpu.text(0, 31, "scale-in < 30 %", fontsize=7, color=COL_RPS)
    a_cpu.set_ylabel("CPU VMSS (%)")
    a_cpu.set_xlabel("Minutos desde el inicio de la prueba")
    for e in events:
        for ax in axes:
            ax.axvline(m(e["t"]), color=COL_INST if e["dir"] == "out" else COL_RPS, ls="-.", lw=1, alpha=0.8)
        a_inst.text(m(e["t"]), 4.6, f"scale-{e['dir']} {e['old']}→{e['new']}", fontsize=7, rotation=0)
    for ax in axes:
        ax.grid(alpha=0.3)
    axes[0].set_title("P1.2 — Perfil escalonado: instancias, RPS, p95 y CPU alineados en el tiempo")
    fig.tight_layout()
    fig.savefig(GRAF / "p1_escalonado_alineado.png", dpi=150)
    plt.close(fig)

    total_req = hist[-1]["req"]
    total_fail = hist[-1]["fail"]
    dur = (hist[-1]["t"] - hist[0]["t"]) / 60
    # Tiempo de reacción: primer minuto con CPU promedio de 5 min > 70 % hasta instancias sanas > 2
    t_thr = None
    if cpu:
        for i in range(4, len(cpu)):
            win = [v for _, v in cpu[i - 4 : i + 1]]
            if cpu[i][0] >= t0 and sum(win) / len(win) > 70:
                t_thr = cpu[i][0]
                break
    t_out = next((e["t"] for e in events if e["dir"] == "out"), None)
    t_in = next((e["t"] for e in events if e["dir"] == "in"), None)
    t_healthy = next((s["t"] for s in samp if s["healthy"] > 2 and (t_out is None or s["t"] >= t_out - 60)), None)
    max_inst = max([s["inst"] for s in samp] + [0])
    resumen["P1_escalonado"] = {
        "duracion_min": dur,
        "peticiones": total_req,
        "fallas": total_fail,
        "error_pct": 100 * total_fail / max(total_req, 1),
        "rps_pico": max(r["rps"] for r in hist),
        "p95_max_ms": max((r["p95"] for r in hist if not math.isnan(r["p95"])), default=math.nan),
        "max_instancias": max_inst,
        "eventos_autoscale": [{"hora": hhmm(e["t"]), "min": round(m(e["t"]), 1), **{k: e[k] for k in ("dir", "old", "new")}} for e in events],
        "t_umbral_cpu": hhmm(t_thr) if t_thr else None,
        "t_scale_out": hhmm(t_out) if t_out else None,
        "t_nuevas_sanas": hhmm(t_healthy) if t_healthy else None,
        "reaccion_umbral_a_scaleout_s": (t_out - t_thr) if (t_out and t_thr) else None,
        "reaccion_umbral_a_sanas_s": (t_healthy - t_thr) if (t_healthy and t_thr) else None,
        "t_scale_in": hhmm(t_in) if t_in else None,
    }
    r = resumen["P1_escalonado"]
    lineas += [
        "## P1.2 Perfil escalonado",
        "",
        f"- Duración de Locust: {dur:.1f} min · {total_req} peticiones · {total_fail} fallas ({r['error_pct']:.2f} %)",
        f"- RPS pico: {r['rps_pico']:.1f} · p95 máximo: {r['p95_max_ms']:.0f} ms · instancias máximas: {max_inst}",
        "- Eventos de autoscale: " + ("; ".join(f"{e['hora']} (min {e['min']}) scale-{e['dir']} {e['old']}→{e['new']}" for e in r["eventos_autoscale"]) or "ninguno registrado"),
        f"- CPU promedio 5 min > 70 % desde: {r['t_umbral_cpu']} · scale-out: {r['t_scale_out']} · nuevas instancias sanas: {r['t_nuevas_sanas']}",
        f"- Tiempo de reacción umbral→scale-out: {r['reaccion_umbral_a_scaleout_s']} s · umbral→instancias sanas: {r['reaccion_umbral_a_sanas_s']} s",
        f"- Scale-in: {r['t_scale_in']}",
        "- Gráfico: `evidencias/graficos/p1_escalonado_alineado.png`",
        "",
    ]


# ---------------------------------------------------------------- P2
def p2(nombre: str, titulo: str) -> None:
    d = EVID / "P2" / nombre
    evf = d / "eventos.json"
    if not evf.exists():
        return
    ev = json.loads(evf.read_text())
    hist = read_history(d / "locust_stats_history.csv")
    probe = []
    if (d / "sonda.csv").exists():
        for r in csv.DictReader((d / "sonda.csv").open()):
            probe.append({"t": float(r["epoch"]), "status": int(r["status"]), "inst": r["instance"], "err": r["error"]})
    samp = read_sampler(d / "instancias.csv")
    target = ev.get("instancia_nombre", "")
    if nombre == "falla_logica":
        if ev.get("t0_vm"):
            # reloj de la VM llevado al reloj local (las peticiones de la sonda usan el reloj local)
            t0 = ev["t0_vm"] + float(ev.get("desfase_reloj_s") or 0)
        else:
            t0 = (ev["t0_local_antes"] + ev["t0_local_despues"]) / 2
    else:
        t0 = ev["t0"]

    out: dict = {"instancia": target, "t0": hhmm(t0)}
    after_target = [p for p in probe if p["t"] >= t0 and p["inst"] == target and p["status"] == 200]
    t_last = max((p["t"] for p in after_target), default=None)
    if nombre == "falla_logica":
        t1 = t_last if t_last else t0
        seen_before = any(p["inst"] == target for p in probe if p["t"] < t0)
        out["t1_ultima_peticion_a_instancia"] = hhmm(t1) if t_last else "sin peticiones a la instancia después de T0"
        out["tiempo_hasta_dejar_de_recibir_s"] = round(t1 - t0, 1) if t_last else (0.0 if seen_before else None)
        if not seen_before:
            out["aviso"] = "la sonda no registró peticiones a la instancia objetivo antes de T0; revisar sonda.csv"
        t_end = t1 + 15
        if ev.get("reparada_epoch"):
            out["reparacion_automatica_s"] = round(ev["reparada_epoch"] - t0, 0)
            out["instancias_tras_reparacion"] = ev.get("instancias_tras_reparacion")
    else:
        t_rec = ev.get("recuperada_epoch")
        errs = [p["t"] for p in probe if p["t"] >= t0 and p["status"] != 200]
        t_last_err = max(errs, default=t0)
        out["ultima_falla_sonda"] = hhmm(t_last_err)
        out["errores_hasta_s"] = round(t_last_err - t0, 1)
        out["recuperacion_capacidad_minima_s"] = round(t_rec - t0, 0) if t_rec else None
        t_end = max(t_last_err, t0 + 60) + 15
    out["ventana_falla"] = f"{hhmm(t0)} – {hhmm(t_end)}"
    req, fail = window_errors(hist, t0, t_end)
    out["locust_peticiones_ventana"] = req
    out["locust_fallas_ventana"] = fail
    out["locust_error_pct_ventana"] = round(100 * fail / max(req, 1), 2)
    pw = [p for p in probe if t0 <= p["t"] <= t_end]
    pf = [p for p in pw if p["status"] != 200]
    out["sonda_peticiones_ventana"] = len(pw)
    out["sonda_fallas_ventana"] = len(pf)
    out["sonda_error_pct_ventana"] = round(100 * len(pf) / max(len(pw), 1), 2)
    if hist:
        out["locust_total_peticiones"] = hist[-1]["req"]
        out["locust_total_fallas"] = hist[-1]["fail"]
        out["locust_error_pct_total"] = round(100 * hist[-1]["fail"] / max(hist[-1]["req"], 1), 3)
    resumen[f"P2_{nombre}"] = out

    # gráfico: peticiones de la sonda por instancia cada 5 s + fallas + instancias
    if probe:
        start = min(p["t"] for p in probe)
        bins: dict[int, dict[str, int]] = {}
        for p in probe:
            b = int((p["t"] - start) // 5)
            key = p["inst"] if p["status"] == 200 else "FALLA"
            bins.setdefault(b, {}).setdefault(key, 0)
            bins[b][key] += 1
        insts = sorted({k for v in bins.values() for k in v if k != "FALLA"})
        xs = sorted(bins)
        fig, (a1, a2) = plt.subplots(2, 1, figsize=(10, 6), sharex=True, gridspec_kw={"height_ratios": [2, 1]})
        bottom = [0] * len(xs)
        palette = ["#2563eb", "#059669", "#7c3aed", "#0891b2", "#ca8a04", "#db2777"]
        for i, name in enumerate(insts + ["FALLA"]):
            vals = [bins[x].get(name, 0) for x in xs]
            color = "#dc2626" if name == "FALLA" else palette[i % len(palette)]
            label = f"{name} (objetivo)" if name == target else name
            a1.bar([x * 5 / 60 for x in xs], vals, width=5 / 60, bottom=bottom, color=color, label=label, align="edge")
            bottom = [b + v for b, v in zip(bottom, vals)]
        tm = (t0 - start) / 60
        for ax in (a1, a2):
            ax.axvline(tm, color="black", ls="--", lw=1)
        a1.text(tm, max(bottom) * 0.95, " T0 falla", fontsize=8)
        if nombre == "falla_logica" and t_last:
            a1.axvline((t_last - start) / 60, color=COL_P95, ls=":", lw=1)
            a1.text((t_last - start) / 60, max(bottom) * 0.85, f" T1 (+{t_last - t0:.0f} s)", fontsize=8, color=COL_P95)
        a1.set_ylabel("peticiones de la sonda / 5 s")
        a1.legend(fontsize=7, loc="upper left", bbox_to_anchor=(1.01, 1), borderaxespad=0)
        a1.set_title(f"P2 — {titulo}: a qué instancia llega cada petición nueva")
        if samp:
            a2.step([(s["t"] - start) / 60 for s in samp], [s["healthy"] for s in samp], where="post", color=COL_INST, label="instancias sanas")
            a2.step([(s["t"] - start) / 60 for s in samp], [s["inst"] for s in samp], where="post", color=COL_GRAY, ls="--", label="instancias")
            a2.legend(fontsize=7)
        if hist:
            a3 = a2.twinx()
            a3.plot([(r["t"] - start) / 60 for r in hist], [r["fps"] for r in hist], color=COL_ERR, lw=1)
            a3.set_ylabel("fallas/s Locust", color=COL_ERR)
            a3.set_ylim(bottom=0)
        a2.set_ylabel("instancias")
        a2.set_ylim(0, max([s["inst"] for s in samp] + [2]) + 1)
        a2.yaxis.get_major_locator().set_params(integer=True)
        a2.set_xlabel("minutos desde el inicio")
        for ax in (a1, a2):
            ax.grid(alpha=0.3)
        fig.tight_layout()
        fig.savefig(GRAF / f"p2_{nombre}.png", dpi=150)
        plt.close(fig)

    lineas.append(f"## P2 {titulo}")
    lineas.append("")
    for k, v in out.items():
        lineas.append(f"- {k}: **{v}**")
    lineas.extend([f"- Gráfico: `evidencias/graficos/p2_{nombre}.png`", ""])


p2("falla_logica", "Falla lógica (/health = 503)")
p2("falla_abrupta", "Falla abrupta (instancia eliminada)")

(EVID / "resumen_resultados.json").write_text(json.dumps(resumen, indent=2, ensure_ascii=False, default=str))
(EVID / "RESUMEN_RESULTADOS.md").write_text("\n".join(lineas) + "\n")
print("\n".join(lineas))
print(f"\nGráficos en {GRAF}")
