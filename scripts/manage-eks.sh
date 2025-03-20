#!/bin/bash
set -e

ENV=$1
AWS_REGION=${AWS_REGION:-"us-west-2"}
POC=true  # Restrict to `dev` environment during POC

if [[ -z "$ENV" ]]; then
  echo "Usage: $0 <environment>"
  exit 1
fi

# Restrict to `dev` during POC phase
if [[ "$POC" == "true" && "$ENV" != "dev" ]]; then
  echo "❌ ERROR: POC mode is enabled. Only 'dev' environment is allowed."
  exit 1
fi

echo "🚀 Managing EKS Cluster for Environment: $ENV"

# Ensure AWS credentials are loaded from GitHub Secrets
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
AWS_ROLE_TO_ASSUME="${AWS_ROLE_TO_ASSUME}"

if [[ -z "$AWS_ACCOUNT_ID" || -z "$AWS_ROLE_TO_ASSUME" ]]; then
  echo "❌ ERROR: AWS credentials not found. Ensure GitHub Environment Secrets are set."
  exit 1
fi

echo "🔹 AWS Account ID: $AWS_ACCOUNT_ID"
echo "🔹 AWS Role: $AWS_ROLE_TO_ASSUME"

# Define cluster name
CLUSTER_NAME="widgetapi-$ENV"
K8S_VERSION="1.30"  # Explicitly setting latest supported version

# Set node scaling values based on environment
case "$ENV" in
  dev)
    NODE_MIN=2
    NODE_MAX=2
    NODE_DESIRED=2
    ;;
  stage)
    NODE_MIN=2
    NODE_MAX=3
    NODE_DESIRED=2
    ;;
  prod)
    NODE_MIN=3
    NODE_MAX=6
    NODE_DESIRED=4
    ;;
  *)
    echo "❌ ERROR: Unsupported environment: $ENV"
    exit 1
    ;;
esac

echo "🔹 Node Scaling Settings: Min=$NODE_MIN, Max=$NODE_MAX, Desired=$NODE_DESIRED"

### 1️⃣ **Ensure IAM Role for GitHub Actions Exists**
echo "🔹 Checking IAM Role for GitHub Actions..."
if ! aws iam get-role --role-name GitHubActionsRole > /dev/null 2>&1; then
  echo "🛠 Creating IAM Role and Permissions..."
  bash scripts/setup-iam-role.sh
  echo "✅ IAM Role Created!"
else
  echo "✅ IAM Role 'GitHubActionsRole' already exists."
fi

### 2️⃣ **Ensure EKS Cluster Exists**
if ! eksctl get cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" > /dev/null 2>&1; then
  echo "🌐 Creating EKS Cluster: $CLUSTER_NAME..."
  eksctl create cluster --name "$CLUSTER_NAME" \
    --version "$K8S_VERSION" \
    --region "$AWS_REGION" \
    --nodegroup-name "$ENV-nodes" \
    --node-type t3.medium \
    --nodes "$NODE_DESIRED" \
    --nodes-min "$NODE_MIN" \
    --nodes-max "$NODE_MAX" \
    --managed
  echo "✅ EKS Cluster '$CLUSTER_NAME' created successfully!"
else
  echo "✅ EKS Cluster '$CLUSTER_NAME' already exists."
fi

### 3️⃣ **Associate IAM OIDC Provider**
echo "🔹 Associating IAM OIDC Provider..."
eksctl utils associate-iam-oidc-provider --cluster "$CLUSTER_NAME" --approve

### 4️⃣ **Install AWS Load Balancer Controller**
echo "🚀 Installing AWS Load Balancer Controller..."
helm repo add eks https://aws.github.io/eks-charts || true
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller

echo "✅ AWS Load Balancer Controller installed successfully!"

### 5️⃣ **Install Cluster Autoscaler**
echo "🚀 Installing Cluster Autoscaler..."
helm repo add autoscaler https://kubernetes.github.io/autoscaler || true
helm repo update

helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName="$CLUSTER_NAME" \
  --set awsRegion="$AWS_REGION"

echo "✅ Cluster Autoscaler installed successfully!"

### 6️⃣ **Install Cert-Manager (Fix for Missing CRDs)**
echo "🚀 Installing Cert-Manager..."
helm repo add jetstack https://charts.jetstack.io || true
helm repo update

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true

# Ensure Cert-Manager CRDs are applied
echo "🔍 Checking for Cert-Manager CRDs..."
kubectl get crds | grep cert-manager || {
  echo "⚠ Cert-Manager CRDs not found. Re-applying..."
  kubectl apply -f https://github.com/jetstack/cert-manager/releases/latest/download/cert-manager.crds.yaml
}

# Wait for Cert-Manager pods to be ready
echo "⌛ Waiting for Cert-Manager to be ready..."
kubectl rollout status deployment cert-manager -n cert-manager --timeout=120s
kubectl rollout status deployment cert-manager-webhook -n cert-manager --timeout=120s
kubectl rollout status deployment cert-manager-cainjector -n cert-manager --timeout=120s

echo "✅ Cert-Manager installed successfully!"

### 7️⃣ **Ensure ClusterIssuer is Created**
echo "🚀 Configuring ClusterIssuer for Cert-Manager..."
kubectl apply -f chart/templates/cert-issuer.yaml || {
  echo "⚠ Failed to apply ClusterIssuer. Retrying in 10 seconds..."
  sleep 10
  kubectl apply -f chart/templates/cert-issuer.yaml
}

echo "✅ EKS Cluster setup for $ENV is complete!"
