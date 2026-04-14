#!/bin/bash
# © 2026 Yost AI. All rights reserved.
# 06-server-b.sh — Server Provisioning Phase B (post-reboot)
# Usage: bash 06-server-b.sh <server-ip> <pem-path> <app-slug>
#
# Runs via SSH AFTER server has rebooted from Phase A.
# Installs Node.js, Claude Code, shared Python venv, all dependencies,
# sets timezone, installs crontab (append pattern), enables and starts systemd bot service.

set -e

SERVER_IP="${1}"
PEM_PATH="${2}"
APP_SLUG="${3}"

if [ -z "$SERVER_IP" ] || [ -z "$PEM_PATH" ] || [ -z "$APP_SLUG" ]; then
    echo "ERROR: Missing arguments"
    echo "Usage: bash 06-server-b.sh <server-ip> <pem-path> <app-slug>"
    exit 1
fi

echo "=== Server Provisioning — Phase B ==="
echo "  Server: $SERVER_IP"
echo "  App slug: $APP_SLUG"
echo ""

SSH_OPTS="-i $PEM_PATH -o StrictHostKeyChecking=no -o ServerAliveInterval=60"

# --- Node.js 22 ---
echo "--- Installing Node.js 22..."
ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "set -o pipefail; curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - 2>&1 | tail -3"
ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "sudo apt install -y nodejs 2>&1 | tail -3"

NODE_MAJOR=$(ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "node --version 2>/dev/null | sed 's/v//' | cut -d. -f1 || echo 0")
if [ "$NODE_MAJOR" -lt 22 ]; then
    echo "  Node.js v22 not found (got v${NODE_MAJOR}) — auto-retrying..."
    ssh $SSH_OPTS ubuntu@"$SERVER_IP" "sudo apt remove -y nodejs 2>/dev/null || true"
    ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
        "set -o pipefail; curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - 2>&1 | tail -3"
    ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
        "sudo apt install -y nodejs 2>&1 | tail -3"
    NODE_MAJOR=$(ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
        "node --version 2>/dev/null | sed 's/v//' | cut -d. -f1 || echo 0")
    if [ "$NODE_MAJOR" -lt 22 ]; then
        echo "  ERROR: Node.js v22 could not be installed after two attempts."
        echo "  This is usually a temporary network issue. Wait a minute and re-run Phase 6."
        exit 1
    fi
fi
echo "  OK: Node.js v${NODE_MAJOR}"

# --- Claude Code ---
echo "--- Installing Claude Code..."
ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "sudo npm install -g @anthropic-ai/claude-code 2>&1 | tail -3"
CLAUDE_VERSION=$(ssh $SSH_OPTS ubuntu@"$SERVER_IP" "claude --version 2>/dev/null || echo NOT_FOUND")
echo "  OK: $CLAUDE_VERSION"

# --- Shared Python venv ---
echo "--- Checking shared Python venv at /home/ubuntu/.venv..."
VENV_EXISTS=$(ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "[ -d /home/ubuntu/.venv ] && echo YES || echo NO")
if [ "$VENV_EXISTS" = "NO" ]; then
    echo "  Creating shared venv (first ProductOS on this server)..."
    ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
        "python3 -m venv /home/ubuntu/.venv"
    echo "  OK: shared venv created"
else
    echo "  SKIP: shared venv already exists — reusing"
fi

# --- Python dependencies (shared venv) ---
echo "--- Installing Python dependencies into shared venv..."
ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "/home/ubuntu/.venv/bin/pip install --upgrade pip --quiet && \
     /home/ubuntu/.venv/bin/pip install \
       anthropic \
       claude-agent-sdk \
       aiogram \
       python-telegram-bot \
       requests \
       python-dotenv \
       aiohttp \
       aiofiles \
       --quiet 2>&1 | tail -5"
echo "  OK"

# --- Install from requirements.txt if present ---
ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "cd /home/ubuntu/${APP_SLUG} && \
     if [ -f requirements.txt ]; then \
       /home/ubuntu/.venv/bin/pip install -r requirements.txt --quiet 2>/dev/null || true; \
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
    "set -a && source /home/ubuntu/${APP_SLUG}/.env && set +a && \
     mkdir -p ~/.aws && \
     aws configure set aws_access_key_id \"\$AWS_ACCESS_KEY_ID\" && \
     aws configure set aws_secret_access_key \"\$AWS_SECRET_ACCESS_KEY\" && \
     aws configure set default.region us-east-1"
echo "  OK: AWS credentials configured (~/.aws/credentials)"

# --- Crontab (append with slug markers — idempotent) ---
echo "--- Installing crontab entries for ${APP_SLUG}..."
ssh $SSH_OPTS ubuntu@"$SERVER_IP" "
    APP_SLUG='${APP_SLUG}'
    CRON_SOURCE=\"/home/ubuntu/\${APP_SLUG}/scripts/crontab-healthos.txt\"

    # Generate substituted entries: replace hardcoded paths with slug + shared venv
    CRON_CONTENT=\$(sed \
        -e \"s|/home/ubuntu/healthos/.venv/bin/python3|/home/ubuntu/.venv/bin/python3|g\" \
        -e \"s|/home/ubuntu/healthos|/home/ubuntu/\${APP_SLUG}|g\" \
        \"\$CRON_SOURCE\")

    # Guard: ensure content was actually generated
    if [ -z \"\$CRON_CONTENT\" ]; then
        echo \"ERROR: Failed to read crontab source at \$CRON_SOURCE\"
        exit 1
    fi

    # Strip existing block for this slug (idempotent on resume)
    EXISTING=\$(crontab -l 2>/dev/null || true)
    STRIPPED=\$(echo \"\$EXISTING\" | awk \"/# BEGIN \${APP_SLUG}/{skip=1} /# END \${APP_SLUG}/{skip=0;next} !skip\")
    if [ -n \"\$STRIPPED\" ]; then printf \"%s\\n\" \"\$STRIPPED\" | crontab -; fi

    # Append new block
    (crontab -l 2>/dev/null; echo \"# BEGIN \${APP_SLUG}\"; echo \"\$CRON_CONTENT\"; echo \"# END \${APP_SLUG}\") | crontab -
"
CRON_COUNT=$(ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "crontab -l | grep -v '^#' | grep -v '^\$' | wc -l | tr -d ' '")
echo "  OK: $CRON_COUNT total active cron entries"

# --- systemd bot service ---
echo "--- Installing and starting ${APP_SLUG}-bot systemd service..."
ssh $SSH_OPTS ubuntu@"$SERVER_IP" "
    # Copy service file with slug-based name
    sudo cp /home/ubuntu/${APP_SLUG}/scripts/systemd/healthos-bot.service \
        /etc/systemd/system/${APP_SLUG}-bot.service

    # Patch venv path first (must precede workspace path replacement)
    sudo sed -i 's|/home/ubuntu/healthos/.venv|/home/ubuntu/.venv|g' \
        /etc/systemd/system/${APP_SLUG}-bot.service

    # Patch workspace path
    sudo sed -i 's|/home/ubuntu/healthos|/home/ubuntu/${APP_SLUG}|g' \
        /etc/systemd/system/${APP_SLUG}-bot.service

    sudo systemctl daemon-reload
    sudo systemctl enable ${APP_SLUG}-bot
    sudo systemctl start ${APP_SLUG}-bot
"

echo "  Starting your HealthOS bot — this may take up to 60 seconds on first launch..."
BOT_WAIT=0
BOT_MAX=20
while true; do
    BOT_STATUS=$(ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
        "sudo systemctl is-active ${APP_SLUG}-bot 2>/dev/null || echo FAILED")
    if [ "$BOT_STATUS" = "active" ]; then
        echo "  OK: ${APP_SLUG}-bot is active (running)"
        break
    fi
    BOT_WAIT=$((BOT_WAIT + 1))
    if [ $BOT_WAIT -ge $BOT_MAX ]; then
        echo "  ERROR: ${APP_SLUG}-bot status: $BOT_STATUS after ${BOT_MAX} attempts"
        echo "  Check logs: ssh -i $PEM_PATH ubuntu@$SERVER_IP 'sudo journalctl -u ${APP_SLUG}-bot -n 30'"
        exit 1
    fi
    echo "  Status: $BOT_STATUS — waiting 3s..."
    sleep 3
done

echo ""
echo "=== Phase B Complete ==="
echo ""
echo "SERVER_B_OK=true"
