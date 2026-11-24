# D1 — Evidencia del pipeline bloqueante

1. Commit 1 agrega `infra/zz_prueba_insegura.tf` (SSH 22 abierto desde `*`).
   El workflow `terraform-security` falla en el paso **Checkov (blocking)** con `CKV_AZURE_10`.
2. Commit 2 elimina la regla. El mismo PR pasa `fmt`, `validate` y Checkov y se fusiona.

Capturas y logs: `evidencias/D1/`.
