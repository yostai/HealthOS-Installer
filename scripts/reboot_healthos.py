#!/usr/bin/env python3
"""
reboot_healthos.py — Reboot your HealthOS Lightsail instance from your Mac.

Usage: python3 scripts/reboot_healthos.py

Uses AWS credentials already configured on your Mac during install.
No extra login or keys required.
"""

import glob
import json
import subprocess
import sys
import time
from pathlib import Path

INSTALLER_DIR = Path(__file__).parent.parent


def find_instance_name():
    """Read instance name from install-state file written during install."""
    state_files = sorted(glob.glob(str(INSTALLER_DIR / "install-state-*.json")))
    if state_files:
        try:
            with open(state_files[-1]) as f:
                data = json.load(f)
            name = data.get("config", {}).get("instance_name")
            if name:
                return name
        except (json.JSONDecodeError, OSError):
            pass
    return None


def main():
    print("HealthOS Reboot Tool")
    print("--------------------")

    instance_name = find_instance_name()

    if not instance_name:
        print("Could not find your instance name automatically.")
        instance_name = input("Enter your Lightsail instance name (e.g. healthos-personal): ").strip()
        if not instance_name:
            print("No instance name provided. Exiting.")
            sys.exit(1)

    print(f"Instance: {instance_name}")
    print("Sending reboot command...")

    result = subprocess.run(
        ["aws", "lightsail", "reboot-instance", "--instance-name", instance_name],
        capture_output=True, text=True
    )

    if result.returncode != 0:
        print(f"\nReboot failed. Error from AWS:")
        print(result.stderr.strip() or result.stdout.strip())
        print("\nCommon fixes:")
        print("  - Wrong instance name: check the Lightsail console for the exact name")
        print("  - Credentials expired: run 'aws configure' with your IAM keys")
        sys.exit(1)

    print("Reboot command sent.")
    print("Waiting for HealthOS to come back up (~60 seconds)...")

    time.sleep(20)
    for i in range(1, 9):
        check = subprocess.run(
            ["aws", "lightsail", "get-instance",
             "--instance-name", instance_name,
             "--query", "instance.state.name",
             "--output", "text"],
            capture_output=True, text=True
        )
        state = check.stdout.strip()
        if state == "running":
            print(f"\nHealthOS is back online. Your bot should be active within 30 seconds.")
            return
        print(f"  Status: {state} — checking again in 10s... ({i}/8)")
        time.sleep(10)

    print("\nInstance is taking longer than expected.")
    print("Check the Lightsail console for status, or wait a minute and try your Telegram bot.")


if __name__ == "__main__":
    main()
