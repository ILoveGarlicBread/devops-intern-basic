# Guide: Building and Deploying a Custom RKE2 Ingress Controller

This guide outlines the exact steps required to patch, build, and deploy your own custom Ingress Controller to eliminate the CVEs flagged by Trivy, bypassing the default RKE2 lifecycle.

---

## Phase 1: Patching and Building the Image

Because you are running RKE2's hardened version, we will fork from Rancher's official repository rather than the standard Kubernetes upstream. This ensures you keep their specific RBAC and RKE2-compatibility fixes.

### 1. Clone the Source Code
On a machine with Docker and Git installed (like your master node or a local laptop):
```bash
# Clone Rancher's specific fork of the ingress-nginx controller
git clone https://github.com/rancher/ingress-nginx.git
cd ingress-nginx

# Checkout the branch/tag that closely matches your current v1.14.5 version
git checkout tags/v1.14.5
```

### 2. Patch the Vulnerabilities
Open the `Dockerfile` (typically located in the `rootfs/` or `images/` directory depending on the branch).
1. **Fix the Go CVEs:** Look for the line that defines the Golang builder version (e.g., `ARG GOLANG_VERSION=1.26.2`). Change it to the patched version Trivy recommended:
   ```dockerfile
   ARG GOLANG_VERSION=1.26.5
   ```
2. **Fix the OS CVEs:** Look for the final base image stage (e.g., `FROM suse/sles16.0`). Change it to the newest patched version of that OS, or swap it to a minimal, secure base like Alpine:
   ```dockerfile
   FROM alpine:3.24.2
   ```

### 3. Build and Scan the Image
Build the Docker image and tag it with your custom identifier:
```bash
docker build -t my-dockerhub-user/nginx-ingress:v1.14.5-patched -f rootfs/Dockerfile .
```
*(Crucial Step)*: Run Trivy against your newly built image to verify the vulnerabilities are gone before deploying it to production!
```bash
trivy image --severity HIGH,CRITICAL my-dockerhub-user/nginx-ingress:v1.14.5-patched
```

### 4. Push to a Container Registry
Push the image to a registry that your Kubernetes cluster has access to (like Docker Hub, AWS ECR, or a private company registry).
```bash
docker push my-dockerhub-user/nginx-ingress:v1.14.5-patched
```

---

## Phase 2: Deploying to RKE2 (The Override)

Now we tell RKE2 to abandon its default image and pull your new patched image.

### 1. Create the HelmChartConfig
SSH into your RKE2 Master Node. Create a configuration file that overrides the RKE2 packaged Helm chart:
```bash
sudo nano /var/lib/rancher/rke2/server/manifests/rke2-ingress-nginx-config.yaml
```

Paste the following configuration, replacing the registry and image with your actual push destination:
```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-ingress-nginx
  namespace: kube-system
spec:
  valuesContent: |-
    controller:
      image:
        registry: docker.io
        image: my-dockerhub-user/nginx-ingress
        tag: "v1.14.5-patched"
        digest: "" 
        # (Setting digest to empty string prevents RKE2 from trying to enforce the old image hash)
```

### 2. Watch the Rollout
As soon as you save the file in the `/var/lib/rancher/rke2/server/manifests/` directory, the `rke2-server` service will instantly detect it. It automatically triggers the Helm controller to perform a Rolling Update.

You can watch the magic happen live by running:
```bash
kubectl get pods -n kube-system -w | grep ingress-nginx
```

You will see Kubernetes gracefully spin up a new pod with your `patched` image. Once it passes its readiness probes, it will terminate the old vulnerable `hardened2` pod, ensuring absolutely zero downtime for your Fineract APIs.
