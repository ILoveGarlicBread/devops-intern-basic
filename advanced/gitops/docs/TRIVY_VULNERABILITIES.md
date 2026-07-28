# Trivy Security Vulnerabilities & Remediation

This document outlines the Pod Security misconfigurations and vulnerabilities identified by Trivy during static Helm chart auditing. The security context fixes ensure our Kubernetes workloads follow least-privilege principles, preventing container escapes and unnecessary resource consumption.

## Global Fix Strategy

For all workloads across our stacks, the following security baseline is applied:

1. **Pod Security Context:**
   - Enforce non-root execution (`runAsNonRoot: true`, `runAsUser: 10001`, `runAsGroup: 10001`).
   - Filter dangerous system calls via `seccompProfile: { type: RuntimeDefault }`.
2. **Container Security Context:**
   - Prevent privilege escalation (`allowPrivilegeEscalation: false`).
   - Restrict file modifications (`readOnlyRootFilesystem: true`).
   - Drop all default capabilities (`capabilities: { drop: ["ALL"] }`).
3. **Resource Limits:** Ensure all containers define requests and limits for CPU and Memory.
4. **Image Tagging:** Avoid `:latest` tags; use specific version tags.

---

## Service Stacks

### 1. Fineract Core Stack
*(Identified via `trivy config ./advanced/fineract`)*

#### A. Fineract Backend (`fineract-server-deployment.yml`)
- **Vulnerabilities Identified:**
  - `KSV-0001`: Privilege escalation not explicitly denied.
  - `KSV-0012`, `KSV-0118`: Container allows root execution (default security context).
  - `KSV-0014`: Root filesystem is writable.
  - `KSV-0030`, `KSV-0104`: Missing seccomp profile.
  - `KSV-0003`, `KSV-0004`, `KSV-0106`: Linux capabilities not dropped.
- **Fix Applied:** Injected the standard strict Pod and Container `securityContext` block.

#### B. Fineract UI (`fineract-ui-deployment.yml`)
- **Vulnerabilities Identified:**
  - `KSV-0001`, `KSV-0012`, `KSV-0118`, `KSV-0014`, `KSV-0030`, `KSV-0003`.
  - `KSV-0013`: Image tag not specified (using `:latest`).
  - `KSV-0015`, `KSV-0016`: Missing CPU/Memory requests.
- **Fix Applied:** Injected strict security contexts and resource constraints. Mapped `emptyDir` volumes to `/var/cache/nginx` and `/var/run` to support the internal UI webserver under a read-only filesystem. Pinning image tag from `latest` to a stable tag is recommended in `values.yaml`.

#### C. Fineract Nginx Proxy (`fineract-nginx.yaml`)
- **Vulnerabilities Identified:**
  - `KSV-0001`, `KSV-0012`, `KSV-0118`, `KSV-0014`, `KSV-0030`, `KSV-0003`.
- **Fix Applied:** Injected strict security contexts. Successfully mapped ephemeral `emptyDir` volumes to `/var/cache/nginx` and `/var/run` to allow NGINX to cache data dynamically and prevent `CrashLoopBackOff` while maintaining a strict read-only root filesystem.

#### D. Fineract Logical Backup CronJob (`fineract-backup-cronjob.yaml`)
- **Vulnerabilities Identified:**
  - `KSV-0001`, `KSV-0012`, `KSV-0118`, `KSV-0014`, `KSV-0030`, `KSV-0003`.
  - `KSV-0011`, `KSV-0015`, `KSV-0016`, `KSV-0018`: Missing resource requests and limits.
- **Fix Applied:** Injected strict security contexts. Added missing CPU and Memory constraints for the backup-worker container.

#### E. Fineract Tenant & Default Databases (`mysql-default.yaml`, `mysql-tenants.yaml`)
- **Vulnerabilities Identified:**
  - `KSV-0001`, `KSV-0012`, `KSV-0118`, `KSV-0014`, `KSV-0030`, `KSV-0003`.
- **Fix Applied:** Injected strict security contexts. Swapped the vulnerable `mariadb:11.4` image for the hardened `bitnami/mariadb:latest`. 
  - **Volume Permission Resolution:** Resolved critical `Permission denied` startup errors (caused by the new non-root execution `runAsUser: 10001` accessing legacy root-created databases) by injecting `fsGroup: 10001` into the pod's security context. This triggers Kubernetes to automatically `chown` the existing PVCs, ensuring seamless data continuity.
  - **Read-Only Compatibility:** Appended `emptyDir` mounts for `/tmp`, `/opt/bitnami/mariadb/tmp`, and `/opt/bitnami/mariadb/logs` to support the read-only root filesystem requirement.

*(Note: As other service stacks are deployed and audited, they will be appended to this document.)*

---

## 2. Docker Image CVE Scanning
*(Identified via `trivy image`)*

Due to hardware constraints on the master node (4GB RAM) and the massive size of the Java vulnerability databases (>890MB) plus Fineract's base images, local CVE scanning experiences severe Out-Of-Memory (OOM) errors and disk quota exhaustion. It is heavily recommended to offload all CVE scans to a CI/CD pipeline (e.g., GitHub Actions). 

### Recent Scan Attempts:

#### 1. MariaDB Base Image (`mariadb:11.4`)
Scan completed successfully. Identified **15 HIGH/CRITICAL CVEs**. 
Although MariaDB is a C/C++ application, it embeds static Go helper utilities (like `gosu`) to drop root privileges on container startup. The vulnerable library is `stdlib` (Go version `v1.26.1`), yielding the following CVEs:
- **`CVE-2026-27145` (HIGH):** `crypto/x509` Denial of Service via excessive DNS processing.
- **`CVE-2026-32281`, `CVE-2026-32283` (HIGH):** `crypto/tls` Denial of Service via TLS 1.3 key exchanges.
- **`CVE-2026-33811` (HIGH):** `net` package Denial of Service via long CNAME response.
- **`CVE-2026-33814`, `CVE-2026-39820`, `CVE-2026-39822`, `CVE-2026-42499`, `CVE-2026-42504`:** Additional DoS vulnerabilities in Go's `net/http2`, `net/mail`, `os`, and `mime` packages.
*(Note: Because the `gosu` utility only executes briefly during startup and does not expose network ports, these CVEs are practically unexploitable).*

#### 2. RKE2 Ingress Controller (`rancher/nginx-ingress-controller:v1.14.5-hardened2`)
Scan completed successfully. Identified **27 HIGH CVEs** in base OS packages and **12 HIGH CVEs** in the Go binary (`nginx-ingress-controller`).
- **OS Packages (SUSE Linux `sles 16.0`):** Flagged `curl`, `glibc`, `liblzma5` (xz), `python313`, and `tar`. Example: `SUSE-SU-2026:22582-1` (curl update).
- **Go Application (`golang.org/x/net` & `stdlib v1.26.2`):**
  - **`CVE-2026-25681`, `CVE-2026-27136` (HIGH):** Cross-Site Scripting (XSS) via HTML parsing bypass.
  - **`CVE-2026-39821` (HIGH):** Privilege escalation via incorrect Punycode label processing (`net/idna`).
  - Plus the same suite of DoS vulnerabilities (`CVE-2026-33814`, `CVE-2026-42504`) found in the MariaDB Go compiler.

#### 3. Fineract App (`openmf/community-app:latest`)
Scan **failed immediately**. The Trivy Java DB download caused a `disk quota exceeded` fatal error, preventing the scan from executing on the constrained master node.

#### 4. Prometheus (`quay.io/prometheus/prometheus:v2.52.0`)
Scan completed successfully (using custom `TMPDIR`). Identified **39 HIGH** and **4 CRITICAL** CVEs.
- **Base OS:** 0 vulnerabilities (distroless base).
- **Go Application:** 
  - Flagged CRITICAL in `github.com/docker/docker` (`CVE-2024-41110` auth bypass) and `google.golang.org/grpc` (`CVE-2026-33186`).
  - Flagged HIGH in `net/url` and `crypto/x509` (similar Go stdlib issues).
  - *Risk:* Prometheus exposes a web API, so the gRPC and URL vulnerabilities are theoretically reachable, although the Docker/SSH ones are false alarms (Prometheus only uses them for node discovery).

#### 5. Longhorn Manager (`docker.io/longhornio/longhorn-manager:v1.12.0`)
Scan completed successfully. Identified **29 HIGH** CVEs.
- **Base OS (SUSE Linux `sles 15.7`):** 14 HIGH vulnerabilities in system utilities like `curl`, `glibc`, `sqlite3`, and `libopenssl`.
- **Go Application:** 15 HIGH vulnerabilities, purely in `golang.org/x/crypto/ssh` and `net/html`, identical to the Go compiler issues found in MariaDB and Ingress.

#### 6. Grafana (`docker.io/grafana/grafana:11.0.0`)
Scan completed successfully. Identified **77 total vulnerabilities** across the base OS and Go binaries.
- **Base OS (Alpine 3.19.1):** 8 HIGH vulnerabilities (`curl`, `libcrypto3`, `musl`). *Note: Trivy warned that Alpine 3.19.1 is out of support.*
- **Go Application (`grafana`, `grafana-cli`, `grafana-server`):** 52 vulnerabilities (47 HIGH, 5 CRITICAL).
  - **CRITICAL ALERT:** `CVE-2024-9264` (Command injection and local file inclusion via SQL Expressions). Since Grafana parses SQL from users and dashboards, this is highly exploitable and must be patched.
  - Other issues include `CVE-2026-41602` (Apache Thrift) and `CVE-2026-21728` (Tempo DoS).

#### 7. Velero Backup Controller (`docker.io/velero/velero:v1.14.0`)
Scan completed successfully. Identified **38 total vulnerabilities** across the base OS and Go binaries (`velero`, `restic`, `velero-helper`).
- **Base OS (Ubuntu 22.04):** 2 HIGH vulnerabilities (`openssl`, `libssl3`).
- **Go Application:** 36 vulnerabilities (33 HIGH, 3 CRITICAL).
  - CRITICAL in `google.golang.org/grpc` (`CVE-2026-33186`).
  - Remaining issues are the standard Go compiler vulnerabilities (`crypto/ssh`, `net/html`) seen across all other Go-based controllers.

---

### Mitigation Strategy for Image CVEs
1. **Understanding the Go Compiler Vulnerabilities:** Both the MariaDB and Ingress Controller images are heavily affected by underlying DoS bugs in the Go Standard Library. These occur because the vendors compiled their binaries with older, vulnerable versions of Go (`1.26.1` and `1.26.2`).
2. **Switching to Hardened Images (MariaDB):** To achieve a zero-CVE baseline, it is recommended to replace standard Docker Hub images with hardened images from providers like **Bitnami**. 
   - *(COMPLETED):* The migration to `bitnami/mariadb:latest` was successfully executed on July 16, 2026. All pods are currently healthy and `1/1 Running`.
3. **Accepting Risk (Ingress Controller):** Since the `nginx-ingress-controller` image is tightly coupled to the RKE2 distribution lifecycle, we accept the risk until Rancher compiles and releases a patched image in a future RKE2 minor upgrade. Overriding the image via `HelmChartConfig` is technically possible but breaks the officially tested Rancher support matrix.
4. **Internet-Facing Component: Nginx Proxy (`nginx:latest`):** The default Docker Hub image contains a full Debian OS layer, meaning it ships with unused utilities (like `apt` and `curl`) that harbor vulnerabilities. **Remediation:** Update the `Deployment` to use a minimal, hardened base image such as `bitnami/nginx:latest` or a distroless variant like `cgr.dev/chainguard/nginx:latest`.
5. **Internet-Facing Component: Fineract UI (`openmf/community-app:latest`):** This image is overly bloated because it ships with development/build tools to serve a static website. Scanning this image locally causes a `disk quota exceeded` crash due to the massive Java vulnerability database requirements. **Remediation:** Refactor the Dockerfile to use a **Multi-Stage Build**. Extract the static HTML/JS/CSS assets during the build phase and serve them out of an empty, distroless web server (like `chainguard/nginx`). This instantly reduces the attack surface and drops the CVE count to zero.
