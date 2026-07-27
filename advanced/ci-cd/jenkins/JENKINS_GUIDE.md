# Jenkins CI/CD on Kubernetes: The GitOps Way

This guide documents the pivot from AWS CodeBuild to Jenkins, our GitOps deployment architecture, and foundational Jenkins concepts for enterprise DevOps.

## 1. Why We Pivoted to Jenkins (Bypassing AWS CodeBuild Limits)
Initially, we attempted to use **AWS CodeBuild** for our Continuous Integration (building our Python Docker images). However, we ran into a strict AWS anti-fraud account limit:
*   **The Error:** `Cannot have more than 0 builds in queue for the account`
*   **The Cause:** AWS sets a hard Service Quota of `0.0` for all CodeBuild compute environments on restricted accounts to prevent crypto-mining abuse.
*   **The Lambda Workaround Failed:** While AWS Support approved a quota increase for the `Linux Lambda/4GB` compute environment, **Docker builds (`docker build`) require Privileged Mode.** AWS Lambda environments physically cannot run Docker-in-Docker.
*   **The Solution:** By deploying **Jenkins** inside our own Kubernetes cluster (running on our EC2 worker nodes), we bypassed AWS completely. We own the infrastructure, so we control the concurrent build limits!

## 2. Deploying Jenkins: The GitOps "Umbrella Chart" Architecture
In modern DevOps, we **never** run manual `helm install jenkins jenkins/jenkins` commands from a terminal. If the cluster crashes, or a teammate makes an unrecorded change, we experience "Configuration Drift."

Instead, we used an **Umbrella Chart** managed by **ArgoCD**:

### The Architecture:
1.  **`Chart.yaml` (The Wrapper):**
    Instead of downloading hundreds of Jenkins templates into our Git repository, we created a `Chart.yaml` with a `dependencies` block pointing to the official `https://charts.jenkins.io` repository.
2.  **`values.yaml` (The Configuration):**
    We defined our persistent storage (`15Gi` Longhorn), Ingress routes, and a list of pre-installed plugins (e.g., `kubernetes`, `git`, `docker-workflow`).
3.  **`jenkins-app.yaml` (The ArgoCD App):**
    ArgoCD sees our Git commit, automatically downloads the official Jenkins templates in the background (`helm dependency build`), injects our local `values.yaml`, and applies it to the cluster.

### Why This is Better Than `helm install`:
*   **Disaster Recovery:** If our cluster is deleted, we just point ArgoCD at the new cluster, and our exact Jenkins setup (plugins, storage limits, and version) is restored in 5 minutes.
*   **Peer Review:** If a developer wants to add a new Jenkins plugin, they can't run `helm upgrade`. They must open a Git Pull Request to edit `values.yaml`.
*   **No Drift:** If someone manually modifies the Jenkins cluster, ArgoCD instantly detects the drift and rewrites the cluster to match Git.

## 3. Jenkins Plugin Resolution Issue
During our initial deployment, the Jenkins `init` container got stuck in a `CrashLoopBackOff`. 
*   **The Mistake:** We appended `:latest` to the plugins in our `values.yaml` (e.g., `kubernetes:latest`).
*   **The Fix:** The Jenkins CLI does not support the `:latest` tag. It requires either the exact version hash (e.g. `kubernetes:4267.v339fb...`) or the name *without any version* (e.g., `kubernetes`), which tells Jenkins to dynamically resolve the latest version.

## 4. Useful Commands

**Check Jenkins Deployment Status:**
```bash
kubectl get pods -n jenkins -w
```

**Retrieve the Auto-Generated Admin Password:**
Once the pod is fully running, run this to get the initial login password:
```bash
kubectl get secret jenkins -n jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode && echo
```
