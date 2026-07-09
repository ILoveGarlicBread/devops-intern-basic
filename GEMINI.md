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

- **Vault K8s Auth Bypass (July 2026):** Solved K8s 1.24+ strict token review rejections in RKE2. Configured Vault with `disable_iss_validation=true` and explicit `token_reviewer_jwt` to allow ESO to sync secrets securely.
- **Dynamic Secret Rotation (Future Option):** Current Vault setup uses static `KV v2`. Future optimization: Implement Vault Dynamic Secret Engines for ephemeral AWS STS tokens and temp MySQL users.
- **Kanister Logical Backups:** Created custom Blueprint using `kando`. Fixed `mysqldump` version mismatches with `--column-statistics=0` and streamed backups via `gzip` directly to S3.
- **Disaster Recovery Tested:** Proven ability to recover from total namespace deletion (Longhorn PV loss) by combining Velero (Infra) and Kanister (Logical data).
- **Blackbox Exporter Enterprise Fixes:** Split generic HTTP probes into multiple `Probe` CRDs. Injected `dnsPolicy: None` and `8.8.8.8` to force external Route53 testing. Used regex to verify HTML body (`[Ff]ineract`, `Grafana`) to prevent false-positive 200 OKs.
- **Fineract Business Metrics:** Deployed custom Go `sql_exporter` for Fineract business metrics (Total Clients/Loans) with declarative ConfigMap SQL queries.
- **HTTPS/TLS:** Cert-Manager deployed with `letsencrypt-prod` ClusterIssuer. Fully functional for all ingresses.
- **Vault TLS & Kube-bench Security Hardening:** Secured Vault communication via internal TLS and fixed K8s 1.24+ token review rejections. Executed CIS benchmark scans (`kube-bench`) and engineered Ansible playbooks to harden RKE2 Kubelet configurations (disabling anonymous auth, enforcing Webhook auth, and restricting cryptographic ciphers) across all cluster nodes.
- **Pod Security Admissions:** Enforced Kubernetes `restricted` Pod Security standards on the `default` namespace to block privileged containers and host mounts.

## 4. Future Security Roadmap
- [ ] **Network Policies (Micro-segmentation):** Implement default-deny rules across all namespaces.
- [ ] **Dynamic Secret Rotation:** Upgrade Vault from static KV v2 to Dynamic Engines for MySQL and AWS STS.
- [ ] **RBAC Audit & Image Scanning:** Enforce least privilege (remove wildcards) and integrate image provenance/scanning (Trivy/Kyverno).
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
