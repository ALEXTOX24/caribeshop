#!/usr/bin/env python3
"""Sonda de tráfico para las pruebas de falla (P2).

Cada petición abre una conexión TCP NUEVA (sin keep-alive), así el Load
Balancer decide el backend en cada petición. La respuesta de /work incluye el
nombre de la instancia que atendió, lo que permite medir exactamente cuándo una
instancia deja de recibir tráfico nuevo.

Salida CSV: epoch,status,latency_ms,instance,error

Uso:
  python3 sonda_trafico.py --url http://IP --duration 600 --out sonda.csv
"""

from __future__ import annotations

import argparse
import csv
import json
import threading
import time
import urllib.error
import urllib.request


def worker(url: str, end: float, pause: float, timeout: float, writer, lock: threading.Lock, fh) -> None:
    while time.time() < end:
        start = time.time()
        status, instance, error = 0, "", ""
        try:
            req = urllib.request.Request(url, headers={"Connection": "close"})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                status = resp.status
                body = json.loads(resp.read().decode("utf-8"))
                instance = (body.get("instance") or {}).get("name") or ""
        except urllib.error.HTTPError as exc:
            status, error = exc.code, "HTTPError"
        except Exception as exc:  # timeouts, conexiones rechazadas/reseteadas
            error = type(exc).__name__
        latency = (time.time() - start) * 1000
        with lock:
            writer.writerow([f"{start:.3f}", status, f"{latency:.1f}", instance, error])
            fh.flush()
        time.sleep(pause)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--url", required=True, help="URL base, p. ej. http://20.1.2.3")
    p.add_argument("--path", default="/work?iterations=300")
    p.add_argument("--workers", type=int, default=4)
    p.add_argument("--duration", type=int, default=600, help="segundos")
    p.add_argument("--pause", type=float, default=0.2, help="pausa entre peticiones por hilo")
    p.add_argument("--timeout", type=float, default=5.0)
    p.add_argument("--out", required=True)
    a = p.parse_args()

    url = a.url.rstrip("/") + a.path
    end = time.time() + a.duration
    lock = threading.Lock()
    with open(a.out, "w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["epoch", "status", "latency_ms", "instance", "error"])
        threads = [
            threading.Thread(target=worker, args=(url, end, a.pause, a.timeout, writer, lock, fh), daemon=True)
            for _ in range(a.workers)
        ]
        for t in threads:
            t.start()
        for t in threads:
            t.join()


if __name__ == "__main__":
    main()
