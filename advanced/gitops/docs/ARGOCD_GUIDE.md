# ArgoCD & GitOps Implementation Guide

## 1. The GitOps Architecture
ArgoCD is built entirely around **GitOps**, where **Git is the absolute single source of truth** for your infrastructure.

### The CI/CD Separation
*   **CI (Continuous Integration - GitHub Actions/Jenkins):** Compiles code, runs tests, builds Docker images, pushes to a registry, and updates the `image.tag` in a Git repository. *It does not have access to the Kubernetes cluster.*
*   **CD (Continuous Delivery - ArgoCD):** Lives inside the Kubernetes cluster, watches the Git repository, detects the updated image tag, and safely rolls out the changes to the cluster.

### The App of Apps Standard
To manage complex clusters with many tools, we use the **App of Apps** pattern. Instead of creating ArgoCD applications manually in the UI, we create one "Root Application" that points to a folder in Git. That folder contains YAML definitions for all our other applications (Vault, Monitoring, Fineract). Adding a new tool to the cluster is as simple as adding a new YAML file to that folder.

## 2. ArgoCD Architecture (Low-Level)
ArgoCD is a microservice architecture consisting of 5 core components:
1.  **`argocd-server`:** The Frontend UI and API gateway.
2.  **`argocd-repo-server`:** Clones the Git repo and generates Kubernetes manifests (runs `helm template` in memory).
3.  **`argocd-application-controller`:** The brain. It uses a **3-Way Merge algorithm** to calculate drift between Git, the live cluster, and the last applied state. It executes changes using Kubernetes Informer WebSockets.
4.  **`redis`:** Caches Git repo states and cluster states to prevent overloading the Kubernetes API server.
5.  **`argocd-dex-server`:** Optional Identity Provider for SSO (OIDC/SAML) integration.

## 3. Installation Guide (Manual Bootstrap)
ArgoCD replaces manual deployment commands, but you must run one manual command to "bootstrap" ArgoCD itself into the cluster.

### A. Add the Helm Repository
```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

### B. Bootstrap Install
Install ArgoCD into the `argocd` namespace using our custom values:
```bash
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  -f advanced/gitops/helm-values/ci-cd/argocd-values.yaml
```

### C. Retrieve Initial Admin Password
ArgoCD auto-generates a secure password and stores it in a Kubernetes secret. Extract it using:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### D. Access the UI
If an Ingress is not configured, port-forward the UI locally:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
Log in at `https://localhost:8080` using the username `admin` and the extracted password.

## 4. Brownfield Adoption (Managing Existing Stacks)
To hand over your existing Fineract stack to ArgoCD:
1. Ensure your Git repo perfectly matches the live cluster state.
2. Create an ArgoCD Application pointing to the `fineract` namespace with **Auto-Sync OFF**.
5. Review the visual diff in the ArgoCD UI.
6. Click "Sync" to allow ArgoCD to inject its tracking annotations (`argocd.argoproj.io/tracking-id`) and adopt the resources without downtime.

## 5. Deployed Applications (Current State)

### A. Fineract Domain App (Brownfield)
*   **Repo**: `https://git-codecommit.ap-south-1.amazonaws.com/v1/repos/TMA-DevOps-Lam-Internship`
*   **Path**: `advanced/fineract`
*   **Status**: Created. **Requires Git Repository Credentials in ArgoCD to perform initial sync.** Auto-sync is currently turned **OFF** to safely perform brownfield adoption of the existing Fineract stack.

### B. AI Agent Application
*   **Repo**: `https://git-codecommit.ap-south-1.amazonaws.com/v1/repos/TMA-DevOps-Lam-Internship`
*   **Path**: `advanced/ai-agent/helm/ai-agent`
*   **Status**: Deployed. Agent successfully authenticates with OpenAI API natively.

## 6. Troubleshooting & Operational Solutions

### A. Sync Lag (The 3-Minute Window)
**Problem:** ArgoCD polls the Git repository every 3 minutes by default (unless webhooks are configured). If you push a code change to Git and immediately delete a crashing pod to force a restart, Kubernetes may spawn a new pod *before* ArgoCD has applied the new Git state. This causes the pod to crash again using the old configuration.
**Solution:** Force ArgoCD to bypass the 3-minute timer and pull the latest Git commit instantly using a "Hard Refresh":
```bash
kubectl patch application <app-name> -n argocd --type merge -p '{"metadata": {"annotations": {"argocd.argoproj.io/refresh": "hard"}}}'
```
