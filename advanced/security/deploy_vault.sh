#!/bin/bash
set -e

echo "1. Deploying External Secrets Operator (if not exist)..."
kubectl apply -f external-secrets.yaml || true

echo "2. Applying Vault TLS Cert-Manager configs..."
kubectl apply -f vault-tls.yaml

echo "3. Deploying Vault via Helm..."
helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null || true
helm repo update
helm upgrade --install vault hashicorp/vault -n vault --create-namespace -f vault-values.yaml

echo "4. Waiting for Vault pods to be Ready (auto-unseal via KMS)..."
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=vault -n vault --timeout=300s

echo "5. Configuring Vault K8s Auth..."
sleep 5 # Ensure leader election settles
if [ -z "$VAULT_TOKEN" ]; then
  echo "Error: VAULT_TOKEN environment variable is not set."
  exit 1
fi
kubectl exec vault-0 -n vault -- sh -c "VAULT_TOKEN=\"$VAULT_TOKEN\" vault write -tls-skip-verify auth/kubernetes/config kubernetes_host=\"https://kubernetes.default.svc:443\" disable_iss_validation=true disable_local_ca_jwt=false" || echo "K8s auth config failed. Ensure Vault is initialized."

echo "6. Creating ESO ClusterSecretStore..."
kubectl apply -f vault-store.yaml

echo "Vault deployment complete. Check status with: kubectl get clustersecretstore production-vault"
