"""
Locust Distributed Load Test
Simulates realistic user traffic patterns for autoscaling validation.

Usage (standalone):
  locust -f locustfile.py --host=http://backend-api.backend.svc.cluster.local

Usage (distributed — 1 master, 4 workers):
  locust -f locustfile.py --master --host=http://backend-api:80
  locust -f locustfile.py --worker --master-host=locust-master

Usage (headless surge test):
  locust -f locustfile.py --headless -u 200 -r 20 --run-time 5m \
    --host=http://backend-api:80
"""
import random
import json
from locust import HttpUser, task, between, constant_pacing, events
from locust.runners import MasterRunner


class APIUser(HttpUser):
    """Simulates a typical API consumer — reads heavy, writes occasional."""

    # Think time: 0.5–2 seconds between requests (realistic user pacing)
    wait_time = between(0.5, 2)

    def on_start(self):
        """Called when a simulated user starts — authenticate."""
        resp = self.client.post("/api/auth/token", json={
            "username": f"loadtest-user-{random.randint(1, 10000)}",
            "password": "test-password"
        }, catch_response=True)

        if resp.status_code == 200:
            self.token = resp.json().get("access_token", "")
        else:
            self.token = ""

    @property
    def auth_headers(self):
        return {"Authorization": f"Bearer {self.token}"}

    @task(40)
    def list_products(self):
        """Most common request — product listing."""
        page = random.randint(1, 10)
        self.client.get(
            f"/api/products?page={page}&limit=20",
            headers=self.auth_headers,
            name="/api/products"
        )

    @task(25)
    def search(self):
        """Search — CPU-intensive on backend."""
        terms = ["kubernetes", "terraform", "aws", "docker", "python", "golang"]
        self.client.get(
            f"/api/search?q={random.choice(terms)}",
            headers=self.auth_headers,
            name="/api/search"
        )

    @task(15)
    def get_product_detail(self):
        """Product detail page."""
        product_id = random.randint(1, 10000)
        self.client.get(
            f"/api/products/{product_id}",
            headers=self.auth_headers,
            name="/api/products/[id]"
        )

    @task(10)
    def user_profile(self):
        """User profile — hits auth + database."""
        self.client.get(
            "/api/user/profile",
            headers=self.auth_headers,
            name="/api/user/profile"
        )

    @task(7)
    def add_to_cart(self):
        """Write operation — important for testing write path under load."""
        self.client.post(
            "/api/cart/items",
            json={"product_id": random.randint(1, 1000), "quantity": 1},
            headers=self.auth_headers,
            name="/api/cart/items"
        )

    @task(3)
    def health_check(self):
        """Simulates ALB health checks."""
        with self.client.get("/healthz", catch_response=True) as resp:
            if resp.status_code == 200:
                resp.success()
            else:
                resp.failure(f"Health check failed: {resp.status_code}")


class SurgeUser(HttpUser):
    """
    Surge user — no think time, maximum throughput.
    Used in burst scenarios to simulate flash sale / traffic spike.
    """
    wait_time = constant_pacing(0.1)   # 10 RPS per user

    @task
    def surge_request(self):
        self.client.get("/api/products", name="/api/products [surge]")


# ── Event hooks for monitoring ────────────────────────────────────────────────
@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    if isinstance(environment.runner, MasterRunner):
        print("==> Surge load test starting")
        print(f"    Target host: {environment.host}")
        print(f"    Workers: {environment.runner.worker_count}")


@events.quitting.add_listener
def on_quitting(environment, **kwargs):
    stats = environment.stats.total
    print("\n=== LOAD TEST RESULTS ===")
    print(f"Total requests  : {stats.num_requests}")
    print(f"Failures        : {stats.num_failures}")
    print(f"Failure rate    : {stats.fail_ratio * 100:.3f}%")
    print(f"p50 latency     : {stats.get_response_time_percentile(0.5):.0f}ms")
    print(f"p95 latency     : {stats.get_response_time_percentile(0.95):.0f}ms")
    print(f"p99 latency     : {stats.get_response_time_percentile(0.99):.0f}ms")
    print(f"RPS (peak)      : {stats.max_response_time:.0f}ms max")
