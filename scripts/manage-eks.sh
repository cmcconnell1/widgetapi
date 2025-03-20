#!/bin/bash
set -e

ENV=$1
AWS_REGION=${AWS_REGION:-"us-west-2"}
POC=true  # Restrict to dev environment during POC

if [[ -z "$ENV" ]]; then
  echo "Usage: $0 <environment>"
  exit 1
fi

# Restrict to dev during POC phase
if [[ "$POC" == "true" && "$ENV" != "dev" ]]; then
  echo "❌ ERROR: POC mode is enabled. Only 'dev' environment is allowed."
  exit 1
fi

echo "🚀 Managing EKS Cluster for Environment: $ENV"

# Load AWS Credentials
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null)}"
AWS_ROLE_TO_ASSUME="${AWS_ROLE_TO_ASSUME:-}"

if [[ -z "$AWS_ACCOUNT_ID" ]]; then
  echo "❌ ERROR: AWS credentials not found. Ensure AWS CLI is configured or GitHub Secrets are set."
  exit 1
fi

echo "🔹 AWS Account ID: $AWS_ACCOUNT_ID"

# Assume IAM Role if provided
if [[ -n "$AWS_ROLE_TO_ASSUME" && -z "$GITHUB_ACTIONS" ]]; then
  echo "🔹 Assuming AWS IAM Role: $AWS_ROLE_TO_ASSUME..."
  TEMP_ROLE=$(aws sts assume-role --role-arn "arn:aws:iam::$AWS_ACCOUNT_ID:role/$AWS_ROLE_TO_ASSUME" --role-session-name EKSSetup 2>/dev/null)
  if [[ -z "$TEMP_ROLE" ]]; then
    echo "❌ ERROR: Failed to assume role $AWS_ROLE_TO_ASSUME"
    exit 1
  fi
  export AWS_ACCESS_KEY_ID=$(echo "$TEMP_ROLE" | jq -r '.Credentials.AccessKeyId')
  export AWS_SECRET_ACCESS_KEY=$(echo "$TEMP_ROLE" | jq -r '.Credentials.SecretAccessKey')
  export AWS_SESSION_TOKEN=$(echo "$TEMP_ROLE" | jq -r '.Credentials.SessionToken')
  echo "✅ AWS Role Assumed Successfully!"
fi

# Define cluster name and Kubernetes version
CLUSTER_NAME="widgetapi-$ENV"
K8S_VERSION="1.30"

# Set node scaling values
case "$ENV" in
  dev) NODE_MIN=2; NODE_MAX=5; NODE_DESIRED=2 ;;
  stage) NODE_MIN=2; NODE_MAX=5; NODE_DESIRED=3 ;;
  prod) NODE_MIN=3; NODE_MAX=6; NODE_DESIRED=4 ;;
  *) echo "❌ ERROR: Unsupported environment: $ENV"; exit 1 ;;
esac

echo "🔹 Node Scaling Settings: Min=$NODE_MIN, Max=$NODE_MAX, Desired=$NODE_DESIRED"

### **1️⃣ Ensure IAM Role Setup (Fix ACM Permissions)**
echo "🔹 Ensuring IAM Role for AWS Load Balancer Controller..."
bash scripts/setup-iam-role.sh

### **2️⃣ Ensure EKS Cluster Exists**
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

### **3️⃣ Ensure AWS EBS CSI Driver is Installed**
echo "🚀 Ensuring AWS EBS CSI Driver is installed..."
if ! kubectl get daemonset -n kube-system | grep -q ebs; then
  echo "🔹 Installing AWS EBS CSI Driver..."
  eksctl create addon --name aws-ebs-csi-driver --cluster "$CLUSTER_NAME" --region "$AWS_REGION" --force
else
  echo "✅ AWS EBS CSI Driver is already installed."
fi

### **4️⃣ Ensure AWS Load Balancer Controller is Installed**
echo "🚀 Installing AWS Load Balancer Controller..."
helm repo add eks https://aws.github.io/eks-charts || true
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

echo "✅ AWS Load Balancer Controller installed successfully!"

# Restart the controller to apply IAM changes
echo "🔄 Restarting AWS Load Balancer Controller..."
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system

### **5️⃣ Ensure Cluster Autoscaler is Installed**
echo "🚀 Installing Cluster Autoscaler..."
helm repo add autoscaler https://kubernetes.github.io/autoscaler || true
helm repo update

helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName="$CLUSTER_NAME" \
  --set awsRegion="$AWS_REGION"

echo "✅ Cluster Autoscaler installed successfully!"

### **6️⃣ Ensure Cert-Manager is Installed**
echo "🚀 Installing Cert-Manager..."
helm repo add jetstack https://charts.jetstack.io || true
helm repo update

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true

echo "✅ Cert-Manager installed successfully!"

# Ensure Cert-Manager CRDs are applied
if ! kubectl get crds | grep -q cert-manager; then
  echo "⚠ Cert-Manager CRDs not found. Re-applying..."
  kubectl apply -f https://github.com/jetstack/cert-manager/releases/latest/download/cert-manager.crds.yaml
fi

# Wait for Cert-Manager to be ready
echo "⌛ Waiting for Cert-Manager to be ready..."
kubectl rollout status deployment cert-manager -n cert-manager --timeout=120s
kubectl rollout status deployment cert-manager-webhook -n cert-manager --timeout=120s
kubectl rollout status deployment cert-manager-cainjector -n cert-manager --timeout=120s

### **7️⃣ Ensure ClusterIssuer is Created (Fix Parsing Errors)**
echo "🚀 Configuring ClusterIssuer for Cert-Manager..."
kubectl delete clusterissuer selfsigned-cluster-issuer --ignore-not-found
kubectl apply -f chart/templates/cert-issuer.yaml || {
  echo "⚠ Failed to apply ClusterIssuer. Retrying in 10 seconds..."
  sleep 10
  kubectl apply -f chart/templates/cert-issuer.yaml
}

### **8️⃣ Ensure Ingress is Properly Configured**
echo "🚀 Reapplying Ingress to trigger ALB creation..."
kubectl delete ingress widgetapi -n widgetapi-$ENV || true
helm upgrade --install widgetapi ./chart -n widgetapi-$ENV --values ./chart/$ENV-values.yaml --debug --wait

# Verify ALB creation
echo "🔍 Checking AWS Load Balancer status..."
kubectl get ingress -n widgetapi-$ENV

echo "✅ EKS Cluster setup for $ENV is complete!"
