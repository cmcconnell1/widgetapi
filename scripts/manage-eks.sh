#!/bin/bash
set -e

ENV=$1
AWS_REGION="${AWS_REGION:-us-west-2}"
POC=true

if [[ -z "$ENV" ]]; then
  echo "Usage: $0 <environment>"
  exit 1
fi

if [[ "$POC" == "true" && "$ENV" != "dev" ]]; then
  echo "❌ ERROR: POC mode is enabled. Only 'dev' environment is allowed."
  exit 1
fi

echo "🚀 Managing EKS Cluster for Environment: $ENV"

AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null)}"
AWS_ROLE_TO_ASSUME="${AWS_ROLE_TO_ASSUME:-}"

if [[ -z "$AWS_ACCOUNT_ID" ]]; then
  echo "❌ ERROR: AWS credentials not found."
  exit 1
fi

echo "🔹 AWS Account ID: $AWS_ACCOUNT_ID"

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

CLUSTER_NAME="widgetapi-$ENV"
K8S_VERSION="1.30"
NODEGROUP_NAME="$ENV-nodes"

case "$ENV" in
  dev) NODE_MIN=2; NODE_MAX=5; NODE_DESIRED=2 ;;
  stage) NODE_MIN=2; NODE_MAX=5; NODE_DESIRED=3 ;;
  prod) NODE_MIN=3; NODE_MAX=6; NODE_DESIRED=4 ;;
  *) echo "❌ ERROR: Unsupported environment: $ENV"; exit 1 ;;
esac

echo "🔹 Node Scaling Settings: Min=$NODE_MIN, Max=$NODE_MAX, Desired=$NODE_DESIRED"

echo "🔹 Running setup-iam-pre-eks.sh..."
bash scripts/setup-iam-pre-eks.sh "$ENV"

if eksctl get cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" > /dev/null 2>&1; then
  echo "✅ EKS Cluster '$CLUSTER_NAME' already exists."
else
  echo "🌐 Creating EKS Cluster '$CLUSTER_NAME'..."
  eksctl create cluster --name "$CLUSTER_NAME" \
    --version "$K8S_VERSION" \
    --region "$AWS_REGION" \
    --nodegroup-name "$NODEGROUP_NAME" \
    --node-type t3.medium \
    --nodes "$NODE_DESIRED" \
    --nodes-min "$NODE_MIN" \
    --nodes-max "$NODE_MAX" \
    --managed
  echo "✅ EKS Cluster '$CLUSTER_NAME' created successfully!"
fi

echo "🔹 Running setup-iam-post-eks.sh..."
bash scripts/setup-iam-post-eks.sh "$ENV"

echo "🚀 Ensuring AWS EBS CSI Driver is installed..."
if ! kubectl get daemonset -n kube-system | grep -q ebs; then
  eksctl create addon --name aws-ebs-csi-driver --cluster "$CLUSTER_NAME" --region "$AWS_REGION" --force
else
  echo "✅ AWS EBS CSI Driver is already installed."
fi

echo "🚀 Installing Cluster Autoscaler..."
helm repo add autoscaler https://kubernetes.github.io/autoscaler || true
helm repo update

helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName="$CLUSTER_NAME" \
  --set awsRegion="$AWS_REGION"

echo "✅ Cluster Autoscaler installed!"

echo "🚀 Installing Cert-Manager..."
helm repo add jetstack https://charts.jetstack.io || true
helm repo update

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true \
  --wait --timeout 10m

if ! kubectl get crds | grep -q cert-manager; then
  echo "⚠ Re-applying Cert-Manager CRDs..."
  kubectl apply -f https://github.com/jetstack/cert-manager/releases/latest/download/cert-manager.crds.yaml
fi

echo "⌛ Waiting for Cert-Manager to be ready..."
kubectl rollout status deployment cert-manager -n cert-manager --timeout=180s
kubectl rollout status deployment cert-manager-webhook -n cert-manager --timeout=180s
kubectl rollout status deployment cert-manager-cainjector -n cert-manager --timeout=180s

echo "🔍 Checking for existing ClusterIssuer..."
if kubectl get clusterissuer selfsigned-cluster-issuer > /dev/null 2>&1; then
  echo "⚠️ ClusterIssuer 'selfsigned-cluster-issuer' already exists. Deleting..."
  kubectl delete clusterissuer selfsigned-cluster-issuer || true
fi

echo "🚀 Applying ClusterIssuer..."
kubectl apply -f chart/cluster-issuer.yaml || {
  echo "⚠ Retry applying ClusterIssuer..."
  sleep 10
  kubectl apply -f chart/cluster-issuer.yaml
}

echo "🚀 Installing ingress-nginx Ingress Controller..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx || true
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --wait --timeout 10m

echo "⌛ Waiting for ingress-nginx deployments to roll out..."
kubectl rollout status deployment ingress-nginx-controller -n ingress-nginx --timeout=180s || true
kubectl rollout status deployment ingress-nginx-admission -n ingress-nginx --timeout=180s || true

echo "✅ ingress-nginx Controller installed."

echo "🚀 Re-deploying WidgetAPI and Ingress..."
kubectl create namespace widgetapi-"$ENV" || true
kubectl delete ingress widgetapi -n widgetapi-"$ENV" || true

helm upgrade --install widgetapi ./chart \
  -n widgetapi-"$ENV" \
  --values ./chart/"$ENV"-values.yaml \
  --wait --timeout 10m

echo "🔍 Checking NGINX Ingress status..."
kubectl get ingress -n widgetapi-"$ENV"

echo "✅ EKS Cluster and services setup complete for environment: $ENV"
