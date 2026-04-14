#!/bin/bash
# © 2026 Yost AI. All rights reserved.
# 07-verify.sh — Full HealthOS installation verification suite
# Usage: bash 07-verify.sh <server-ip> <pem-path> <bot-token> <group-id> [ssh-alias] [app-slug]
#
# Runs 13 checks. Prints a summary table with pass/fail for each.
# If any check fails, prints the specific fix command.

SERVER_IP="${1}"
PEM_PATH="${2}"
BOT_TOKEN="${3}"
GROUP_ID="${4}"
SSH_ALIAS="${5:-$SERVER_IP}"  # defaults to IP if instance name not provided
APP_SLUG="${6:-healthos}"     # defaults to 'healthos' for backwards compatibility

if [ -z "$SERVER_IP" ] || [ -z "$PEM_PATH" ]; then
    echo "ERROR: Missing arguments"
    echo "Usage: bash 07-verify.sh <server-ip> <pem-path> <bot-token> <group-id> [ssh-alias] [app-slug]"
    exit 1
fi

SSH_OPTS="-i $PEM_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=10"

echo "=== HealthOS Verification Suite ==="
echo "  Server: $SERVER_IP"
echo "  App slug: $APP_SLUG"
echo ""

PASS_COUNT=0
FAIL_COUNT=0
FIXES=""

check() {
    local NAME="$1"
    local CMD="$2"
    local FIX="$3"

    if eval "$CMD" &>/dev/null 2>&1; then
        echo "  OK  $NAME"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL $NAME"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        if [ -n "$FIX" ]; then
            FIXES="$FIXES\n  [$NAME] $FIX"
        fi
    fi
}

# 1. SSH connection
check "SSH connection" \
    "ssh $SSH_OPTS ubuntu@$SERVER_IP 'echo OK'" \
    "Check: ssh -i $PEM_PATH ubuntu@$SERVER_IP 'echo OK'"

# 2. Python imports
check "Python imports (anthropic, aiogram, dotenv)" \
    "ssh $SSH_OPTS ubuntu@$SERVER_IP '/home/ubuntu/.venv/bin/python3 -c \"import anthropic; import aiogram; import dotenv; print(\\\"OK\\\")\"'" \
    "Run: ssh $SSH_ALIAS && /home/ubuntu/.venv/bin/pip install anthropic aiogram python-dotenv"

# 3. Claude Code installed
check "Claude Code installed" \
    "ssh $SSH_OPTS ubuntu@$SERVER_IP 'claude --version'" \
    "Run: ssh $SSH_ALIAS && sudo npm install -g @anthropic-ai/claude-code"

# 4. Timezone
check "Timezone = America/New_York" \
    "ssh $SSH_OPTS ubuntu@$SERVER_IP 'timedatectl | grep -q \"America/New_York\"'" \
    "Run: ssh $SSH_ALIAS && sudo timedatectl set-timezone America/New_York"

# 5. Firewall: port 80 is closed (tests from Mac side via nc)
check "Firewall: port 80 closed" \
    "! nc -z -w 3 $SERVER_IP 80 2>/dev/null" \
    "Close port 80: aws lightsail close-instance-public-ports --instance-name <name> --port-info fromPort=80,toPort=80,protocol=tcp"

# 6. systemd bot service active
check "systemd: ${APP_SLUG}-bot active" \
    "ssh $SSH_OPTS ubuntu@$SERVER_IP 'sudo systemctl is-active ${APP_SLUG}-bot | grep -q active'" \
    "Run: ssh $SSH_ALIAS && sudo systemctl start ${APP_SLUG}-bot && sudo journalctl -u ${APP_SLUG}-bot -n 30"

# 7. Crontab entries
check "Crontab: 6+ entries installed" \
    "ssh $SSH_OPTS ubuntu@$SERVER_IP 'crontab -l | grep -v \"^#\" | grep -v \"^$\" | wc -l | awk \"{exit (\\\$1 < 6)}\"'" \
    "Re-run Phase 6 to append crontab entries for ${APP_SLUG}"

# 8. .env exists with correct permissions
check ".env exists with correct permissions" \
    "ssh $SSH_OPTS ubuntu@$SERVER_IP 'test -f /home/ubuntu/${APP_SLUG}/.env && stat -c \"%a\" /home/ubuntu/${APP_SLUG}/.env | grep -q 600'" \
    "Run: ssh $SSH_ALIAS && chmod 600 ~/${APP_SLUG}/.env"

# 9. Swap active
check "Swap: 2GB active" \
    "ssh $SSH_OPTS ubuntu@$SERVER_IP 'swapon --show | grep -q swapfile'" \
    "Run: ssh $SSH_ALIAS && sudo swapon /swapfile — if missing, re-run scripts/05-server-a.sh"

# 10. apps/command/__main__.py exists
check "apps/command/__main__.py exists" \
    "ssh $SSH_OPTS ubuntu@$SERVER_IP 'test -f /home/ubuntu/${APP_SLUG}/apps/command/__main__.py'" \
    "Check: ssh $SSH_ALIAS && ls ~/${APP_SLUG}/apps/command/__main__.py"

# 11. apps.command module importable
check "apps.command module importable" \
    "ssh $SSH_OPTS ubuntu@$SERVER_IP 'cd /home/ubuntu/${APP_SLUG} && /home/ubuntu/.venv/bin/python3 -c \"import apps.command; print(\\\"OK\\\")\" 2>&1 | grep -q OK'" \
    "Run: ssh $SSH_ALIAS && cd ${APP_SLUG} && /home/ubuntu/.venv/bin/python3 -c \"import apps.command\" to see the import error"

# 12. Telegram: token valid + send install confirmation message
if [ -n "$BOT_TOKEN" ] && [ -n "$GROUP_ID" ]; then
    check "Telegram: bot connected + message sent" \
        "curl -sf -X POST 'https://api.telegram.org/bot${BOT_TOKEN}/sendMessage' \
            -d chat_id=${GROUP_ID} \
            -d text='✅ HealthOS is installed and connected.

Congratulations on your new HealthOS Coach. When you are ready to set up your coach, please type '\''setup'\'' here.' \
            | python3 -c \"import sys,json; d=json.load(sys.stdin); exit(0 if d.get('ok') else 1)\"" \
        "Check bot token and group ID — make sure the bot is an admin in your Telegram group"
else
    echo "  SKIP Telegram test (no token/group-id provided)"
fi

# 13. Node.js version
check "Node.js 22+ installed" \
    "ssh $SSH_OPTS ubuntu@$SERVER_IP 'node --version | grep -q \"v22\"'" \
    "Run: ssh $SSH_ALIAS && curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt install -y nodejs"

echo ""
echo "======================================="
echo "  Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "======================================="

if [ $FAIL_COUNT -gt 0 ]; then
    echo ""
    echo "Fix commands:"
    printf "$FIXES\n"
    echo ""
    exit 1
else
    echo ""
    echo "All checks passed. HealthOS is fully operational."
    echo ""
    echo "  SSH access:    ssh $SSH_ALIAS"
    echo "  Bot status:    ssh $SSH_ALIAS 'sudo systemctl status ${APP_SLUG}-bot'"
    echo "  Bot logs:      ssh $SSH_ALIAS 'sudo journalctl -u ${APP_SLUG}-bot -f'"
    echo "  Cron logs:     ssh $SSH_ALIAS 'tail -f ~/${APP_SLUG}/scripts/health.log'"
fi
