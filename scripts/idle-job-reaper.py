#!/usr/bin/env python

import argparse
import json
import subprocess
import sys
import time
from datetime import datetime, timedelta
from typing import List, Dict
import requests

class GPUJobReaper:
    def __init__(self):
        self.step_min = 1
        self.window_min = 60
        self.expected_values = self.window_min // self.step_min + 1
        self.min_util = 5.0
        self.prometheus_url = "http://localhost:8428/prometheus/api/v1/query_range"

    def get_gpu_jobs(self) -> List[int]:
        try:
            result = subprocess.run(
                ["squeue", "--json=v0.0.40"],
                capture_output=True,
                text=True,
                check=True
            )

            queue_data = json.loads(result.stdout)
            job_ids = []

            for job in queue_data.get("jobs", []):
                if (job.get("tres_alloc_str", "").find("gres/gpu") != -1 and
                    job.get("job_state", [""])[0] == "RUNNING"):
                    job_ids.append(int(job["job_id"]))

            return sorted(job_ids)

        except subprocess.CalledProcessError as e:
            print(f"Error running squeue: {e}", file=sys.stderr)
            return []
        except json.JSONDecodeError as e:
            print(f"Error parsing squeue JSON: {e}", file=sys.stderr)
            return []

    def get_gpu_utilization(self, job_id: int) -> Dict:
        now = datetime.now()
        start_time = now - timedelta(minutes=self.window_min)

        params = {
            "query": f'avg(gpu_job_utilisation{{job_id="{job_id}"}})',
            "start": start_time.isoformat() + "Z",
            "end": now.isoformat() + "Z",
            "step": f"{self.step_min}m"
        }

        try:
            response = requests.get(self.prometheus_url, params=params, timeout=3)
            response.raise_for_status()

            data = response.json()
            result = data.get("data", {}).get("result", [])
            values = (result[0] if result else {}).get("values", [])

            if not values:
                return {"values": [], "avg_util": 0.0, "max_util": 0.0}

            util_values = [float(val[1]) for val in values]

            if util_values:
                avg_util = sum(util_values) / len(util_values)
                max_util = max(util_values)
            else:
                avg_util = 0.0
                max_util = 0.0

            return {
                "values": util_values,
                "avg_util": avg_util,
                "max_util": max_util
            }

        except requests.RequestException as e:
            print(f"Error querying Prometheus for job {job_id}: {e}", file=sys.stderr)
            return {"values": [], "avg_util": 0.0, "max_util": 0.0}

    def get_job_info(self, job_id: int) -> Dict:
        try:
            result = subprocess.run(
                ["scontrol", "show", "job", str(job_id), "--json=v0.0.40"],
                capture_output=True,
                text=True,
                check=True
            )

            job_data = json.loads(result.stdout)
            job = job_data["jobs"][0]

            tres_alloc = job.get("tres_alloc_str", "")
            gpu_count = 0
            if "gres/gpu=" in tres_alloc:
                gpu_part = tres_alloc.split("gres/gpu=")[1]
                gpu_count = gpu_part.split(",")[0].split(":")[0]
            else:
                raise ValueError(f"No GPUs found for job {job_id}")

            return {
                "owner": job.get("user_name", "unknown"),
                "partition": job.get("partition", "unknown")[:7],  # Truncate like original
                "command": job.get("command", "unknown")[:10],     # Truncate like original
                "gpus": gpu_count,
                "start_time": job.get("start_time", {}).get("number", 0)
            }

        except subprocess.CalledProcessError as e:
            print(f"Error getting job info for {job_id}: {e}", file=sys.stderr)
            return {
                "owner": "unknown", "partition": "unknown", "command": "unknown",
                "gpus": "0", "start_time": 0
            }
        except (json.JSONDecodeError, KeyError) as e:
            print(f"Error parsing job info for {job_id}: {e}", file=sys.stderr)
            return {
                "owner": "unknown", "partition": "unknown", "command": "unknown",
                "gpus": "0", "start_time": 0
            }
        except ValueError as e:
            print(f"Error getting job info for {job_id}: {e}", file=sys.stderr)
            return {
                "owner": "unknown", "partition": "unknown", "command": "unknown",
                "gpus": "0", "start_time": 0
            }

    def should_reap_job(self, util_data: Dict) -> bool:
        values = util_data["values"]
        avg_util = util_data["avg_util"]

        return (len(values) == self.expected_values and avg_util <= self.min_util)

    def reap_job(self, job_id: int) -> bool:
        try:
            admin_comment = f"GPU utilization below threshold of {self.min_util} for {self.window_min} minutes"
            subprocess.run(
                ["sudo", "scontrol", "update", f"job={job_id}", f"AdminComment={admin_comment}"],
                check=True
            )

            subprocess.run(["sudo", "scancel", str(job_id)], check=True)
            return True

        except subprocess.CalledProcessError as e:
            print(f"Error reaping job {job_id}: {e}", file=sys.stderr)
            return False

    def format_duration(self, duration_seconds: float) -> float:
        return round(duration_seconds / 3600, 1)

    def run(self, reap_enabled: bool = False):
        print(datetime.now().strftime("%Y-%m-%d %H:%M:%S"))

        now_timestamp = time.time()
        job_ids = self.get_gpu_jobs()

        cancel_queue = []

        print(f"{'Job ID':>8} {'Job Owner':>18} {'Partition':>10} {'Command':>10} "
              f"{'GPUs':>5} {'Avg GPU Util':>13} {'Max GPU Util':>13} "
              f"{'Duration (h)':>13} {'Full Data?':>11} {'Reap?':>5}")

        for job_id in job_ids:
            util_data = self.get_gpu_utilization(job_id)
            job_info = self.get_job_info(job_id)
            duration_h = self.format_duration(now_timestamp - job_info["start_time"])
            should_reap = self.should_reap_job(util_data)
            reap_str = "REAP" if should_reap else ""

            if should_reap:
                cancel_queue.append(job_id)

            full_data_str = "Y" if len(util_data["values"]) == self.expected_values else "N"

            print(f"{job_id:>8} {job_info['owner']:>18} {job_info['partition']:>10} "
                  f"{job_info['command']:>10} {job_info['gpus']:>5} "
                  f"{util_data['avg_util']:>13.2f} {util_data['max_util']:>13.2f} "
                  f"{duration_h:>13.1f} {full_data_str:>11} {reap_str:>5}")

        if reap_enabled and cancel_queue:
            for job_id in cancel_queue:
                print(f"REAPING {job_id}")
                success = self.reap_job(job_id)
                if not success:
                    print(f"Failed to reap job {job_id}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(
        description="Monitor and optionally cancel GPU jobs with low utilization"
    )
    parser.add_argument(
        "action",
        nargs="?",
        choices=["reap", "--reap"],
        help="Enable job cancellation for low-utilization jobs"
    )

    args = parser.parse_args()
    reap_enabled = args.action in ["reap", "--reap"]

    reaper = GPUJobReaper()
    reaper.run(reap_enabled)

if __name__ == "__main__":
    main():
