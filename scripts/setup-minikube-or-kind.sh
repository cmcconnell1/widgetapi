#!/usr/bin/env bash

# Display help
usage() {
  echo "Usage: $0 [ -m | --minikube ] [ -k | --kind ]" 
  echo "  -m | --minikube   Use Minikube instead of Kind"
  echo "  -k | --kind       Use Kind instead of Minikube"
  exit 0
}

# Default to minikube unless specified
USE_MINIKUBE="true"

# Argument Parsing
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -m | --minikube) USE_MINIKUBE="true" ;;
    -k | --kind) USE_MINIKUBE="false" ;;
    -h | --help) usage ;;
    *) echo "❌ Unknown parameter: $1"; exit 1 ;;
  esac
  shift
done

# Setup Minikube or Kind
if [[ "$USE_MINIKUBE" == "true" ]]; then
  command -v minikube >/dev/null 2>&1 || { echo "📦 Installing minikube..."; brew install minikube; }
  echo "🚀 Starting Minikube..."
  minikube start --memory=2g --cpus=2
  # Enable required Minikube addons
  minikube addons enable ingress
  minikube addons enable storage-provisioner
  minikube addons enable metrics-server
  minikube addons enable default-storageclass
  # Optional but recommended
  minikube addons enable volumesnapshots  # (Optional) Snapshot backups for PVCs
  minikube addons enable ingress-dns  # (Optional) Local DNS resolution for ingress
  #minikube tunnel in separate terminal
else
  command -v kind >/dev/null 2>&1 || { echo "📦 Installing Kind..."; brew install kind; }
  echo "🚀 Starting Kind..."
  cat <<EOF | kind create cluster --name=argocd-demo --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30080
    hostPort: 8080
EOF
fi

# Ensure Kubernetes API is Ready
echo "⏳ Waiting for Kubernetes API to be ready..."
until kubectl get --raw /readyz >/dev/null 2>&1; do
  echo "Waiting for Kubernetes API..."
  sleep 5
done
