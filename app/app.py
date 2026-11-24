#!/usr/bin/env python3
"""Aplicación mínima reproducible para el taller CaribeShop.

- /health: endpoint dedicado para el Load Balancer.
- /secret-check: fuerza una lectura de Key Vault con Managed Identity y devuelve
  solo longitud + SHA-256 truncado.
- /work: endpoint CPU-bound controlado para las pruebas de autoscale.
- /: estado básico de la instancia y huella del secreto (con caché).

Nunca imprime ni devuelve el valor del secreto.
"""

from __future__ import annotations

import hashlib
import json
import os
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

PORT = int(os.getenv("PORT", "80"))
KEY_VAULT_URL = os.environ["KEY_VAULT_URL"].rstrip("/")
SECRET_NAME = os.getenv("SECRET_NAME", "db-password")
UNHEALTHY_MARKER = "/tmp/caribeshop-unhealthy"
CACHE_TTL_SECONDS = 300

_cache_lock = threading.Lock()
_secret_cache: dict[str, Any] = {"expires": 0.0, "metadata": None}
_instance_cache: dict[str, Any] | None = None


def _json_request(url: str, headers: dict[str, str], timeout: float = 3.0) -> dict[str, Any]:
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def get_managed_identity_token() -> str:
    query = urllib.parse.urlencode(
        {
            "api-version": "2018-02-01",
            "resource": "https://vault.azure.net",
        }
    )
    url = f"http://169.254.169.254/metadata/identity/oauth2/token?{query}"
    payload = _json_request(url, {"Metadata": "true"})
    return payload["access_token"]


def read_secret_metadata(force: bool = False) -> dict[str, Any]:
    now = time.time()
    with _cache_lock:
        if not force and _secret_cache["metadata"] and now < _secret_cache["expires"]:
            return dict(_secret_cache["metadata"])

    token = get_managed_identity_token()
    encoded_name = urllib.parse.quote(SECRET_NAME, safe="")
    url = f"{KEY_VAULT_URL}/secrets/{encoded_name}?api-version=7.5"
    payload = _json_request(url, {"Authorization": f"Bearer {token}"})
    secret = payload["value"]

    # Solo se conserva una huella no reversible para demostrar la lectura.
    metadata = {
        "secret_name": SECRET_NAME,
        "length": len(secret),
        "sha256_12": hashlib.sha256(secret.encode("utf-8")).hexdigest()[:12],
    }

    # El valor del secreto deja de estar referenciado al salir de la función.
    del secret
    with _cache_lock:
        _secret_cache["metadata"] = dict(metadata)
        _secret_cache["expires"] = time.time() + CACHE_TTL_SECONDS
    return metadata


def instance_metadata() -> dict[str, Any]:
    global _instance_cache
    if _instance_cache is not None:
        return _instance_cache

    url = "http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01"
    try:
        payload = _json_request(url, {"Metadata": "true"})
        _instance_cache = {
            "name": payload.get("name"),
            "vmId": payload.get("vmId"),
            "zone": payload.get("zone"),
            "resourceGroupName": payload.get("resourceGroupName"),
        }
    except Exception as exc:  # La app debe seguir atendiendo aunque IMDS de metadata falle.
        _instance_cache = {"metadata_error": type(exc).__name__}
    return _instance_cache


def cpu_work(iterations: int) -> str:
    """Carga CPU controlada para demostrar autoscale sin dependencias externas."""
    iterations = max(1, min(iterations, 50_000))
    digest = b"caribeshop"
    for _ in range(iterations):
        digest = hashlib.sha256(digest).digest()
    return digest.hex()[:12]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"  # keep-alive: reutiliza conexiones (evita agotar puertos SNAT del cliente)
    server_version = "CaribeShopLab/1.0"

    def log_message(self, fmt: str, *args: Any) -> None:
        # Log mínimo; nunca registra headers de autorización ni secreto.
        print(f"{self.client_address[0]} - {fmt % args}", flush=True)

    def send_json(self, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802 (API de BaseHTTPRequestHandler)
        parsed = urllib.parse.urlparse(self.path)

        if parsed.path == "/health":
            if os.path.exists(UNHEALTHY_MARKER):
                self.send_json(503, {"status": "unhealthy", "reason": "logical-failure-test"})
            else:
                self.send_json(200, {"status": "healthy"})
            return

        if parsed.path == "/secret-check":
            try:
                metadata = read_secret_metadata(force=True)
                self.send_json(200, {"key_vault_read": "ok", **metadata})
            except Exception as exc:
                self.send_json(
                    503,
                    {
                        "key_vault_read": "failed",
                        "error_type": type(exc).__name__,
                        "message": "El valor del secreto nunca se expone en esta respuesta.",
                    },
                )
            return

        if parsed.path == "/work":
            params = urllib.parse.parse_qs(parsed.query)
            try:
                iterations = int(params.get("iterations", ["3000"])[0])
            except ValueError:
                iterations = 3000
            started = time.perf_counter()
            result = cpu_work(iterations)
            self.send_json(
                200,
                {
                    "work": "ok",
                    "iterations": max(1, min(iterations, 50_000)),
                    "digest_12": result,
                    "elapsed_ms": round((time.perf_counter() - started) * 1000, 2),
                    "instance": instance_metadata(),
                },
            )
            return

        if parsed.path == "/":
            try:
                secret = read_secret_metadata(force=False)
                self.send_json(
                    200,
                    {
                        "app": "CaribeShop",
                        "status": "ok",
                        "instance": instance_metadata(),
                        "secret_proof": secret,
                    },
                )
            except Exception as exc:
                self.send_json(
                    503,
                    {
                        "app": "CaribeShop",
                        "status": "degraded",
                        "instance": instance_metadata(),
                        "secret_error": type(exc).__name__,
                    },
                )
            return

        self.send_json(404, {"error": "not_found"})


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"CaribeShop escuchando en 0.0.0.0:{PORT}", flush=True)
    server.serve_forever()
