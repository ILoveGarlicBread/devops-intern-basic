#!/bin/bash

echo "Starting monitoring stack deployment..."

# 1. Add required Helm repositories
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 2. Ensure namespace exists
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# 3. Deploy the Kube-Prometheus-Stack (Grafana, Prometheus, Alertmanager)
echo "Deploying kube-prometheus-stack..."
helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --version 86.3.1 \
  -f ../helm_values/prometheus-values.yaml

# 4. Deploy MySQL Exporter for Default DB
echo "Deploying MySQL Exporter for Default DB..."
helm upgrade --install mysql-exporter-default prometheus-community/prometheus-mysql-exporter \
  --namespace monitoring \
  --version 2.14.0 \
  -f mysql-default-values.yaml

# 5. Deploy MySQL Exporter for Tenants DB
echo "Deploying MySQL Exporter for Tenants DB..."
helm upgrade --install mysql-exporter-tenants prometheus-community/prometheus-mysql-exporter \
  --namespace monitoring \
  --version 2.14.0 \
  -f mysql-tenants-values.yaml

# 6. Apply Longhorn Custom ServiceMonitor and PrometheusRule Manifests
echo "Applying Longhorn Monitoring manifests..."
kubectl apply -f longhorn-prometheus-rules.yaml
kubectl apply -f longhorn-servicemonitor.yaml

# 7. Deploy Fineract Business Metrics Exporter and Dashboard
echo "Applying Fineract Business Metrics manifests..."
kubectl apply -f ../fineract-business-exporter.yaml
kubectl apply -f ../fineract-business-rules.yaml
kubectl apply -f ../fineract-business-dashboard.yaml

# 8. Patch Alertmanager Generated Configuration to fix PrometheusOperatorSyncFailed
# The kube-prometheus-stack base chart often passes a default empty string for slack_api_url,
# which clashes with slack_api_url_file and breaks the operator sync.
echo "Patching AlertManager generated secret..."
kubectl get secret alertmanager-prometheus-stack-kube-prom-alertmanager -n monitoring -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d > am.yaml
sed -i '/slack_api_url: ""/d' am.yaml
kubectl create secret generic alertmanager-prometheus-stack-kube-prom-alertmanager -n monitoring --from-file=alertmanager.yaml=am.yaml --dry-run=client -o yaml | kubectl apply -f -
rm -f am.yaml

echo "Deployment complete! Use 'kubectl get pods -n monitoring' to check the status."
