#!/bin/bash
set -e

ENV=$1
AWS_REGION="${AWS_REGION:-us-west-2}"

if [[ -z "$ENV" ]]; then
  echo "Usage: $0 <environment>"
  exit 1
fi

EKS_CLUSTER_NAME="widgetapi-$ENV"
NODEGROUP_NAME="$ENV-nodes"

echo "🔍 Retrieving EKS Node IAM Role from nodegroup..."
NODEGROUP_ROLE_ARN=$(aws eks describe-nodegroup \
  --cluster-name "$EKS_CLUSTER_NAME" \
  --nodegroup-name "$NODEGROUP_NAME" \
  --query "nodegroup.nodeRole" \
  --output text 2>/dev/null || true)

if [[ -z "$NODEGROUP_ROLE_ARN" || "$NODEGROUP_ROLE_ARN" == "None" ]]; then
  echo "❌ ERROR: Could not retrieve IAM role ARN from nodegroup '$NODEGROUP_NAME'. Ensure EKS cluster exists."
  exit 1
fi

EKS_NODE_ROLE=$(basename "$NODEGROUP_ROLE_ARN")
echo "✅ Found EKS Node IAM Role: $EKS_NODE_ROLE"

# =====================================================================================
# Attach Cluster Autoscaler IAM Policy
# =====================================================================================
AUTOSCALER_POLICY_NAME="AmazonEKSClusterAutoscalerPolicy"
AUTOSCALER_TAG="kubernetes.io/cluster/${EKS_CLUSTER_NAME}"
echo "🔍 Checking for existing Cluster Autoscaler policy..."
EXISTING_POLICY_ARN=$(aws iam list-policies \
  --query "Policies[?PolicyName=='$AUTOSCALER_POLICY_NAME'].Arn" \
  --output text)

if [[ -z "$EXISTING_POLICY_ARN" ]]; then
  echo "🚀 Creating Cluster Autoscaler IAM Policy..."
  POLICY_ARN=$(aws iam create-policy \
    --policy-name "$AUTOSCALER_POLICY_NAME" \
    --description "IAM policy for EKS Cluster Autoscaler" \
    --policy-document "{
      \"Version\": \"2012-10-17\",
      \"Statement\": [
        {
          \"Effect\": \"Allow\",
          \"Action\": [
            \"autoscaling:DescribeAutoScalingGroups\",
            \"autoscaling:DescribeAutoScalingInstances\",
            \"autoscaling:DescribeLaunchConfigurations\",
            \"autoscaling:DescribeTags\",
            \"ec2:DescribeInstanceTypes\",
            \"ec2:DescribeLaunchTemplateVersions\"
          ],
          \"Resource\": \"*\"
        },
        {
          \"Effect\": \"Allow\",
          \"Action\": [
            \"autoscaling:SetDesiredCapacity\",
            \"autoscaling:TerminateInstanceInAutoScalingGroup\"
          ],
          \"Resource\": \"*\",
          \"Condition\": {
            \"StringEquals\": {
              \"autoscaling:ResourceTag/$AUTOSCALER_TAG\": \"owned\"
            }
          }
        }
      ]
    }" --query "Policy.Arn" --output text)
  echo "✅ Created Cluster Autoscaler policy: $POLICY_ARN"
else
  POLICY_ARN="$EXISTING_POLICY_ARN"
  echo "✅ Existing policy found: $POLICY_ARN"
fi

echo "🚀 Attaching Cluster Autoscaler policy to $EKS_NODE_ROLE..."
aws iam attach-role-policy \
  --role-name "$EKS_NODE_ROLE" \
  --policy-arn "$POLICY_ARN"
echo "✅ Cluster Autoscaler policy attached."

# =====================================================================================
# Attach EBS CSI Driver Permissions
# =====================================================================================
echo "🚀 Attaching EBS CSI Driver permissions to $EKS_NODE_ROLE..."
aws iam put-role-policy \
  --role-name "$EKS_NODE_ROLE" \
  --policy-name "EBS-CSI-Driver-Permissions" \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "ec2:AttachVolume",
          "ec2:CreateSnapshot",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:DeleteSnapshot",
          "ec2:DeleteTags",
          "ec2:DeleteVolume",
          "ec2:DescribeInstances",
          "ec2:DescribeSnapshots",
          "ec2:DescribeTags",
          "ec2:DescribeVolumes",
          "ec2:DetachVolume"
        ],
        "Resource": "*"
      }
    ]
  }'
echo "✅ EBS CSI Driver permissions attached."

# =====================================================================================
# Final Validation
# =====================================================================================
echo "🔍 Validating attached policies for $EKS_NODE_ROLE..."
aws iam list-attached-role-policies --role-name "$EKS_NODE_ROLE"
echo "✅ Post-cluster IAM setup complete for environment: $ENV"
