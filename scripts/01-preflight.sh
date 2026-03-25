#!/bin/bash
# 01-preflight.sh — Mac preflight checks before HealthOS install
# Usage: bash 01-preflight.sh
# Checks: AWS CLI installed, credentials configured, credentials valid
#
# Exit codes:
#   0 + PREFLIGHT_OK=true     — ready to proceed
#   0 + NEED_CREDENTIALS=true — CLI installed but no credentials yet
#   0 + CLI_DOWNLOADED=true   — pkg downloaded, run: sudo installer -pkg /tmp/AWSCLIV2.pkg -target /
#   1                         — unexpected error

set -e

echo "=== HealthOS Preflight Check ==="
echo ""

# --- Check AWS CLI ---
echo "Checking AWS CLI..."
if command -v aws &>/dev/null; then
    AWS_VERSION=$(aws --version 2>&1 | head -1)
    echo "  OK: $AWS_VERSION"
else
    echo "  MISSING: AWS CLI not installed — downloading..."
    curl -s -o /tmp/AWSCLIV2.pkg "https://awscli.amazonaws.com/AWSCLIV2.pkg"
    echo "  OK: Package downloaded to /tmp/AWSCLIV2.pkg"
    echo ""
    echo "CLI_DOWNLOADED=true"
    exit 0
fi

# --- Check AWS credentials ---
echo "Checking AWS credentials..."
if aws sts get-caller-identity &>/dev/null 2>&1; then
    IDENTITY=$(aws sts get-caller-identity --output json 2>&1)
    ACCOUNT=$(echo "$IDENTITY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['Account'])")
    ARN=$(echo "$IDENTITY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['Arn'])")
    echo "  OK: Connected as $ARN"
    echo "  Account ID: $ACCOUNT"
    echo ""
    echo "PREFLIGHT_OK=true"
    echo "AWS_ACCOUNT_ID=$ACCOUNT"
else
    echo "  MISSING: No valid AWS credentials found"
    echo ""
    echo "NEED_CREDENTIALS=true"
fi
