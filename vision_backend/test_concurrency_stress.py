"""
Empirical Challenger Concurrency Stress Test Harness
Tests async threading, event loop unblocking, and health probe responsiveness
under concurrent camera scans, tests, and calibration frame requests.
"""

import asyncio
import time
import unittest
from unittest.mock import patch
import httpx
from main import app, pipeline, pipeline_lock


class VisionBackendConcurrencyStressTest(unittest.IsolatedAsyncioTestCase):

    async def asyncSetUp(self):
        # Warm up YOLO model
        if not pipeline.is_yolo_ready:
            pipeline.scan_camera(camera_id=1)

    async def test_01_health_responsiveness_during_normal_scan(self):
        """Verifies /health response time remains < 50ms while /api/camera/scan is running."""
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://testserver"
        ) as client:
            # Launch scan in background task
            scan_task = asyncio.create_task(client.get("/api/camera/scan?camera_id=1"))

            # Give task a moment to enter threadpool
            await asyncio.sleep(0.01)

            # Fire multiple health checks while scan is running
            health_latencies = []
            for _ in range(5):
                t0 = time.perf_counter()
                res = await client.get("/health")
                lat_ms = (time.perf_counter() - t0) * 1000
                health_latencies.append(lat_ms)
                self.assertEqual(res.status_code, 200)
                self.assertEqual(res.json()["status"], "ok")

            scan_res = await scan_task
            self.assertEqual(scan_res.status_code, 200)
            data = scan_res.json()
            self.assertIn("totalBottles", data)

            max_lat = max(health_latencies)
            avg_lat = sum(health_latencies) / len(health_latencies)
            print(f"\n   [PASS] Normal Scan Concurrency: max /health latency = {max_lat:.2f}ms, avg = {avg_lat:.2f}ms (< 50ms threshold)")
            self.assertLess(max_lat, 50.0, f"Health check took {max_lat:.2f}ms, exceeding 50ms limit during scan")

    async def test_02_health_and_status_during_long_running_scan(self):
        """Simulates heavy inference/scan (1.0s) in worker thread and verifies /health and /status latency < 50ms."""
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://testserver"
        ) as client:
            orig_scan = pipeline.scan_camera

            def slow_scan(*args, **kwargs):
                time.sleep(0.6)  # Simulate prolonged capture & inference
                return orig_scan(*args, **kwargs)

            with patch.object(pipeline, "scan_camera", side_effect=slow_scan):
                t_scan_start = time.perf_counter()
                scan_task = asyncio.create_task(client.post("/api/camera/scan", json={"camera_id": 2}))

                # Wait for scan to definitely be running in worker thread
                await asyncio.sleep(0.1)
                self.assertFalse(scan_task.done(), "Scan should still be in flight")

                # Test /health latency repeatedly while scan is running
                health_latencies = []
                for _ in range(10):
                    t0 = time.perf_counter()
                    res_health = await client.get("/health")
                    lat_ms = (time.perf_counter() - t0) * 1000
                    health_latencies.append(lat_ms)
                    self.assertEqual(res_health.status_code, 200)
                    self.assertEqual(res_health.json()["status"], "ok")
                    await asyncio.sleep(0.03)

                # Test /status latency
                t0_status = time.perf_counter()
                res_status = await client.get("/status")
                lat_status_ms = (time.perf_counter() - t0_status) * 1000
                self.assertEqual(res_status.status_code, 200)
                self.assertTrue(res_status.json()["yoloReady"])

                scan_res = await scan_task
                total_scan_time = time.perf_counter() - t_scan_start
                self.assertEqual(scan_res.status_code, 200)
                self.assertGreaterEqual(total_scan_time, 0.6)

                max_lat = max(health_latencies)
                avg_lat = sum(health_latencies) / len(health_latencies)
                print(f"   [PASS] Long Scan Concurrency (0.6s scan): max /health latency = {max_lat:.2f}ms, avg = {avg_lat:.2f}ms, /status latency = {lat_status_ms:.2f}ms (< 50ms threshold)")
                self.assertLess(max_lat, 50.0, f"Health latency {max_lat:.2f}ms exceeded 50ms threshold during 0.6s scan")
                self.assertLess(lat_status_ms, 50.0, f"Status latency {lat_status_ms:.2f}ms exceeded 50ms threshold during 0.6s scan")

    async def test_03_concurrent_camera_test_and_calibration_frame(self):
        """Tests concurrent requests across /api/camera/scan, /api/camera/test, and /calibration/frame."""
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://testserver"
        ) as client:
            t0 = time.perf_counter()
            # Launch all three heavy operations concurrently
            scan_coro = client.get("/api/camera/scan?camera_id=3")
            test_coro = client.post("/api/camera/test", json={"camera_id": 4})
            calib_coro = client.get("/calibration/frame")

            # Fire /health continuously during these three concurrent operations
            async def probe_health():
                lats = []
                for _ in range(8):
                    th0 = time.perf_counter()
                    r = await client.get("/health")
                    lats.append((time.perf_counter() - th0) * 1000)
                    self.assertEqual(r.status_code, 200)
                    await asyncio.sleep(0.02)
                return lats

            health_task = asyncio.create_task(probe_health())
            scan_res, test_res, calib_res = await asyncio.gather(scan_coro, test_coro, calib_coro)
            health_lats = await health_task

            elapsed = time.perf_counter() - t0
            self.assertEqual(scan_res.status_code, 200)
            self.assertEqual(test_res.status_code, 200)
            self.assertEqual(calib_res.status_code, 200)
            self.assertEqual(calib_res.headers["content-type"], "image/jpeg")

            max_lat = max(health_lats)
            avg_lat = sum(health_lats) / len(health_lats)
            print(f"   [PASS] Heavy Multi-Endpoint Concurrency: 3 heavy endpoints completed in {elapsed:.3f}s. max /health latency = {max_lat:.2f}ms, avg = {avg_lat:.2f}ms")
            self.assertLess(max_lat, 50.0, f"Health check latency {max_lat:.2f}ms exceeded 50ms during heavy concurrency")


if __name__ == "__main__":
    unittest.main()
