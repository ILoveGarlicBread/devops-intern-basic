#!/bin/bash

echo "Starting OTel/Loki logging stack deployment..."

helm repo add grafana https://grafana.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

# Ensure namespace exists
kubectl create namespace logging --dry-run=client -o yaml | kubectl apply -f -

# Deploy Loki
echo "Deploying Loki..."
helm upgrade --install loki grafana/loki \
  --namespace logging \
  -f loki-prod-values.yaml

# Deploy OTel Gateway
echo "Deploying OpenTelemetry Gateway..."
helm upgrade --install otel-gateway open-telemetry/opentelemetry-collector \
  --namespace logging \
  -f otel-gateway-values.yaml

# Deploy OTel Agent
echo "Deploying OpenTelemetry Agent..."
helm upgrade --install otel-agent open-telemetry/opentelemetry-collector \
  --namespace logging \
  -f otel-agent-values.yaml

# Apply dashboard configmap
if [ -f "loki-dashboard-cm.yaml" ]; then
    echo "Applying Loki Dashboard ConfigMap..."
    kubectl apply -f loki-dashboard-cm.yaml
fi

echo "OTel/Loki stack deployment complete! Use 'kubectl get pods -n logging' to check the status."
