#!/bin/bash
# 02-aws.sh — Create full HealthOS AWS infrastructure via CLI
# Usage: bash 02-aws.sh <instance-name> <key-name> <static-ip-name>
# Example: bash 02-aws.sh healthos-personal healthos-key healthos-static-ip
#
# Outputs (printed to stdout, capture with eval):
#   STATIC_IP=<ip>
#   PEM_PATH=<path>
#   SSH_HOST=healthos
#
# IMPORTANT: All resources created in us-east-1a (Virginia). Do NOT rely on defaults.

set -e

INSTANCE_NAME="${1:-healthos-personal}"
KEY_NAME="${2:-healthos-key}"
STATIC_IP_NAME="${3:-healthos-static-ip}"
AZ="us-east-1a"
BLUEPRINT="ubuntu_24_04"
BUNDLE="small_3_0"
PEM_PATH="$HOME/.ssh/${KEY_NAME}.pem"

echo "=== HealthOS AWS Infrastructure Setup ==="
echo "  Instance:  $INSTANCE_NAME"
echo "  Key pair:  $KEY_NAME"
echo "  Static IP: $STATIC_IP_NAME"
echo "  Region:    $AZ"
echo "  Bundle:    $BUNDLE (1GB RAM, \$7/mo)"
echo ""

# --- SSH Key Pair ---
echo "--- Creating SSH key pair..."
if aws lightsail get-key-pair --key-pair-name "$KEY_NAME" &>/dev/null 2>&1; then
    echo "  SKIP: Key pair '$KEY_NAME' already exists"
    echo "  WARNING: Cannot re-download private key. If you don't have $PEM_PATH, delete the key pair and re-run."
    if [ ! -f "$PEM_PATH" ]; then
        echo "  ERROR: $PEM_PATH not found and key pair exists — cannot proceed."
        echo "  Fix: aws lightsail delete-key-pair --key-pair-name $KEY_NAME && re-run this script"
        exit 1
    fi
else
    aws lightsail create-key-pair --key-pair-name "$KEY_NAME" \
        --query 'privateKeyBase64' --output text > "$PEM_PATH"
    chmod 400 "$PEM_PATH"
    echo "  OK: Private key written to $PEM_PATH"
fi

# --- Lightsail Instance ---
echo "--- Creating Lightsail instance..."
if aws lightsail get-instance --instance-name "$INSTANCE_NAME" &>/dev/null 2>&1; then
    echo "  SKIP: Instance '$INSTANCE_NAME' already exists"
else
    aws lightsail create-instances \
        --instance-names "$INSTANCE_NAME" \
        --availability-zone "$AZ" \
        --blueprint-id "$BLUEPRINT" \
        --bundle-id "$BUNDLE" \
        --key-pair-name "$KEY_NAME"
    echo "  OK: Instance creation initiated"
fi

# --- Wait for instance to be running ---
echo "--- Waiting for instance to be running..."
WAIT_COUNT=0
MAX_WAIT=18  # 3 minutes max (18 x 10s)
while true; do
    STATE=$(aws lightsail get-instance-state --instance-name "$INSTANCE_NAME" \
        --query 'state.name' --output text 2>/dev/null || echo "pending")
    if [ "$STATE" = "running" ]; then
        echo "  OK: Instance is running"
        break
    fi
    WAIT_COUNT=$((WAIT_COUNT + 1))
    if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
        echo "  ERROR: Instance did not reach running state after 3 minutes"
        echo "  Check AWS Console for status"
        exit 1
    fi
    echo "  State: $STATE — waiting 10s..."
    sleep 10
done

# --- Static IP ---
echo "--- Allocating static IP..."
if aws lightsail get-static-ip --static-ip-name "$STATIC_IP_NAME" &>/dev/null 2>&1; then
    echo "  SKIP: Static IP '$STATIC_IP_NAME' already exists"
else
    aws lightsail allocate-static-ip --static-ip-name "$STATIC_IP_NAME"
    echo "  OK: Static IP allocated"
fi

# --- Attach Static IP ---
echo "--- Attaching static IP to instance..."
ATTACHED_TO=$(aws lightsail get-static-ip --static-ip-name "$STATIC_IP_NAME" \
    --query 'staticIp.attachedTo' --output text 2>/dev/null || echo "None")
if [ "$ATTACHED_TO" = "$INSTANCE_NAME" ]; then
    echo "  SKIP: Already attached to $INSTANCE_NAME"
elif [ "$ATTACHED_TO" != "None" ] && [ -n "$ATTACHED_TO" ]; then
    echo "  WARNING: Static IP is attached to $ATTACHED_TO (not $INSTANCE_NAME)"
    echo "  Detaching and reattaching..."
    aws lightsail detach-static-ip --static-ip-name "$STATIC_IP_NAME"
    sleep 3
    aws lightsail attach-static-ip --static-ip-name "$STATIC_IP_NAME" --instance-name "$INSTANCE_NAME"
    echo "  OK: Reattached to $INSTANCE_NAME"
else
    aws lightsail attach-static-ip --static-ip-name "$STATIC_IP_NAME" --instance-name "$INSTANCE_NAME"
    echo "  OK: Attached to $INSTANCE_NAME"
fi

# --- Get Static IP address ---
STATIC_IP=$(aws lightsail get-static-ip --static-ip-name "$STATIC_IP_NAME" \
    --query 'staticIp.ipAddress' --output text)
echo "  Static IP: $STATIC_IP"

# --- Close port 80 (open by default on Lightsail Ubuntu) ---
echo "--- Closing port 80..."
aws lightsail close-instance-public-ports \
    --instance-name "$INSTANCE_NAME" \
    --port-info fromPort=80,toPort=80,protocol=tcp 2>/dev/null || true
echo "  OK: Port 80 closed (only port 22 open)"

# --- Write SSH config entry ---
echo "--- Writing SSH config entry..."
SSH_CONFIG="$HOME/.ssh/config"
SSH_ALIAS="$INSTANCE_NAME"
# Update existing entry if present, otherwise append
if grep -q "^Host $SSH_ALIAS" "$SSH_CONFIG" 2>/dev/null; then
    python3 - "$SSH_CONFIG" "$SSH_ALIAS" "$STATIC_IP" "$PEM_PATH" <<'PYEOF'
import sys, re
config_path = sys.argv[1]
alias = sys.argv[2]
new_ip = sys.argv[3]
pem_path = sys.argv[4]

with open(config_path, 'r') as f:
    content = f.read()

# Remove existing block for this alias
content = re.sub(r'Host ' + re.escape(alias) + r'\n(?:[ \t]+\S[^\n]*\n)*', '', content)
content = content.rstrip('\n') + '\n'

# Add updated block
new_block = f"\nHost {alias}\n    HostName {new_ip}\n    User ubuntu\n    IdentityFile {pem_path}\n    StrictHostKeyChecking no\n    ServerAliveInterval 60\n"
content += new_block

with open(config_path, 'w') as f:
    f.write(content)
print(f"  OK: Updated SSH config entry '{alias}' (IP: {new_ip})")
PYEOF
else
    cat >> "$SSH_CONFIG" <<SSHEOF

Host $SSH_ALIAS
    HostName $STATIC_IP
    User ubuntu
    IdentityFile $PEM_PATH
    StrictHostKeyChecking no
    ServerAliveInterval 60
SSHEOF
    echo "  OK: SSH config entry '$SSH_ALIAS' added"
fi

# --- Wait for SSH to be available ---
echo "--- Waiting for SSH to become available..."
SSH_WAIT=0
SSH_MAX=12  # 2 minutes
while true; do
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$PEM_PATH" ubuntu@"$STATIC_IP" "echo OK" &>/dev/null 2>&1; then
        echo "  OK: SSH is up"
        break
    fi
    SSH_WAIT=$((SSH_WAIT + 1))
    if [ $SSH_WAIT -ge $SSH_MAX ]; then
        echo "  WARNING: SSH not responding after 2 minutes — instance may still be booting"
        echo "  Try: ssh healthos"
        break
    fi
    echo "  SSH not ready yet — waiting 10s..."
    sleep 10
done

echo ""
echo "=== AWS Infrastructure Complete ==="
echo ""
echo "STATIC_IP=$STATIC_IP"
echo "PEM_PATH=$PEM_PATH"
echo "SSH_HOST=$INSTANCE_NAME"
echo "INSTANCE_NAME=$INSTANCE_NAME"
