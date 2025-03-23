#!/bin/bash
set -e

ENV=$1

if [[ -z "$ENV" ]]; then
  echo "Usage: $0 <environment>"
  exit 1
fi

echo "🚀 Deploying to environment: $ENV"

# Namespace & Ingress Mapping
case "$ENV" in
  local)
    NAMESPACE="widgetapi-local"
    INGRESS_CLASS="nginx"
    ;;
  dev)
    NAMESPACE="widgetapi-dev"
    INGRESS_CLASS="nginx"
    ;;
  stage)
    NAMESPACE="widgetapi-stage"
    INGRESS_CLASS="nginx"
    ;;
  prod)
    NAMESPACE="widgetapi-prod"
    INGRESS_CLASS="nginx"
    ;;
  *)
    echo "❌ ERROR: Unsupported environment: $ENV"
    exit 1
    ;;
esac

echo "🔹 Using Kubernetes namespace: $NAMESPACE"
echo "🔹 Ingress Class: $INGRESS_CLASS"

### 1️⃣ Ensure Cert-Manager is Installed
echo "🚀 Ensuring Cert-Manager is installed..."
if ! kubectl get namespace cert-manager >/dev/null 2>&1; then
  helm repo add jetstack https://charts.jetstack.io || true
  helm repo update
  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager --create-namespace \
    --set installCRDs=true
fi

echo "⌛ Waiting for Cert-Manager to be ready..."
kubectl rollout status deployment cert-manager -n cert-manager --timeout=120s
kubectl rollout status deployment cert-manager-webhook -n cert-manager --timeout=120s
kubectl rollout status deployment cert-manager-cainjector -n cert-manager --timeout=120s
echo "✅ Cert-Manager installed and running."

### 2️⃣ Ensure ClusterIssuer is Applied
echo "🚀 Configuring ClusterIssuer for Cert-Manager..."
echo "🔁 Deleting existing ClusterIssuer to prevent conflicts..."
kubectl delete clusterissuer selfsigned-cluster-issuer --ignore-not-found || true
kubectl apply -f chart/cluster-issuer.yaml || {
  echo "⚠ Failed to apply ClusterIssuer. Retrying in 10 seconds..."
  sleep 10
  kubectl apply -f chart/cluster-issuer.yaml
}
echo "✅ ClusterIssuer configured successfully."

### 3️⃣ Clean Up Existing Resources
echo "⚠️ Cleaning previous deployments in namespace: $NAMESPACE..."
helm uninstall widgetapi -n "$NAMESPACE" --no-hooks || true

# Delete stuck Ingress with finalizer removal if necessary
INGRESS_NAME="widgetapi"
if kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "🔁 Deleting Ingress: $INGRESS_NAME..."
  kubectl delete ingress "$INGRESS_NAME" -n "$NAMESPACE" --wait=false || true
  sleep 3
  FINALIZERS=$(kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE" -o json | jq -r '.metadata.finalizers[]?' || echo "")
  if [[ "$FINALIZERS" == *"kubernetes.io/ingress-finalizer"* ]]; then
    echo "⚠ Removing ingress finalizer..."
    kubectl patch ingress "$INGRESS_NAME" -n "$NAMESPACE" -p '{"metadata":{"finalizers":[]}}' --type=merge
  fi
fi

# Force delete all remaining resource types
for TYPE in all pvc secret configmap; do
  echo "🔁 Deleting all $TYPE resources..."
  kubectl delete $TYPE --all -n "$NAMESPACE" --force --grace-period=0 || true
done

### 4️⃣ Delete Namespace (Finalizer-Aware)
echo "🚨 Deleting namespace to ensure clean state..."
kubectl delete namespace "$NAMESPACE" --ignore-not-found --wait=false || true

echo "🔍 Checking if namespace deletion is stuck..."
for i in {1..12}; do
  if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "✅ Namespace $NAMESPACE fully deleted."
    break
  fi
  echo "⌛ Still waiting for namespace deletion... ($i/12)"
  FINALIZERS=$(kubectl get namespace "$NAMESPACE" -o json | jq '.spec.finalizers')
  if echo "$FINALIZERS" | grep -q "kubernetes"; then
    echo "⚠ Removing finalizers from namespace $NAMESPACE..."
    kubectl patch namespace "$NAMESPACE" -p '{"spec":{"finalizers":[]}}' --type=merge
  fi
  sleep 10
done

if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  echo "❌ Namespace $NAMESPACE failed to delete. Aborting."
  exit 1
fi

### 5️⃣ Recreate Namespace
echo "🚀 Recreating namespace: $NAMESPACE"
kubectl create namespace "$NAMESPACE"

### 6️⃣ Deploy Helm Chart
echo "🚀 Installing Helm release for WidgetAPI..."
helm upgrade --install widgetapi chart/ \
  --namespace "$NAMESPACE" --values chart/${ENV}-values.yaml \
  --set ingress.className="$INGRESS_CLASS" \
  --atomic --timeout 300s --wait

echo "✅ Deployment complete for environment: $ENV"

### 7️⃣ Run Helm Tests
echo "🔎 Running Helm tests..."
if helm test widgetapi --namespace "$NAMESPACE"; then
  echo "✅ Helm tests passed!"
else
  echo "❌ Helm tests failed! Gathering logs..."
  kubectl logs -n "$NAMESPACE" -l app=widgetapi || true
  exit 1
fi

### 8️⃣ Show Running Resources
echo "🔎 Debugging: Showing Kubernetes resources in $NAMESPACE..."
kubectl get all -n "$NAMESPACE"

echo "🚀 Deployment and validation complete for environment: $ENV"
