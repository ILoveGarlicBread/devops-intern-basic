#!/bin/bash

echo "Starting logging stack deployment..."

# 1. Add Bitnami Legacy repository (used for migration-proofing)
helm repo add bitnamilegacy https://raw.githubusercontent.com/bitnami/charts/archive-full-index/bitnami
helm repo update

# 2. Ensure namespace exists
kubectl create namespace logging --dry-run=client -o yaml | kubectl apply -f -

# 3. Deploy Elasticsearch
echo "Deploying Elasticsearch..."
helm upgrade --install elasticsearch bitnamilegacy/elasticsearch \
  --namespace logging \
  --version 22.1.6 \
  -f ../helm_values/elasticsearch-values.yaml

# 4. Deploy Logstash
echo "Deploying Logstash..."
helm upgrade --install logstash bitnamilegacy/logstash \
  --namespace logging \
  --version 7.0.11 \
  -f ../helm_values/logstash-values.yaml

# 5. Deploy Kibana
echo "Deploying Kibana..."
helm upgrade --install kibana bitnamilegacy/kibana \
  --namespace logging \
  --version 12.1.10 \
  -f ../helm_values/kibana-values.yaml

# 6. Deploy Fluent-Bit
echo "Deploying Fluent-Bit..."
helm upgrade --install fluent-bit bitnamilegacy/fluent-bit \
  --namespace logging \
  --version 3.1.13 \
  -f ../helm_values/fluent-bit-values.yaml

echo "Logging stack deployment complete! Use 'kubectl get pods -n logging' to check the status."
