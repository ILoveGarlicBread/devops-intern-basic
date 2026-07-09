# Deploying Production Vault in Kubernetes

This guide walks you through replacing AWS SSM Parameter Store with a production-ready, highly available HashiCorp Vault cluster running completely inside your Kubernetes environment. 

We will deploy Vault in **High Availability (HA) mode** using **Integrated Raft Storage**.

---

## Step 1: Install Vault via Helm (HA Mode)

First, create a dedicated namespace and install the Helm chart. We configure it to use Raft storage with 3 replicas.

Run these commands:
```bash
# 1. Create the production namespace
kubectl create namespace vault

# 2. Add Hashicorp repo (if you haven't already)
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# 3. Create a values file for High Availability
cat <<EOF > vault-ha-values.yaml
server:
  dataStorage:
    size: 1Gi
  affinity: ""
  ha:
    enabled: true
    replicas: 3
    raft:
      enabled: true
      setNodeId: true
      config: |
        ui = true
        listener "tcp" {
          tls_disable = 1
          address = "[::]:8200"
          cluster_address = "[::]:8201"
        }
        storage "raft" {
          path = "/vault/data"
        }
EOF

# 4. Deploy Vault
helm install vault hashicorp/vault -n vault -f vault-ha-values.yaml
```

*Note: In this guide we use `tls_disable = 1` to simplify internal cluster routing for learning. In a strict enterprise, you would provision TLS certificates for the Vault pods. We also request `1Gi` storage to avoid overwhelming learning clusters.*

---

## Step 2: Initialize and Unseal Vault

Unlike Dev Mode, production Vault starts up **Sealed**. You must initialize it to generate the Master Keys, and then use those keys to unseal it.

Run these commands carefully and **save the output**:

```bash
# 1. Initialize Vault on the first node
kubectl exec -n vault vault-0 -- vault operator init -key-shares=5 -key-threshold=3
```
⚠️ **CRITICAL:** The command above will print 5 Unseal Keys and 1 Initial Root Token. **Copy these down somewhere safe immediately.** You will lose access forever if you lose them.

```bash
# 2. Unseal the first node (Run this 3 times, pasting a different Unseal Key each time)
kubectl exec -n vault -it vault-0 -- vault operator unseal
```

> 🛡️ **Security Tip**: Notice the `-it` flag. This creates an interactive prompt so you can type the key invisibly. While you *can* pass the key directly (e.g. `vault operator unseal <key>`), this is dangerous because it saves your highly sensitive unseal key permanently in your terminal's `~/.bash_history` file. **Always use the interactive prompt.**

```bash
# 3. Join the other two nodes to the Raft cluster
kubectl exec -n vault -it vault-1 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec -n vault -it vault-2 -- vault operator raft join http://vault-0.vault-internal:8200

# 4. Unseal the remaining nodes (Run this 3 times per node, just like node 0)
kubectl exec -n vault -it vault-1 -- vault operator unseal
kubectl exec -n vault -it vault-2 -- vault operator unseal
```

---

## Step 3: Configure Kubernetes Authentication

To allow External Secrets Operator (ESO) to talk to Vault securely, we enable Kubernetes Auth. This allows ESO to authenticate using a Kubernetes ServiceAccount token instead of a hardcoded Root token.

```bash
# 1. Log into Vault using your Initial Root Token
kubectl exec -n vault -it vault-0 -- sh
> vault login <YOUR_INITIAL_ROOT_TOKEN>

# 2. Enable the Key-Value (v2) secrets engine
> vault secrets enable -path=secret kv-v2

# 3. Enable Kubernetes Authentication
> vault auth enable kubernetes

# 4. Configure Vault to talk to the Kubernetes API
> vault write auth/kubernetes/config \
    kubernetes_host="https://\$KUBERNETES_PORT_443_TCP_ADDR:443"

# 5. Create a Read-Only Policy for ESO
> vault policy write eso-read - <<EOF
path "secret/data/*" {
  capabilities = ["read", "list"]
}
EOF

# 6. Bind the Policy to a Kubernetes Role
> vault write auth/kubernetes/role/eso-role \
    bound_service_account_names=external-secrets \
    bound_service_account_namespaces=external-secrets \
    policies=eso-read \
    ttl=1h

# 7. Exit the pod
> exit
```

---

## Step 4: Re-wire External Secrets Operator

Finally, update your `ClusterSecretStore` to authenticate with Vault using the Kubernetes Service Account.

```bash
# Apply the new ClusterSecretStore
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: production-vault
spec:
  provider:
    vault:
      server: "http://vault.vault.svc.cluster.local:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "eso-role"
          serviceAccountRef:
            name: "external-secrets"
            namespace: "external-secrets"
EOF
```

You can now port-forward `kubectl port-forward svc/vault-ui 8200:8200 -n vault` to access the UI, add your real passwords, and update your `ExternalSecret` manifests to point to `production-vault`!
