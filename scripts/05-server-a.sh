#!/bin/bash
# 05-server-a.sh — Server Provisioning Phase A (pre-reboot)
# Usage: bash 05-server-a.sh <server-ip> <pem-path>
#
# Runs via SSH. Performs apt update/upgrade, installs base packages, reboots.
# Phase B must run AFTER the server is back up from reboot.
#
# IMPORTANT: apt upgrade on Ubuntu 24.04 triggers a kernel update.
# The server MUST reboot before Phase B or Node.js install will fail.

set -e

SERVER_IP="${1}"
PEM_PATH="${2}"

if [ -z "$SERVER_IP" ] || [ -z "$PEM_PATH" ]; then
    echo "ERROR: Missing arguments"
    echo "Usage: bash 05-server-a.sh <server-ip> <pem-path>"
    exit 1
fi

echo "=== Server Provisioning — Phase A ==="
echo "  Server: $SERVER_IP"
echo ""

SSH_OPTS="-i $PEM_PATH -o StrictHostKeyChecking=no -o ServerAliveInterval=60"

# --- System update ---
echo "--- Running apt update..."
ssh $SSH_OPTS ubuntu@"$SERVER_IP" "sudo apt update -y 2>&1 | tail -3"
echo "  OK"

echo "--- Running apt upgrade (this takes 1-3 minutes)..."
ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y 2>&1 | tail -5"
echo "  OK"

# --- Install base packages ---
echo "--- Installing base packages..."
ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "sudo apt install -y python3.12-venv python3-dev build-essential \
     libpango-1.0-0 libpangoft2-1.0-0 libgdk-pixbuf2.0-0 \
     libffi-dev libssl-dev curl wget awscli 2>&1 | tail -5"
echo "  OK"

# --- Reboot ---
echo "--- Rebooting server (kernel upgrade requires reboot)..."
ssh $SSH_OPTS ubuntu@"$SERVER_IP" "sudo reboot" 2>/dev/null || true
echo "  Reboot command sent. Waiting for server to go down..."
sleep 15

# --- Wait for SSH to come back ---
echo "--- Waiting for SSH to come back up..."
WAIT=0
MAX=24  # 4 minutes max
while true; do
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$PEM_PATH" \
        ubuntu@"$SERVER_IP" "echo UP" &>/dev/null 2>&1; then
        echo "  OK: Server is back up"
        break
    fi
    WAIT=$((WAIT + 1))
    if [ $WAIT -ge $MAX ]; then
        echo "  ERROR: Server did not come back within 4 minutes"
        echo "  Try: ssh -i $PEM_PATH ubuntu@$SERVER_IP 'echo UP'"
        exit 1
    fi
    echo "  Still booting... (${WAIT}0s elapsed)"
    sleep 10
done

echo ""
echo "=== Phase A Complete — Server Rebooted and Up ==="
echo ""
echo "SERVER_A_OK=true"
