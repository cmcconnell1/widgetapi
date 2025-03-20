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
    INGRESS_CLASS="alb"
    ;;
  stage)
    NAMESPACE="widgetapi-stage"
    INGRESS_CLASS="alb"
    ;;
  prod)
    NAMESPACE="widgetapi-prod"
    INGRESS_CLASS="alb"
    ;;
  *)
    echo "❌ ERROR: Unsupported environment: $ENV"
    exit 1
    ;;
esac

echo "🔹 Using Kubernetes namespace: $NAMESPACE"
echo "🔹 Ingress Class: $INGRESS_CLASS"

### **1️⃣ Ensure Cert-Manager Is Installed**
if ! kubectl get namespace cert-manager >/dev/null 2>&1; then
  echo "🚀 Installing Cert-Manager..."
  helm repo add jetstack https://charts.jetstack.io || true
  helm repo update
  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager --create-namespace \
    --set installCRDs=true
  echo "⌛ Waiting for Cert-Manager to be ready..."
  kubectl rollout status deployment cert-manager -n cert-manager --timeout=120s
  kubectl rollout status deployment cert-manager-webhook -n cert-manager --timeout=120s
  kubectl rollout status deployment cert-manager-cainjector -n cert-manager --timeout=120s
  echo "✅ Cert-Manager installed successfully!"
else
  echo "✅ Cert-Manager is already installed."
fi

### **2️⃣ Install & Verify Ingress Controller (NGINX for Local, ALB for EKS)**
if [[ "$ENV" == "local" ]]; then
  echo "🔹 Using NGINX Ingress for local..."
  
  if ! kubectl get pods -n ingress-nginx | grep -q "ingress-nginx-controller"; then
    echo "🚀 Installing NGINX Ingress Controller..."
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
      --namespace ingress-nginx --create-namespace \
      --set controller.ingressClass=$INGRESS_CLASS \
      --set controller.service.type=NodePort \
      --set controller.service.nodePorts.http=30691 \
      --set controller.service.nodePorts.https=31863 \
      --set controller.admissionWebhooks.enabled=false

    echo "⌛ Waiting for NGINX Ingress to start..."
    sleep 5
    retries=20
    until kubectl get pods -n ingress-nginx | grep -q "Running"; do
      if [ $retries -le 0 ]; then
        echo "❌ ERROR: NGINX Ingress Controller failed to start."
        kubectl describe pod -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
        exit 1
      fi
      echo "⌛ Waiting for NGINX Ingress to start... ($((retries * 5)) seconds left)"
      sleep 5
      retries=$((retries - 1))
    done
    echo "✅ NGINX Ingress Controller is running."
  else
    echo "✅ NGINX Ingress Controller is already installed."
  fi
else
  echo "🔹 Using AWS ALB Ingress for EKS..."
  echo "✅ Ensure ALB Ingress Controller is installed for AWS EKS."
fi

### **3️⃣ Cleanup Previous Resources**
echo "⚠️ Removing any existing Helm release..."
helm uninstall widgetapi -n "$NAMESPACE" --no-hooks || true

echo "🔍 Deleting all Kubernetes resources in namespace: $NAMESPACE"
kubectl delete all --all -n "$NAMESPACE" --force --grace-period=0 || true
kubectl delete pvc --all -n "$NAMESPACE" --force --grace-period=0 || true
kubectl delete secret --all -n "$NAMESPACE" --force --grace-period=0 || true
kubectl delete configmap --all -n "$NAMESPACE" --force --grace-period=0 || true

### **4️⃣ Ensure Namespace Is Clean**
echo "🚨 Deleting namespace to prevent auto-recreation..."
kubectl delete namespace "$NAMESPACE" --force --grace-period=0 || true

echo "⌛ Waiting for namespace deletion..."
while kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; do
  echo "⌛ Waiting for namespace $NAMESPACE to be fully removed..."
  sleep 5
done

echo "✅ Namespace $NAMESPACE fully deleted."

### **5️⃣ Recreate Namespace**
echo "🚀 Recreating namespace: $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

### **6️⃣ Deploy WidgetAPI Helm Chart**
echo "🚀 Installing Helm release for WidgetAPI..."
helm upgrade --install widgetapi chart/ \
  --namespace "$NAMESPACE" --create-namespace \
  --values chart/${ENV}-values.yaml \
  --set ingress.className=$INGRESS_CLASS \
  --atomic --timeout 300s --wait

echo "✅ Deployment complete for environment: $ENV"

### **7️⃣ Run Helm Tests**
echo "🔎 Running Helm tests..."
if helm test widgetapi --namespace "$NAMESPACE"; then
  echo "✅ Helm tests passed!"
else
  echo "❌ Helm tests failed! Check logs for debugging."
  kubectl logs -n "$NAMESPACE" -l app=widgetapi || true
  exit 1
fi

### **8️⃣ Debugging: Show Running Resources**
echo "🔎 Debugging: Showing Kubernetes resources in $NAMESPACE..."
kubectl get all -n "$NAMESPACE"

echo "🚀 Deployment and validation complete for environment: $ENV"
