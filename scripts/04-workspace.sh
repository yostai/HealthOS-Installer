#!/bin/bash
# 04-workspace.sh — Clone HealthOS from GitHub onto server and write .env
# Usage: bash 04-workspace.sh <server-ip> <pem-path> <github-repo-url> \
#            <bot-token> <group-id> <anthropic-key> \
#            <bucket-name> <backup-key-id> <backup-secret>
#
# Clones HealthOS directly from GitHub onto the server.
# App code goes GitHub -> server only. Never touches the installer machine.

set -e

SERVER_IP="${1}"
PEM_PATH="${2}"
GITHUB_REPO_URL="${3}"
BOT_TOKEN="${4}"
GROUP_ID="${5}"
ANTHROPIC_KEY="${6}"
S3_BUCKET="${7}"
BACKUP_KEY_ID="${8}"
BACKUP_SECRET="${9}"

if [ -z "$SERVER_IP" ] || [ -z "$PEM_PATH" ] || [ -z "$GITHUB_REPO_URL" ]; then
    echo "ERROR: Missing required arguments"
    echo "Usage: bash 04-workspace.sh <server-ip> <pem-path> <github-repo-url> <bot-token> <group-id> <anthropic-key> <bucket> <backup-key-id> <backup-secret>"
    exit 1
fi

SSH_OPTS="-i $PEM_PATH -o StrictHostKeyChecking=no -o ServerAliveInterval=60"

echo "=== HealthOS Workspace Deploy ==="
echo "  Server: $SERVER_IP"
echo "  Source: GitHub repo"
echo ""

# --- Ensure git is available on server ---
echo "--- Ensuring git is available on server..."
ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "which git &>/dev/null && echo '  OK: git available' || (sudo apt install -y git 2>&1 | tail -2 && echo '  OK: git installed')"

# --- Clone HealthOS from GitHub onto server ---
echo "--- Cloning HealthOS onto server..."
ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "if [ -d /home/ubuntu/healthos/.git ]; then
         echo '  SKIP: healthos already cloned — pulling latest instead'
         cd /home/ubuntu/healthos && git pull
     else
         git clone $GITHUB_REPO_URL /home/ubuntu/healthos
         echo '  OK: HealthOS cloned'
     fi"

# --- Write .env directly to server ---
echo "--- Writing .env to server..."
ssh $SSH_OPTS ubuntu@"$SERVER_IP" "cat > /home/ubuntu/healthos/.env" <<ENVEOF
TELEGRAM_BOT_TOKEN=$BOT_TOKEN
TELEGRAM_GROUP_ID=$GROUP_ID
ANTHROPIC_API_KEY=$ANTHROPIC_KEY
AWS_ACCESS_KEY_ID=$BACKUP_KEY_ID
AWS_SECRET_ACCESS_KEY=$BACKUP_SECRET
AWS_DEFAULT_REGION=us-east-1
S3_BACKUP_BUCKET=$S3_BUCKET
ENVEOF

ssh $SSH_OPTS ubuntu@"$SERVER_IP" "chmod 600 /home/ubuntu/healthos/.env"
echo "  OK: .env written, permissions 600"

# --- Update backup script with actual bucket name ---
echo "--- Updating backup script with bucket name..."
ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "sed -i 's|BUCKET=s3://[^/]*|BUCKET=s3://$S3_BUCKET|' /home/ubuntu/healthos/scripts/backup_health_db.sh 2>/dev/null && echo '  OK: backup_health_db.sh updated' || echo '  SKIP: backup_health_db.sh not found'"

# --- Verify key files landed ---
echo "--- Verifying key files on server..."
MISSING=""
for f in ".env" "apps/command/__main__.py" "scripts/health_notify.py" "scripts/crontab-healthos.txt" "scripts/systemd/healthos-bot.service"; do
    if ! ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
        "test -f /home/ubuntu/healthos/$f" 2>/dev/null; then
        MISSING="$MISSING $f"
    fi
done

if [ -n "$MISSING" ]; then
    echo "  WARNING: Missing files on server:$MISSING"
    exit 1
else
    echo "  OK: All key files present on server"
fi

echo ""
echo "=== Workspace Deployed ==="
