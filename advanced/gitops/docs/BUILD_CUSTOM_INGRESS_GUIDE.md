# Guide: Building and Deploying a Custom RKE2 Ingress Controller

This guide outlines the exact steps we actually executed to patch, build, and deploy our custom Ingress Controller to eliminate the CVEs flagged by Trivy, bypassing the default RKE2 lifecycle.

---

## Phase 1: Patching and Building the Image

Because the `t3.medium` admin node ran out of disk space during the build process, we had to first expand the EBS volume and resize the filesystem before compiling the image.

### 1. Clone the Source Code
On the master node, we cloned the official upstream repository:
```bash
git clone https://github.com/kubernetes/ingress-nginx.git /home/ubuntu/ingress-nginx
cd /home/ubuntu/ingress-nginx

# Checkout the branch/tag matching our RKE2 version
git checkout tags/controller-v1.14.5
```

### 2. Patch the Vulnerabilities
We updated the `Makefile` to override the build variables with our secure versions:
1. **Fix the Go CVEs (The Compiler):** We bumped the Golang builder version to `1.26.5` to eliminate the `net/http` CVEs.
2. **Fix the OS CVEs:** We set the `NGINX_BASE` image to the securely patched alpine-based distribution `registry.k8s.io/ingress-nginx/nginx:v2.2.8@...`.
3. **Custom Tag:** We modified the `TAG` variable to `v1.14.5-patched`.

*(Note on Go Modules vs Compiler)*: Bumping the builder version only updates the *compiler factory*. If the source code still demands a vulnerable third-party library, the final binary will still be vulnerable. To fix library-level CVEs (like `golang.org/x/net`), we must also rewrite the `go.mod` blueprint before building:
- `go get golang.org/x/net@v0.55.0` (Downloads the secure library and updates the `go.mod` blueprint and `go.sum` lockfile).
- `go mod tidy` (Cleans up leftover unused dependencies).
When `make image` is subsequently run, the Go compiler will read the updated `go.mod` file and bake the secure library into the new image.

### 3. Compile the Image
Instead of a simple `docker build`, we utilized the project's official `make` build system to perform a proper Go compilation of the secure binary:
```bash
# Compile the custom image directly into the local docker daemon
make ARCH=amd64 image
```

### 4. Distribute via Tarball (Air-gapped Method)
Instead of pushing to a public registry like Docker Hub, we used a local tarball distribution method so the cluster can pull the image without internet registry access:
```bash
# Save the Docker image to a tar file
docker save my-dockerhub-user/nginx-ingress:v1.14.5-patched > /tmp/nginx-ingress-patched.tar

# Move it into the containerd auto-load directory on the master node
sudo mv /tmp/nginx-ingress-patched.tar /var/lib/rancher/rke2/agent/images/

# NOTE: This tarball must also be copied (via SCP) to `/var/lib/rancher/rke2/agent/images/` on ALL worker nodes!
```

---

## Phase 2: Deploying to RKE2 (The Override)

Now we tell RKE2 to abandon its default image and pull your new patched image.

### 1. Create the HelmChartConfig
We created a configuration file that overrides the RKE2 packaged Helm chart:
```bash
nano /home/ubuntu/rke2-ingress-nginx-config.yaml
```

We used the following configuration to point to our locally loaded image:
```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-ingress-nginx
  namespace: kube-system
spec:
  failurePolicy: reinstall
  valuesContent: |-
    controller:
      image:
        repository: my-dockerhub-user/nginx-ingress
        tag: v1.14.5-patched
        digest: "" 
        pullPolicy: IfNotPresent
      metrics:
        enabled: true
        serviceMonitor:
          enabled: true
          additionalLabels:
            release: prometheus-stack
```

### 2. Apply and Watch the Rollout
We applied the configuration directly to the Kubernetes API:
```bash
kubectl apply -f /home/ubuntu/rke2-ingress-nginx-config.yaml
```

Once applied, the `rke2-server` automatically triggers the internal Helm controller to perform a Rolling Update.
Because the `pullPolicy` is `IfNotPresent` and we placed the `.tar` in the `agent/images/` directory, the `containerd` runtime on the nodes will instantly find the local image and deploy the secure pods without attempting to pull from the internet!

---

## Phase 3: Debugging the Init System Bug (`catatonit`)

After applying the configuration, the pods were stuck in a `RunContainerError`. A `kubectl describe pod` revealed the following error:
`exec: "/usr/bin/catatonit": stat /usr/bin/catatonit: no such file or directory`

**The Cause:**
By extracting the image manifest using `tar -xOf /tmp/nginx-ingress-patched.tar manifest.json`, we discovered that the upstream image `ENTRYPOINT` was configured to use `/usr/bin/catatonit`. However, our newly patched Alpine base image only had `/usr/bin/dumb-init` installed, meaning the container had no valid init system to start.

**The Fix:**
We created a new Dockerfile to symlink the expected `catatonit` binary to the existing `dumb-init` binary:

```dockerfile
FROM my-dockerhub-user/nginx-ingress:v1.14.5-patched
USER root
RUN ln -s /usr/bin/dumb-init /usr/bin/catatonit
USER www-data
```

We then built this fix and saved it as a new image `v1.14.5-patched2`:
```bash
docker build -t my-dockerhub-user/nginx-ingress:v1.14.5-patched2 -f Dockerfile.nginx-fix .
docker save my-dockerhub-user/nginx-ingress:v1.14.5-patched2 > /tmp/nginx-ingress-patched2.tar
```

---

## Phase 4: Air-Gapped Distribution to Worker Nodes

To distribute the new `.tar` file across all nodes without a registry, we ran a bash loop to SCP the file to every node's temporary directory, then moved it to the `containerd` auto-import directory:

```bash
for ip in 172.31.43.67 172.31.10.48 172.31.20.223 172.31.30.200; do
  scp /tmp/nginx-ingress-patched2.tar ubuntu@$ip:/tmp/
  ssh ubuntu@$ip "sudo mkdir -p /var/lib/rancher/rke2/agent/images/ && sudo mv /tmp/nginx-ingress-patched2.tar /var/lib/rancher/rke2/agent/images/ && sudo chown root:root /var/lib/rancher/rke2/agent/images/nginx-ingress-patched2.tar"
done
```

---

## Phase 5: Final Helm Override

Finally, we updated our `rke2-ingress-nginx-config.yaml` to point to the `v1.14.5-patched2` tag and reapplied it:

```bash
kubectl apply -f /home/ubuntu/rke2-ingress-nginx-config.yaml
```

RKE2's internal Helm controller detected the updated config, triggered a rolling update on the DaemonSet, and gracefully replaced the pods node-by-node using our secure, custom-compiled image. All ingress controller pods successfully entered the `Running` state!
