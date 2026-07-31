# ⚠️ TEMPORARY CONTEXT FOR NEXT AGENT SESSION (July 2026) ⚠️
*Worker nodes have stabilized after a Spot Instance rotation. Storage detach errors were resolved.*

**Current State & Next Steps for the AI:**
1. **Nginx Ingress CVE Patching:** Custom image built and loaded to master node. Needs to be distributed to worker nodes (SCP or registry) once they stabilize.
2. **Kanister Backups:** Fixed the network timeout issue in the logical backup blueprint by migrating to `mysql-sidecar:0.118.0` and fixing `kando` syntax. Backups run perfectly. **UPDATE (July 2026):** Successfully used `.sql.gz` logical backups to restore Fineract data to a fresh cluster without corrupting GitOps state.
3. **CI/CD (ArgoCD):** Shifted focus to GitOps. Drafted ArgoCD deployment guides (`ARGOCD_GUIDE.md`) and custom Helm values. **UPDATE (July 2026):** ArgoCD successfully deployed. Next steps: Configure the repository, adopt Fineract (brownfield), and deploy Cert-Manager / Monitoring via the App of Apps pattern.
4. **AI Agent Integration:** Configured an AI agent using the OpenAI SDK. **UPDATE (July 2026):** Abandoned AWS Bedrock due to marketplace fraud locks. Migrated the agent to connect natively to OpenAI `gpt-4o-mini`, pulling the API key securely from Vault via External Secrets. Deployed successfully via ArgoCD, with an automated CI/CD pipeline successfully updating the image tag.
5. **Jenkins CI/CD:** Abandoned AWS CodeBuild due to a strict anti-fraud 0.0 concurrent build limit on the account (and Lambda's inability to run Docker-in-Docker). Pivoted to deploying Jenkins directly inside the Kubernetes cluster via an ArgoCD Umbrella Chart. Successfully orchestrated a Dockerless Kaniko pipeline to build and push images natively to ECR using instance IAM profiles.
---

# Infrastructure Automation & Cluster Administration
**Location:** `~/TMA-DevOps-Lam-Internship/advanced/`

## 1. Environment Overview
This project manages a Kubernetes environment for Apache Fineract on AWS Spot Instances using RKE2.

- **Infrastructure:** Terraform (`main.tf`) provisions Master (`t3.medium`) and Workers (`t3a.large`).
- **Kubernetes:** RKE2 Cluster (1 Master, 3 Workers). `~/.kube/config` on `Main` EC2 node.
- **DNS:** Route 53 dynamic updates.
  - `fineract.lblam.tma-demos.shop`
  - `monitoring.lblam.tma-demos.shop`
- **Local Access (Firewall Bypass):**
  ```bash
  ssh -L 3000:localhost:3000 -L 8080:localhost:8080 ubuntu@<MAIN_NODE_IP>
  kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80 &
  kubectl port-forward -n fineract svc/fineract-nginx-service 8080:3000 &
  ```

## 2. Current Live Architecture

### A. Core Applications (`fineract`)
- **Apache Fineract:** Core banking system. Uses `fineract-default-0` and `fineract-tenants-0` databases (MySQL).
- **Ingress:** `fineract.lblam.tma-demos.shop` (TLS via Cert-Manager).

### B. Security & Secrets Management (`vault`, `external-secrets`)
- **HashiCorp Vault (HA):** 3 replicas with Integrated Raft Storage. Auto-unsealed via AWS KMS.
- **External Secrets Operator (ESO):** Replaced AWS Secrets Manager. Authenticates to Vault via K8s Auth (`eso-role`). Injects Fineract DB passwords, AWS S3 keys, and Slack webhooks natively into cluster memory.

### C. Backup & Disaster Recovery (`velero`, `kanister`, `longhorn-system`)
- **Longhorn:** Distributed block storage (2 replicas).
- **Velero:** Infrastructure/snapshot-based cluster backups to AWS S3.
- **Kanister:** Application-level logical DB backups (mysqldump). Custom blueprint streams compressed SQL dumps directly to S3 without local disk usage.

### D. Observability & Monitoring (`monitoring`, `logging`)
- **Loki Stack:** OpenTelemetry (DaemonSet + Gateway) collects/transforms logs, forwards to Loki (Distributed). Grafana queries `http://loki-read.logging.svc.cluster.local:3100`.
- **Prometheus Stack:** Scrapes `node_exporter`, `kube-state-metrics`, `cadvisor`, Fineract DBs (`mysql-exporter`), Longhorn, and custom `fineract-business-exporter`.
- **Alertmanager:** Routes critical alerts (CrashLoop, PVC Full, Node Down) to Slack webhook (fetched from Vault). Null-routes RKE2 ghost alerts.

## 3. Completed Milestones & Technical Lessons

- **Vault Zero-Trust Ephemeral Auth (July 2026):** Upgraded Vault Kubernetes Auth from using a static ServiceAccount `token_reviewer_jwt` to purely zero-trust. Vault now dynamically utilizes its own ephemeral pod token (`/var/run/secrets/kubernetes.io/serviceaccount/token`) to authenticate against the Kubernetes TokenReview API, completely eliminating the need for permanent secrets and preventing token expiration lockouts in K8s 1.24+.
- **Dynamic Secret Rotation (Future Option):** Current Vault setup uses static `KV v2`. Future optimization: Implement Vault Dynamic Secret Engines for ephemeral AWS STS tokens and temp MySQL users.
- **Kanister Logical Backups:** Created custom Blueprint using `kando`. Fixed `mysqldump` version mismatches with `--column-statistics=0` and streamed backups via `gzip` directly to S3.
- **Disaster Recovery Tested:** Proven ability to recover from total namespace deletion (Longhorn PV loss) by combining Velero (Infra) and Kanister (Logical data).
- **Blackbox Exporter Enterprise Fixes:** Split generic HTTP probes into multiple `Probe` CRDs. Injected `dnsPolicy: None` and `8.8.8.8` to force external Route53 testing. Used regex to verify HTML body (`[Ff]ineract`, `Grafana`) to prevent false-positive 200 OKs.
- **Fineract Business Metrics:** Deployed custom Go `sql_exporter` for Fineract business metrics (Total Clients/Loans) with declarative ConfigMap SQL queries.
- **HTTPS/TLS:** Cert-Manager deployed with `letsencrypt-prod` ClusterIssuer. Fully functional for all ingresses.
- **Vault TLS & Kube-bench Security Hardening:** Secured Vault communication via internal TLS and fixed K8s 1.24+ token review rejections. Executed CIS benchmark scans (`kube-bench`) and engineered Ansible playbooks to harden RKE2 Kubelet configurations (disabling anonymous auth, enforcing Webhook auth, and restricting cryptographic ciphers) across all cluster nodes.
- **Pod Security Admissions:** Enforced Kubernetes `restricted` Pod Security standards on the `default` namespace to block privileged containers and host mounts.
- **Trivy Vulnerability & Misconfiguration Remediation (July 2026):** Evaluated Trivy for live cluster CVE scanning but shifted to static Helm auditing (`trivy config`) due to OOM/disk limits on the `t3.medium` nodes. Successfully remediated all KSV misconfigurations (dropped capabilities, enforced `readOnlyRootFilesystem: true` using `emptyDir` mounts for `/var/cache/nginx` and `/tmp`, and enabled `runAsNonRoot: true`). Also successfully mitigated 15 HIGH/CRITICAL CVEs in `mariadb:11.4` by migrating to `bitnami/mariadb:latest`. A significant lesson was resolving `Permission denied` startup errors caused by the new non-root user (`runAsUser: 10001`) trying to access the legacy root-created StatefulSet databases—solved by injecting `fsGroup: 10001` into the Pod Security Context to trigger automatic Kubernetes volume recursive chown on mount.
- **Fineract Multi-Tenant DB Decryption Debugging (July 2026):** Resolved a complex `CrashLoopBackOff` in `fineract-backend` after upgrading the databases via External Secrets Operator (ESO). Discovered that the `fineract_tenants` database contains a `tenant_server_connections` table with an encrypted `schema_password` for the `fineract_default` database, as well as a `master_password_hash`. When ESO rotated the master secret to a new value (`fineractnew`), Fineract failed to decrypt the legacy AES payload. The permanent fix involved:
  1. Running Fineract's `DatabasePasswordEncryptor` Java utility manually inside a pod to generate a new AES payload (`zHsH...`) and BCrypt hash (`$2a...`) using the new `fineractnew` password.
  2. Updating the `fineract-db-sync` CronJob to automatically execute a `mysql` query that overwrites both `schema_password` and `master_password_hash` in the database whenever the Vault secret changes.
  3. Injecting `FINERACT_TENANT_MASTERPASSWORD` into the Fineract deployment environment variables. Without this variable, Fineract defaults to verifying the BCrypt hash against the hardcoded string `"fineract"`, which causes a `java.lang.IllegalArgumentException: Invalid master password` when using a custom password.
- **Database Password Separation (July 2026):** Refactored the shared `password` key in Vault into three distinct credentials (`tenantDbPassword`, `defaultDbPassword`, `fineractMasterPassword`) to strictly enforce the principle of least privilege across Fineract's database routing architecture. Implemented manual rotation documentation due to Fineract's Java-based AES encryption requirements.
- **Kanister Blueprint Network Fix (July 2026):** Diagnosed 18 historical backup failures. The default blueprint tried to `microdnf install mysql`, which timed out in the restricted environment. Completely rewrote the blueprint to use `ghcr.io/kanisterio/mysql-sidecar:0.118.0` (pre-installed tools) and corrected `kando` CLI flag syntax, successfully resuming logical S3 backups.
- **CI/CD GitOps Architecture Design (July 2026):** Designed the architecture for migrating from manual Helm deployments to a pull-based ArgoCD GitOps model. Documented the App of Apps pattern, CI/CD segregation, and Brownfield cluster adoption methodologies. Drafted initial ArgoCD installation manifests (staged, awaiting node stability).
- **GitOps ArgoCD Migration & Fineract Restoration (July 2026):** Restored Fineract data logically via Kanister `.sql.gz` dumps from S3 to prevent Kubernetes manifest drift. Diagnosed and fixed a CORS Preflight/Mixed-Content error in the Fineract UI proxy that blocked login by updating the Helm templates to return HTTPS. Successfully deployed ArgoCD via Helm and staged for brownfield cluster adoption.
- **AI Agent AWS Bedrock Integration (July 2026):** Deployed a tool-calling AI assistant (`ai-agent`) to the cluster. Discovered that the agent's custom OpenAI-based `Runner` framework was incompatible with the raw Anthropic SDK. To circumvent this without rewriting the core framework, we tested two solutions: 1) Using the Bedrock Mantle endpoint to natively query `google.gemma-3-4b-it` using dynamic IAM tokens, and 2) Deploying a local `LiteLLM` proxy within the pod's entrypoint to perform real-time translation of OpenAI tool schemas into Anthropic schemas for `claude-3-haiku`. We ultimately configured and staged the `LiteLLM` architecture, leaving it scaled to `0` pending an AWS Support quota approval for 3rd-party model access.
- **AI Agent Native OpenAI Migration (July 2026):** Abandoned the Bedrock approach entirely due to unyielding AWS marketplace fraud locks on the account. Successfully migrated the `main.py` script to use the native `AsyncOpenAI` client targeting `gpt-4o-mini`. Stored the OpenAI API key in HashiCorp Vault and used External Secrets Operator to inject it into the pod. Fixed a 401 Authentication Error caused by ArgoCD failing to automatically rollout the pod when the `ConfigMap` changed.
- **CodeBuild Pivot & Jenkins GitOps Deployment (July 2026):** Attempted to build the AI Agent Docker image using AWS CodeBuild, but was blocked by a hard `0.0` concurrent build Service Quota (another anti-fraud lock). While AWS Support approved an increase for the `Linux Lambda/4GB` environment, discovered that Lambda CodeBuild environments fundamentally do not support Privileged Mode (required for `docker build`). Pivoted to deploying Jenkins natively in the cluster. Used an "Umbrella Chart" (`Chart.yaml` dependencies) to manage Jenkins via ArgoCD. Resolved a `VersionCompatibilityException` in the Jenkins `init` container by upgrading the Jenkins controller image tag to `latest-jdk17` to satisfy the minimum requirements of the newest plugins.
- **Dockerless Kubernetes CI/CD via Kaniko (July 2026):** Replaced standard `docker build` within the Jenkins pipeline with a Google Kaniko sidecar to securely build images inside the RKE2 containerd environment without requiring root access or a Docker daemon. Configured Kaniko to dynamically inherit the EC2 worker node's IAM profile (`rke2-worker-route53-role` + `AmazonEC2ContainerRegistryPowerUser`) to securely push to AWS ECR without using static AWS credentials.
- **GitOps SSH Authentication Fixes (July 2026):** Resolved Jenkins SSH `git push` failures to AWS CodeCommit by explicitly setting `export GIT_SSH_COMMAND="ssh -i \${SSH_KEY} -o StrictHostKeyChecking=no -o User=\${SSH_USERNAME}"`, forcing Git to authenticate using the AWS IAM Key ID instead of the default container username.
- **Spot Instance Multi-Attach Recovery (July 2026):** Successfully diagnosed and recovered from Longhorn PVC Multi-Attach errors on `vault-1` and `loki-write-1` following an AWS Spot instance rotation. Removed stale pods and PVCs, relying on Raft consensus (Vault) and stateless design (Loki WAL) to automatically provision fresh PVCs without data loss.
- **RKE2 Nginx Ingress Metrics (July 2026):** Enabled missing Nginx Ingress metrics by creating a custom `HelmChartConfig` for the native `rke2-ingress-nginx` controller, configuring it to automatically generate a ServiceMonitor with the `release: prometheus-stack` label to feed data into Grafana dashboards.
- **DNS Architecture Optimization (July 2026):** Refactored Route53 DNS management by converting `monitoring.lblam.tma-demos.shop` from an independently managed A record into a CNAME pointing to `fineract.lblam.tma-demos.shop`, eliminating redundant dynamic DNS bash scripts inside Terraform worker node definitions. Also added a CNAME for Jenkins.
- **Jenkins Ingress TLS (July 2026):** Configured the Jenkins Helm chart to automatically utilize the existing `letsencrypt-prod` Cert-Manager ClusterIssuer to dynamically provision TLS certificates for the Jenkins UI.
- **GitOps Codebase Consolidation (July 2026):** Reorganized the GitOps folder structure by combining `argocd-values.yaml` and `jenkins-values.yaml` into a unified `ci-cd` directory, streamlining application value paths.
- **FastMCP & LLM Hallucination Prevention (July 2026):** Deployed a Model Context Protocol (MCP) server bridging Fineract to an OpenAI agent. Diagnosed and fixed an SSE connection failure caused by a trailing slash in the `MCP_SERVER_URL` triggering a `307 Temporary Redirect` (which `httpx-sse` inherently drops), and bypassed a `421 Misdirected Request` by disabling FastMCP's DNS rebinding protection for internal cluster traffic. Refactored the tool return signatures to transform noisy raw Fineract JSON payloads into strictly mapped Python dictionaries, successfully preventing `gpt-4o-mini` from hallucinating cross-client account ownership.
- **GitOps Mono vs Polyrepo Architecture (July 2026):** Solidified the enterprise GitOps strategy by physically separating Application source code from Kubernetes manifests (Polyrepo). Acknowledged the inherent debugging friction of CI/CD Kaniko image build wait times compared to `ConfigMap`-based live reloads, reinforcing the decision to map deployment environments (Dev/Staging/Prod) via directory structures on a unified `main` branch rather than using fragile divergent Git branches.
- **Kaniko Build Optimization & Caching (July 2026):** Implemented parallel Jenkins pipeline stages for the `ai-agent` and `mcp-server` Docker images. Resolved EC2 CPU contention (t3a.large) that was halving parallel build speeds by injecting Kaniko Layer Caching (`--cache=true --cache-repo=...`), dramatically reducing subsequent build times by avoiding redundant PyTorch library compilations.
- **Micro-segmentation Network Policy Debugging (July 2026):** Successfully diagnosed an HTTP timeout between the newly decoupled `ai-agent-mcp` pod and the Fineract backend. Identified that a recently applied `default-deny` Network Policy physically blocked the cross-namespace traffic. Re-established connectivity by explicitly whitelisting ingress from the `ai-agent` namespace to the `fineract-backend` pod.
- **RAG Qdrant Integration & Token Optimization (July 2026):** Decoupled the AI Agent into a frontend UI pod and a backend FastMCP server to support Qdrant vector databases for Retrieval-Augmented Generation (RAG) of Bank Policies. Implemented a highly token-efficient Sliding Window Memory algorithm inside the Gradio UI to preserve conversational context without exhausting LLM token limits or spiking OpenAI API costs.

## 4. Future Security Roadmap
- [ ] **Network Policies (Micro-segmentation):** Implement default-deny rules across all namespaces.
- [ ] **Dynamic Secret Rotation:** Upgrade Vault from static KV v2 to Dynamic Engines for MySQL and AWS STS.
- [ ] **RBAC Audit & Image Scanning:** Enforce least privilege (remove wildcards). Offload Trivy image CVE scanning to a CI/CD pipeline (due to cluster resource constraints), and patch existing Fineract Helm chart misconfigurations.
## 4. Decommissioned & Legacy Systems

### A. EFK Stack (Legacy Centralized Logging)
*Kept for historical context. Removed because Elasticsearch consumed too much RAM (3GB+) for cluster capacity.*
- **Fluent-bit:** Tailed `/var/log/containers/*.log`, converted to JSON.
- **Logstash:** Port 8080. Used complex **Grok** patterns to dynamically parse raw Java Spring Boot logs and Slow Query warnings into discrete Elasticsearch columns (`fineract_log_level`, `fineract_class`, `fineract_thread`). Dropped noisy `kube-probe` logs.
- **Elasticsearch:** Stored logs in rolling indices. Configured automated S3 snapshots (SLM policy) and successfully tested live index recovery. 
- **Kibana:** UI visualization.

### B. Past Learning Exercises (`randomcharts/`)
*Helm values exist in repo, but pods are NOT currently deployed.*
- Redis, Memcached, PostgreSQL, MySQL, MongoDB, Qdrant, RabbitMQ, Milvus, Kafka.
- **Infrastructure Lesson:** Pinned Helm charts to `bitnamilegacy` repository to prevent breaking changes when external registries alter policies.

## 5. Key Files & Useful Queries
- `terraform/main.tf`: AWS infrastructure (EC2, KMS, S3 buckets).
- `ansible/deploy_k8s.yml`: RKE2 cluster deployment.
- `advanced/security/VAULT_PRODUCTION_GUIDE.md`: Vault disaster recovery guide.

**Loki LogQL Queries (Grafana):**
- Backend: `{service_name="fineract-backend"}`
- Database: `{service_name="fineract-default"} |= ""`
- Proxy/UI: `{service_name="fineract-nginx-proxy"}` or `fineract-ui`
