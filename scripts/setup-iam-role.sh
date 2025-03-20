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

# ✅ Fix for `sed` error: Ensure proper variable expansion
echo "🔹 Generating IAM policy files..."
sed -e "s|AWS_ACCOUNT_ID|$AWS_ACCOUNT_ID|g" "$IAM_POLICY_TEMPLATE" > "$IAM_POLICY"
sed -e "s|AWS_ACCOUNT_ID|$AWS_ACCOUNT_ID|g" \
    -e "s|YOUR_GITHUB_REPO|$GITHUB_REPO|g" \
    "$TRUST_POLICY_TEMPLATE" > "$TRUST_POLICY"

echo "✅ Generated IAM policy files."

# **Validate IAM Policy JSON before applying**
echo "🔍 Validating IAM policy JSON..."
jq empty "$IAM_POLICY" || { echo "❌ ERROR: IAM policy JSON is invalid!"; cat "$IAM_POLICY"; exit 1; }

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
    if aws iam list-attached-role-policies --role-name "$ROLE_NAME" | grep -q "$POLICY"; then
        echo "✅ Policy already attached: $POLICY"
    else
        aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "arn:aws:iam::aws:policy/$POLICY"
        echo "✅ Attached policy: $POLICY"
    fi
done

# **Fix for `MalformedPolicyDocument` Error**
echo "🔹 Removing old custom IAM policy (if exists)..."
aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name GitHubActionsCustomPolicy 2>/dev/null || true

echo "🔹 Applying new custom IAM policy..."
aws iam put-role-policy --role-name $ROLE_NAME --policy-name GitHubActionsCustomPolicy --policy-document file://"$IAM_POLICY" || {
    echo "❌ ERROR: Applying IAM policy failed. Inspect the policy:"
    cat "$IAM_POLICY"
    exit 1
}
echo "✅ IAM Role setup complete."

# =====================================================================================
# ✅ **Fix EKS Node IAM Role Detection**
# =====================================================================================

echo "🔹 Retrieving EKS Node IAM Role dynamically..."
EKS_CLUSTER_NAME="widgetapi-dev"
EKS_NODE_ROLE=$(aws iam list-roles --query "Roles[?contains(RoleName, 'eksctl-${EKS_CLUSTER_NAME}-nodegroup')].RoleName" --output text)

if [[ -z "$EKS_NODE_ROLE" ]]; then
    echo "❌ ERROR: Could not determine EKS Node IAM Role for $EKS_CLUSTER_NAME."
    echo "ℹ Available IAM roles:"
    aws iam list-roles --query "Roles[].RoleName" --output text
    exit 1
fi

echo "✅ Found EKS Node IAM Role: $EKS_NODE_ROLE"

# Check if Autoscaler Policy already exists
EXISTING_POLICY=$(aws iam list-policies --query "Policies[?PolicyName=='AmazonEKSClusterAutoscalerPolicy'].Arn" --output text)

if [[ -z "$EXISTING_POLICY" ]]; then
    echo "🚀 Creating IAM Policy: AmazonEKSClusterAutoscalerPolicy..."
    POLICY_ARN=$(aws iam create-policy \
        --policy-name AmazonEKSClusterAutoscalerPolicy \
        --description "IAM policy for EKS Cluster Autoscaler" \
        --policy-document '{
          "Version": "2012-10-17",
          "Statement": [
            {
              "Effect": "Allow",
              "Action": [
                "autoscaling:DescribeAutoScalingGroups",
                "autoscaling:DescribeAutoScalingInstances",
                "autoscaling:DescribeLaunchConfigurations",
                "autoscaling:DescribeTags",
                "ec2:DescribeInstanceTypes",
                "ec2:DescribeLaunchTemplateVersions"
              ],
              "Resource": "*"
            },
            {
              "Effect": "Allow",
              "Action": [
                "autoscaling:SetDesiredCapacity",
                "autoscaling:TerminateInstanceInAutoScalingGroup"
              ],
              "Resource": "*",
              "Condition": {
                "StringEquals": {
                  "autoscaling:ResourceTag/kubernetes.io/cluster/widgetapi-dev": "owned"
                }
              }
            }
          ]
        }' --query "Policy.Arn" --output text)

    sleep 5
    echo "✅ IAM Policy created: $POLICY_ARN"
else
    POLICY_ARN="$EXISTING_POLICY"
    echo "✅ IAM Policy AmazonEKSClusterAutoscalerPolicy already exists: $POLICY_ARN"
fi

# Attach the policy to the EKS Node IAM Role
echo "🔹 Attaching AmazonEKSClusterAutoscalerPolicy to $EKS_NODE_ROLE..."
aws iam attach-role-policy \
    --role-name "$EKS_NODE_ROLE" \
    --policy-arn "$POLICY_ARN"

echo "✅ AmazonEKSClusterAutoscalerPolicy attached successfully!"

# =====================================================================================
# ✅ **Final Validation**
# =====================================================================================
echo "🔎 Validating IAM Role and Policies..."

aws iam get-role --role-name "$ROLE_NAME"
aws iam list-attached-role-policies --role-name "$ROLE_NAME"
aws iam list-attached-role-policies --role-name "$EKS_NODE_ROLE"

echo "✅ IAM Role and Policies setup complete!"
