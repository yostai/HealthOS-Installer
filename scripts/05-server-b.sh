#!/bin/bash
# 05-server-b.sh — Server Provisioning Phase B (post-reboot)
# Usage: bash 05-server-b.sh <server-ip> <pem-path>
#
# Runs via SSH AFTER server has rebooted from Phase A.
# Installs Node.js, Claude Code, Python venv, all dependencies,
# sets timezone, installs crontab, enables and starts systemd bot service.

set -e

SERVER_IP="${1}"
PEM_PATH="${2}"

if [ -z "$SERVER_IP" ] || [ -z "$PEM_PATH" ]; then
    echo "ERROR: Missing arguments"
    echo "Usage: bash 05-server-b.sh <server-ip> <pem-path>"
    exit 1
fi

echo "=== Server Provisioning — Phase B ==="
echo "  Server: $SERVER_IP"
echo ""

SSH_OPTS="-i $PEM_PATH -o StrictHostKeyChecking=no -o ServerAliveInterval=60"

# --- Node.js 22 ---
echo "--- Installing Node.js 22..."
ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - 2>&1 | tail -3"
ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "sudo apt install -y nodejs 2>&1 | tail -3"
NODE_VERSION=$(ssh $SSH_OPTS ubuntu@"$SERVER_IP" "node --version 2>/dev/null || echo NOT_FOUND")
echo "  OK: $NODE_VERSION"

# --- Claude Code ---
echo "--- Installing Claude Code..."
ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "sudo npm install -g @anthropic-ai/claude-code 2>&1 | tail -3"
CLAUDE_VERSION=$(ssh $SSH_OPTS ubuntu@"$SERVER_IP" "claude --version 2>/dev/null || echo NOT_FOUND")
echo "  OK: $CLAUDE_VERSION"

# --- Python venv ---
echo "--- Creating Python virtual environment..."
ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "cd /home/ubuntu/healthos && python3 -m venv .venv"
echo "  OK"

# --- Python dependencies ---
echo "--- Installing Python dependencies (this takes 2-4 minutes)..."
ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "cd /home/ubuntu/healthos && \
     .venv/bin/pip install --upgrade pip --quiet && \
     .venv/bin/pip install \
       anthropic \
       claude-agent-sdk \
       aiogram \
       python-telegram-bot \
       requests \
       python-dotenv \
       playwright \
       aiohttp \
       aiofiles \
       --quiet 2>&1 | tail -5"
echo "  OK"

# --- Playwright Chromium browser ---
echo "--- Installing Playwright Chromium..."
ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "cd /home/ubuntu/healthos && \
     sudo apt install -y libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 \
       libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 \
       libxrandr2 libgbm1 libasound2 2>&1 | tail -3 && \
     .venv/bin/playwright install chromium 2>&1 | tail -3"
echo "  OK: Playwright Chromium installed"

# --- Install from requirements.txt if present ---
ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "cd /home/ubuntu/healthos && \
     if [ -f requirements.txt ]; then \
       .venv/bin/pip install -r requirements.txt --quiet 2>/dev/null || true; \
       echo '  OK: requirements.txt installed'; \
     fi"

# --- Timezone ---
echo "--- Setting timezone to America/New_York..."
ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "sudo timedatectl set-timezone America/New_York"
TZ=$(ssh $SSH_OPTS ubuntu@"$SERVER_IP" "timedatectl | grep 'Time zone' | awk '{print \$3}'")
echo "  OK: $TZ"

# --- AWS credentials for S3 backup (cron doesn't source .env) ---
echo "--- Configuring AWS credentials for S3 backup..."
ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "set -a && source /home/ubuntu/healthos/.env && set +a && \
     mkdir -p ~/.aws && \
     aws configure set aws_access_key_id \"\$AWS_ACCESS_KEY_ID\" && \
     aws configure set aws_secret_access_key \"\$AWS_SECRET_ACCESS_KEY\" && \
     aws configure set default.region us-east-1"
echo "  OK: AWS credentials configured (~/.aws/credentials)"

# --- Crontab ---
echo "--- Installing crontab..."
ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "crontab /home/ubuntu/healthos/scripts/crontab-healthos.txt"
CRON_COUNT=$(ssh $SSH_OPTS ubuntu@"$SERVER_IP" "crontab -l | grep -v '^#' | grep -v '^$' | wc -l | tr -d ' '")
echo "  OK: $CRON_COUNT active cron entries"

# --- systemd bot service ---
echo "--- Installing and starting healthos-bot systemd service..."
ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "sudo cp /home/ubuntu/healthos/scripts/systemd/healthos-bot.service /etc/systemd/system/ && \
     sudo systemctl daemon-reload && \
     sudo systemctl enable healthos-bot && \
     sudo systemctl start healthos-bot"

echo "  Waiting for bot to start..."
BOT_WAIT=0
BOT_MAX=5
while true; do
    BOT_STATUS=$(ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
        "sudo systemctl is-active healthos-bot 2>/dev/null || echo FAILED")
    if [ "$BOT_STATUS" = "active" ]; then
        echo "  OK: healthos-bot is active (running)"
        break
    fi
    BOT_WAIT=$((BOT_WAIT + 1))
    if [ $BOT_WAIT -ge $BOT_MAX ]; then
        echo "  ERROR: healthos-bot status: $BOT_STATUS after ${BOT_MAX} attempts"
        echo "  Check logs: ssh -i $PEM_PATH ubuntu@$SERVER_IP 'sudo journalctl -u healthos-bot -n 30'"
        exit 1
    fi
    echo "  Status: $BOT_STATUS — waiting 3s..."
    sleep 3
done

echo ""
echo "=== Phase B Complete ==="
echo ""
echo "SERVER_B_OK=true"
