#!/bin/bash
set -e

ENV=$1
AWS_REGION="us-west-2"
POC=true  # Restrict to `dev` environment during POC

if [[ -z "$ENV" ]]; then
  echo "Usage: $0 <environment>"
  exit 1
fi

# Restrict to `dev` during POC phase
if [[ "$POC" == "true" && "$ENV" != "dev" ]]; then
  echo "❌ ERROR: POC mode is enabled. Only 'dev' environment can be deleted."
  exit 1
fi

echo "🚀 Deleting EKS Cluster for Environment: $ENV"

# Ensure `eksctl` is installed
if ! command -v eksctl &> /dev/null; then
  echo "❌ eksctl not found. Please install eksctl first."
  exit 1
fi

# Define cluster name
CLUSTER_NAME="widgetapi-$ENV"

# Check if cluster exists before deleting
if eksctl get cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" > /dev/null 2>&1; then
  echo "🔹 Cluster '$CLUSTER_NAME' found. Proceeding with deletion..."

  # Delete EKS Cluster
  eksctl delete cluster --name "$CLUSTER_NAME" --region "$AWS_REGION"

  echo "✅ Successfully deleted EKS cluster: $CLUSTER_NAME"

  # Optionally, cleanup orphaned IAM roles/policies if needed
  echo "🔹 Checking for orphaned IAM Roles..."
  if aws iam get-role --role-name "eksctl-$CLUSTER_NAME-cluster" > /dev/null 2>&1; then
    echo "🛠 Deleting IAM Role: eksctl-$CLUSTER_NAME-cluster"
    aws iam delete-role --role-name "eksctl-$CLUSTER_NAME-cluster"
  fi

  echo "✅ Cleanup completed."
else
  echo "⚠ No cluster found with name '$CLUSTER_NAME'. Skipping deletion."
fi

