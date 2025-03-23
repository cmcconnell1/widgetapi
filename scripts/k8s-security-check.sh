#!/bin/bash
set -e

NAMESPACE=${1:-default}

echo "🔍 Running Kubernetes security checks in namespace: $NAMESPACE"

# Check for privileged pods
echo "🚨 Checking for privileged pods..."
kubectl get pods -n "$NAMESPACE" -o=jsonpath="{.items[*].spec.containers[*].securityContext.privileged}" | grep -q "true" && echo "❌ Privileged pods detected!" || echo "✅ No privileged pods found."

# Check for containers running as root
echo "🚨 Checking for containers running as root..."
kubectl get pods -n "$NAMESPACE" -o=jsonpath="{.items[*].spec.containers[*].securityContext.runAsNonRoot}" | grep -q "false" && echo "❌ Containers running as root detected!" || echo "✅ All containers running as non-root."

# Validate network policies
echo "🔍 Checking for network policies..."
kubectl get networkpolicy -n "$NAMESPACE" || echo "⚠ No network policies found. Ensure proper network isolation."

echo "✅ Kubernetes security checks completed."
