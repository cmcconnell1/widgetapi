#!/bin/bash
set -e

ROLE_NAME="GitHubActionsRole"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
AWS_REGION="us-west-2"
GITHUB_REPO="cmcconnell1/widgetapi"

echo "AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID"
echo "AWS_REGION=$AWS_REGION"
echo "GITHUB_REPO=$GITHUB_REPO"
echo "Creating IAM role: $ROLE_NAME..."

# Paths for policy templates and generated policies
IAM_POLICY_TEMPLATE="iam/GitHubActionsPolicy.json.template"
IAM_POLICY="secrets/GitHubActionsPolicy.json"
TRUST_POLICY_TEMPLATE="iam/trust-policy.json.template"
TRUST_POLICY="secrets/trust-policy.json"

# Ensure secrets directory exists
mkdir -p secrets

# Replace placeholders in policy files
echo "🔹 Generating IAM policy files..."
sed -e "s/YOUR_AWS_ACCOUNT_ID/$AWS_ACCOUNT_ID/g" "$IAM_POLICY_TEMPLATE" > "$IAM_POLICY"
sed -e "s/YOUR_AWS_ACCOUNT_ID/$AWS_ACCOUNT_ID/g" \
    -e "s/YOUR_GITHUB_REPO/$GITHUB_REPO/g" \
    "$TRUST_POLICY_TEMPLATE" > "$TRUST_POLICY"

echo "✅ Generated IAM policy files:"
cat "$IAM_POLICY"
cat "$TRUST_POLICY"

# Check if IAM role already exists
EXISTING_ROLE=$(aws iam get-role --role-name $ROLE_NAME 2>/dev/null || echo "MISSING")
if [[ "$EXISTING_ROLE" == "MISSING" ]]; then
    echo "🔹 Creating IAM Role: $ROLE_NAME..."
    aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file://"$TRUST_POLICY" || exit 1
    echo "✅ Created IAM Role: $ROLE_NAME"
else
    echo "ℹ IAM Role already exists. Skipping creation."
fi

# Attach AWS managed policies
echo "🔹 Attaching AWS managed policies..."
POLICIES=(
    "AmazonS3FullAccess"
    "AmazonEKSClusterPolicy"
    "AWSCertificateManagerFullAccess"
    "AmazonEKSWorkerNodePolicy"
    "AmazonEKSVPCResourceController"
)

for POLICY in "${POLICIES[@]}"; do
    aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn "arn:aws:iam::aws:policy/$POLICY" || exit 1
    echo "✅ Attached policy: $POLICY"
done

# Apply custom IAM policy
echo "🔹 Applying custom IAM policy..."
aws iam put-role-policy --role-name $ROLE_NAME --policy-name GitHubActionsCustomPolicy --policy-document file://"$IAM_POLICY" || exit 1
echo "✅ IAM Role setup complete."
