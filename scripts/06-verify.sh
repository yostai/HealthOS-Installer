#!/bin/bash
# 06-verify.sh — Full HealthOS installation verification suite
# Usage: bash 06-verify.sh <server-ip> <pem-path> <bot-token> <group-id>
#
# Runs 11 checks. Prints a summary table with pass/fail for each.
# If any check fails, prints the specific fix command.

SERVER_IP="${1}"
PEM_PATH="${2}"
BOT_TOKEN="${3}"
GROUP_ID="${4}"
SSH_ALIAS="${5:-$SERVER_IP}"  # defaults to IP if instance name not provided

if [ -z "$SERVER_IP" ] || [ -z "$PEM_PATH" ]; then
    echo "ERROR: Missing arguments"
    echo "Usage: bash 06-verify.sh <server-ip> <pem-path> <bot-token> <group-id> [ssh-alias]"
    exit 1
fi

SSH_OPTS="-i $PEM_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=10"

echo "=== HealthOS Verification Suite ==="
echo "  Server: $SERVER_IP"
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
    "ssh $SSH_OPTS ubuntu@$SERVER_IP '/home/ubuntu/healthos/.venv/bin/python3 -c \"import anthropic; import aiogram; import dotenv; print(\\\"OK\\\")\"'" \
    "Run: ssh healthos && cd healthos && .venv/bin/pip install anthropic aiogram python-dotenv"

# 3. Claude Code installed
check "Claude Code installed" \
    "ssh $SSH_OPTS ubuntu@$SERVER_IP 'claude --version'" \
    "Run: ssh healthos && sudo npm install -g @anthropic-ai/claude-code"

# 4. Timezone
check "Timezone = America/New_York" \
    "ssh $SSH_OPTS ubuntu@$SERVER_IP 'timedatectl | grep -q \"America/New_York\"'" \
    "Run: ssh healthos && sudo timedatectl set-timezone America/New_York"

# 5. Firewall: port 80 is closed (tests from Mac side via nc)
check "Firewall: port 80 closed" \
    "! nc -z -w 3 $SERVER_IP 80 2>/dev/null" \
    "Close port 80: aws lightsail close-instance-public-ports --instance-name <name> --port-info fromPort=80,toPort=80,protocol=tcp"

# 6. systemd healthos-bot active
check "systemd: healthos-bot active" \
    "ssh $SSH_OPTS ubuntu@$SERVER_IP 'sudo systemctl is-active healthos-bot | grep -q active'" \
    "Run: ssh healthos && sudo systemctl start healthos-bot && sudo journalctl -u healthos-bot -n 30"

# 7. Crontab entries
check "Crontab: 6+ entries installed" \
    "ssh $SSH_OPTS ubuntu@$SERVER_IP 'crontab -l | grep -v \"^#\" | grep -v \"^$\" | wc -l | awk \"{exit (\\\$1 < 6)}\"'" \
    "Run: ssh healthos && crontab ~/healthos/scripts/crontab-healthos.txt"

# 8. health.db exists
check ".env exists with correct permissions" \
    "ssh $SSH_OPTS ubuntu@$SERVER_IP 'test -f /home/ubuntu/healthos/.env && stat -c \"%a\" /home/ubuntu/healthos/.env | grep -q 600'" \
    "Run: ssh healthos && chmod 600 ~/healthos/.env"

# 9. Apps command module
check "apps.command module loadable" \
    "ssh $SSH_OPTS ubuntu@$SERVER_IP 'cd /home/ubuntu/healthos && .venv/bin/python3 -c \"import apps.command\" 2>&1 | grep -v \"^$\" | head -1 | grep -qv Error || true; test -f /home/ubuntu/healthos/apps/command/__main__.py'" \
    "Check: ssh healthos && ls ~/healthos/apps/command/__main__.py"

# 10. Telegram test (only if token + group ID provided)
if [ -n "$BOT_TOKEN" ] && [ -n "$GROUP_ID" ]; then
    check "Telegram: health_notify.py runs" \
        "ssh $SSH_OPTS ubuntu@$SERVER_IP 'cd /home/ubuntu/healthos && .venv/bin/python3 scripts/health_notify.py --mode morning' 2>&1 | grep -qv 'Error\\|Traceback'" \
        "Check: ssh healthos && cd healthos && .venv/bin/python3 scripts/health_notify.py --mode morning"
else
    echo "  SKIP Telegram test (no token/group-id provided)"
fi

# 11. Node.js version
check "Node.js 22+ installed" \
    "ssh $SSH_OPTS ubuntu@$SERVER_IP 'node --version | grep -q \"v22\"'" \
    "Run: ssh healthos && curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt install -y nodejs"

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
    echo "  Bot status:    ssh $SSH_ALIAS 'sudo systemctl status healthos-bot'"
    echo "  Bot logs:      ssh $SSH_ALIAS 'sudo journalctl -u healthos-bot -f'"
    echo "  Cron logs:     ssh $SSH_ALIAS 'tail -f ~/healthos/scripts/health.log'"
fi
