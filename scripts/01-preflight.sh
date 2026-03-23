#!/bin/bash
# 01-preflight.sh — Mac preflight checks before HealthOS install
# Usage: bash 01-preflight.sh
# Checks: AWS CLI installed, credentials configured, credentials valid

set -e

echo "=== HealthOS Preflight Check ==="
echo ""

PASS=true

# --- Check AWS CLI ---
echo "Checking AWS CLI..."
if command -v aws &>/dev/null; then
    AWS_VERSION=$(aws --version 2>&1 | head -1)
    echo "  OK: $AWS_VERSION"
else
    echo "  MISSING: AWS CLI not installed"
    echo ""
    echo "  Installing AWS CLI..."
    curl -s -o /tmp/AWSCLIV2.pkg "https://awscli.amazonaws.com/AWSCLIV2.pkg"
    echo ""
    echo "  *** ACTION REQUIRED ***"
    echo "  Run this command in your terminal (you'll be asked for your Mac password):"
    echo ""
    echo "      sudo installer -pkg /tmp/AWSCLIV2.pkg -target /"
    echo ""
    echo "  Then re-run this preflight script."
    exit 1
fi

# --- Check AWS credentials file ---
echo "Checking AWS credentials..."
if [ -f "$HOME/.aws/credentials" ] || [ -f "$HOME/.aws/config" ]; then
    echo "  OK: AWS config found at ~/.aws/"
else
    echo "  MISSING: AWS not configured"
    echo ""
    echo "  You need to run: aws configure"
    echo "  (You'll need your AWS Access Key ID and Secret Access Key)"
    echo ""
    echo "  After running aws configure, re-run this preflight script."
    PASS=false
fi

# --- Verify credentials work ---
if [ "$PASS" = true ]; then
    echo "Verifying AWS credentials..."
    if IDENTITY=$(aws sts get-caller-identity --output json 2>&1); then
        ACCOUNT=$(echo "$IDENTITY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['Account'])")
        ARN=$(echo "$IDENTITY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['Arn'])")
        echo "  OK: Connected as $ARN"
        echo "  Account ID: $ACCOUNT"
        echo ""
        echo "PREFLIGHT_OK=true"
        echo "AWS_ACCOUNT_ID=$ACCOUNT"
    else
        echo "  FAILED: AWS credentials not working"
        echo ""
        echo "  Error: $IDENTITY"
        echo ""
        echo "  Run: aws configure"
        echo "  And enter valid Access Key ID + Secret Access Key"
        exit 1
    fi
fi
