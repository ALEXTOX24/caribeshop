"""Locust para P1.

Uso capacidad (sin shape):
  locust -f locustfile.py --host http://IP --headless -u 25 -r 5 -t 5m ...

Uso perfil escalonado obligatorio de 25 min:
  LOCUST_USE_SHAPE=1 LOCUST_PEAK_USERS=180 locust -f locustfile.py \
    --host http://IP --headless --csv results/step25 --html results/step25.html
"""

import os
from locust import HttpUser, LoadTestShape, between, task

WORK_ITERATIONS = int(os.getenv("LOCUST_WORK_ITERATIONS", "3500"))


class CaribeShopUser(HttpUser):
    wait_time = between(0.05, 0.25)

    @task(9)
    def workload(self):
        # Endpoint CPU-bound controlado para hacer observable el autoscale por CPU.
        self.client.get(
            f"/work?iterations={WORK_ITERATIONS}",
            name="/work",
            timeout=10,
        )

    @task(1)
    def homepage(self):
        self.client.get("/", name="/", timeout=10)


if os.getenv("LOCUST_USE_SHAPE", "0") == "1":
    class Step25Minutes(LoadTestShape):
        """Subida → sostenida → bajada (25 min) + cola de carga baja.

        La cola (LOCUST_TAIL_SECONDS, 600 s por defecto) da tiempo a que la
        regla de scale-in (CPU < 30 % durante 10 min + cooldown) se dispare
        mientras Locust sigue midiendo. Total por defecto: 35 minutos.
        """

        peak = int(os.getenv("LOCUST_PEAK_USERS", "180"))
        low = max(10, peak // 6)
        medium = max(low + 10, peak // 2)

        stages = [
            {"until": 300, "users": low, "spawn_rate": 5},      # 0–5 min
            {"until": 600, "users": medium, "spawn_rate": 10}, # 5–10 min
            {"until": 1200, "users": peak, "spawn_rate": 15},  # 10–20 min
            {"until": 1350, "users": medium, "spawn_rate": 15},# 20–22.5 min
            {"until": 1500, "users": low, "spawn_rate": 10},   # 22.5–25 min
        ]
        tail = int(os.getenv("LOCUST_TAIL_SECONDS", "600"))
        if tail > 0:
            stages.append({"until": 1500 + tail, "users": max(5, low // 2), "spawn_rate": 10})

        def tick(self):
            run_time = self.get_run_time()
            for stage in self.stages:
                if run_time < stage["until"]:
                    return stage["users"], stage["spawn_rate"]
            return None
