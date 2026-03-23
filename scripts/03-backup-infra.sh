#!/bin/bash
# 03-backup-infra.sh — Create S3 bucket + IAM backup user
# Usage: bash 03-backup-infra.sh <bucket-name> <iam-username>
# Example: bash 03-backup-infra.sh healthos-backup-123456789012 healthos-backup
#
# Outputs (printed to stdout):
#   AWS_BACKUP_KEY_ID=<id>
#   AWS_BACKUP_SECRET=<secret>
#   S3_BUCKET=<bucket-name>

set -e

BUCKET_NAME="${1:-healthos-backup}"
IAM_USER="${2:-healthos-backup}"

echo "=== HealthOS S3 + IAM Backup Setup ==="
echo "  Bucket:   s3://$BUCKET_NAME"
echo "  IAM user: $IAM_USER"
echo ""

# --- Create S3 bucket ---
echo "--- Creating S3 bucket..."
if aws s3 ls "s3://$BUCKET_NAME" &>/dev/null 2>&1; then
    echo "  SKIP: Bucket s3://$BUCKET_NAME already exists"
else
    aws s3 mb "s3://$BUCKET_NAME" --region us-east-1
    echo "  OK: Bucket created"

    # Block all public access
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
        2>/dev/null || true
    echo "  OK: Public access blocked"
fi

# --- Create IAM user ---
echo "--- Creating IAM backup user..."
if aws iam get-user --user-name "$IAM_USER" &>/dev/null 2>&1; then
    echo "  SKIP: IAM user '$IAM_USER' already exists"
else
    aws iam create-user --user-name "$IAM_USER"
    echo "  OK: IAM user created"
fi

# --- Attach S3 policy ---
echo "--- Attaching S3 policy..."
POLICY_ARN="arn:aws:iam::aws:policy/AmazonS3FullAccess"
ATTACHED=$(aws iam list-attached-user-policies --user-name "$IAM_USER" \
    --query "AttachedPolicies[?PolicyArn=='$POLICY_ARN'].PolicyArn" \
    --output text 2>/dev/null || echo "")
if [ -n "$ATTACHED" ]; then
    echo "  SKIP: S3 policy already attached"
else
    aws iam attach-user-policy --user-name "$IAM_USER" --policy-arn "$POLICY_ARN"
    echo "  OK: S3FullAccess policy attached"
fi

# --- Create access key ---
echo "--- Creating IAM access key..."
KEY_JSON=$(aws iam create-access-key --user-name "$IAM_USER" --output json)
AWS_BACKUP_KEY_ID=$(echo "$KEY_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['AccessKey']['AccessKeyId'])")
AWS_BACKUP_SECRET=$(echo "$KEY_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['AccessKey']['SecretAccessKey'])")
echo "  OK: Access key created"

echo ""
echo "=== S3 + IAM Backup Complete ==="
echo ""
echo "S3_BUCKET=$BUCKET_NAME"
echo "AWS_BACKUP_KEY_ID=$AWS_BACKUP_KEY_ID"
echo "AWS_BACKUP_SECRET=$AWS_BACKUP_SECRET"
