#!/bin/bash
set -e

echo "🔒 Vault Injection & External Secrets Fix Script"
echo "------------------------------------------------"
echo "This script will:"
echo "1. Log into Vault using your Root Token"
echo "2. Fix the broken Kubernetes Authentication for External Secrets Operator"
echo "3. Inject the ArgoCD CodeCommit SSH Private Key into Vault"
echo "4. Deploy the ExternalSecret to sync it securely to ArgoCD"
echo ""

read -s -p "Enter your Vault Initial Root Token: " VAULT_TOKEN
echo ""

echo "Logging into Vault..."
kubectl exec -n vault -it vault-0 -- sh -c "VAULT_SKIP_VERIFY=true vault login $VAULT_TOKEN" > /dev/null

echo "Fixing Kubernetes Authentication..."
# Generate a new long-lived token for the vault service account
NEW_REVIEWER_TOKEN=$(kubectl -n vault create token vault --duration=87600h)

# Update Vault K8s Auth
kubectl exec -n vault -it vault-0 -- sh -c "VAULT_TOKEN=$VAULT_TOKEN VAULT_SKIP_VERIFY=true vault write auth/kubernetes/config \
    token_reviewer_jwt=\"$NEW_REVIEWER_TOKEN\" \
    kubernetes_host=\"https://kubernetes.default.svc\" \
    disable_iss_validation=true" > /dev/null

echo "Injecting ArgoCD SSH Private Key into Vault..."
# Write to Vault KV by passing the file through stdin
kubectl exec -n vault -i vault-0 -- sh -c "VAULT_TOKEN=$VAULT_TOKEN VAULT_SKIP_VERIFY=true vault kv put secret/argocd/codecommit-ssh-key sshPrivateKey=-" < ~/.ssh/argocd_codecommit_rsa > /dev/null

echo "Applying ExternalSecret Manifest..."
kubectl apply -f advanced/helm_values/ci-cd/argocd-external-secret.yaml

# Clean up the static secret I created earlier
echo "Cleaning up the old static secret..."
kubectl delete secret repo-tma-devops -n argocd --ignore-not-found

echo ""
echo "✅ Done! External Secrets Operator will now securely fetch the SSH key from Vault and provide it to ArgoCD!"
