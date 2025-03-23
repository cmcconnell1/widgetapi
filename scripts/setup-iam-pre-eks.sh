#!/bin/bash
set -e

ENV=$1
AWS_REGION="${AWS_REGION:-us-west-2}"
ROLE_NAME="GitHubActionsRole"
GITHUB_REPO="cmcconnell1/widgetapi"

if [[ -z "$ENV" ]]; then
  echo "Usage: $0 <environment>"
  exit 1
fi

echo "🔹 Setting up pre-EKS IAM Role and Policies for environment: $ENV"

mkdir -p secrets

# Templates
IAM_POLICY_TEMPLATE="iam/GitHubActionsPolicy.json.template"
IAM_POLICY="secrets/GitHubActionsPolicy.json"
TRUST_POLICY_TEMPLATE="iam/trust-policy.json.template"
TRUST_POLICY="secrets/trust-policy.json"

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Generate policy files
echo "🔹 Generating IAM policy files..."
sed -e "s|AWS_ACCOUNT_ID|$AWS_ACCOUNT_ID|g" "$IAM_POLICY_TEMPLATE" > "$IAM_POLICY"
sed -e "s|AWS_ACCOUNT_ID|$AWS_ACCOUNT_ID|g" \
    -e "s|GITHUB_REPO|$GITHUB_REPO|g" \
    "$TRUST_POLICY_TEMPLATE" > "$TRUST_POLICY"
echo "✅ Policy files created."

# Validate policy JSON
echo "🔍 Validating IAM policy JSON..."
jq empty "$IAM_POLICY" || { echo "❌ ERROR: Invalid IAM policy JSON."; cat "$IAM_POLICY"; exit 1; }

# Create role if missing
EXISTING_ROLE=$(aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null || echo "MISSING")
if [[ "$EXISTING_ROLE" == "MISSING" ]]; then
  echo "🔹 Creating IAM Role: $ROLE_NAME..."
  aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document file://"$TRUST_POLICY"
  echo "✅ Created IAM Role: $ROLE_NAME"
else
  echo "ℹ IAM Role already exists. Skipping creation."
fi

# Attach managed policies
echo "🔹 Attaching AWS managed policies..."
POLICIES=(
  "AmazonS3FullAccess"
  "AmazonEKSClusterPolicy"
  "AWSCertificateManagerFullAccess"
  "AmazonEKSWorkerNodePolicy"
  "AmazonEKSVPCResourceController"
)
for POLICY in "${POLICIES[@]}"; do
  if aws iam list-attached-role-policies --role-name "$ROLE_NAME" | grep -q "$POLICY"; then
    echo "✅ Policy already attached: $POLICY"
  else
    aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "arn:aws:iam::aws:policy/$POLICY"
    echo "✅ Attached policy: $POLICY"
  fi
done

# Apply inline custom policy
echo "🔹 Replacing custom inline policy..."
aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name GitHubActionsCustomPolicy 2>/dev/null || true
aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name GitHubActionsCustomPolicy \
  --policy-document file://"$IAM_POLICY"
echo "✅ Custom IAM policy applied to $ROLE_NAME"
