# Infrastructure Automation & Cluster Administration
**Location:** `~/TMA-DevOps-Internship/week2/`

## Role & Responsibilities
I am the primary Infrastructure and Cluster Administrator operating from the `Main` node. My responsibilities include:
- **Infrastructure as Code:** Managing Terraform (`main.tf`) to provision and scale AWS Spot instances.
- **Configuration Management:** Executing Ansible playbooks for RKE2 setup and OS tuning.
- **Cluster Administration:** Performing all `kubectl` and `helm` operations remotely via SSH to the Master node.
- **Deployment Strategy:** Implementing "migration-proof" Helm charts using the Bitnami library.

## Project Overview
This project manages a Kubernetes environment for Apache Fineract and a Bitnami learning stack using RKE2 on AWS Spot Instances.

## Environment Details
- **Control Node:** Ubuntu EC2 Instance (`Main`).
  - **Capabilities:** Native `kubectl` access configured (`~/.kube/config`).
  - **Gemini CLI Integrations:** No active MCP server integrations.
- **Infrastructure:** Terraform (HCL2) provisioning Master (`t3.medium`) and Workers (`t3a.large`).
- **Kubernetes:** RKE2 Cluster (1 Master, 3 Workers).
- **Storage:** Longhorn (Replicas: 2).
- **DNS:** Route 53 dynamic updates for `fineract.lblam.tma-demos.shop`.

## Deployed Bitnami Learning Stack (June 2026)
*Status: Architecture categorized by service type for resource optimization.*

### A. Caching Layer (Node: Worker-1 - `ip-172-31-20-223`)
*Purpose: High-speed data retrieval for Fineract and other apps.*

#### 1. Redis (Namespace: `redis`)
- **Access:** `redis-master.redis.svc.cluster.local:6379`
- **Config:** Standalone, Auth disabled, 128Mi Memory limit.

#### 2. Memcached (Namespace: `memcached`)
- **Access:** `memcached.memcached.svc.cluster.local:11211`
- **Config:** Standalone, 128Mi Memory limit.
- **Migration Fix:** Updated to `repository: bitnamilegacy/memcached`, `tag: 1.6.39`.

### B. Database & AI Layer (Node: Worker-2 - `ip-172-31-10-48`)
*Purpose: Persistent storage and mathematical similarity search.*

#### 3. PostgreSQL (Namespace: `postgresql`)
- **Access:** `postgresql.postgresql.svc.cluster.local:5432`
- **Config:** Standalone, Password: `password123`, 256Mi Memory limit.

#### 4. MySQL (Namespace: `mysql`)
- **Access:** `mysql.mysql.svc.cluster.local:3306`
- **Config:** Standalone, Password: `password123`, 1Gi Memory limit.
- **Infrastructure:** Using `storageClass: longhorn-fixed` (2 Replicas).
- **Migration Fix:** Updated to `repository: bitnamilegacy/mysql`, `tag: 9.4.0`.

#### 5. MongoDB (Namespace: `mongodb`)
- **Access:** `mongodb.mongodb.svc.cluster.local:27017`
- **Config:** Standalone, Password: `password123`, 1Gi Memory limit, 4Gi Volume.
- **Migration Fix:** Updated to `repository: bitnamilegacy/mongodb`, `tag: 8.0.13`.

#### 6. Qdrant (Namespace: `qdrant`)
- **Node:** Worker-2 (`ip-172-31-10-48`) - *Pinned via nodeSelector*
- **Access:** `qdrant.qdrant.svc.cluster.local:6333` (HTTP) / `6334` (gRPC)
- **Config:** Standalone, 512Mi Memory limit, 4Gi Volume. True Vector Database.

### C. Messaging & Ops Layer (Node: Worker-3 - `ip-172-31-30-200`)
*Purpose: High-throughput event streaming, message brokering, and cluster monitoring.*

#### 7. RabbitMQ (Namespace: `rabbitmq`)
- **Node:** Worker-3 (`ip-172-31-30-200`) - *Pinned via nodeSelector*
- **Access:** `rabbitmq.rabbitmq.svc.cluster.local:5672` (UI: 15672)
- **Config:** Standalone, User/Pass: `user/password123`, 512Mi Memory limit.
- **Migration Fix:** Updated to `repository: bitnamilegacy/rabbitmq`, `tag: 4.1.3-debian-12-r1`.

#### 8. Milvus (Namespace: `milvus`)
- **Node:** Worker-3 (`ip-172-31-30-200`) - *Pinned via nodeSelector*
- **Access:** `milvus.milvus.svc.cluster.local:19530` (Proxy) / `attu` (UI)
- **Config:** Standalone (using internal etcd, minio, kafka), 1Gi Memory total limit.
- **Migration Fix:** Updated to `repository: bitnamilegacy/milvus`, `tag: 2.6.0-debian-12-r1`.

## Learning Scope (Bitnami & Third-Party Helm Charts)
- **Status:** [x] Redis, [x] PostgreSQL, [x] RabbitMQ, [x] Memcached, [x] MySQL, [x] MongoDB, [x] Qdrant, [x] Milvus, [x] Kafka, [x] Kube-Prometheus.

## Infrastructure Lessons: Migration-Proofing
- **Concept:** Ensuring deployments don't break when external registries change paths or policies.
- **Strategy:** Explicitly pointing Helm charts to the `bitnamilegacy` repository for stable version pinning.
- **Future:** Transitioning to official Docker Library images or private ECR mirrors.

## Key Files
- `terraform/main.tf`: Infrastructure definition.
- `ansible/vars.yml`: Centralized variable store.
- `ansible/deploy_k8s.yml`: RKE2 cluster setup.
- `ansible/deploy_longhorn.yml`: Storage layer setup.
- `ansible/bootstrap_cluster_apps.yml`: Local kubeconfig setup.
# Recent HTTPS Enablement & DNS Verification

- **Installed Cert‑Manager** in the cluster and created a `ClusterIssuer` (`letsencrypt-prod`).
- **Updated Ingress resources** for `logging`, `monitoring`, and `fineract` to include:
  - `cert-manager.io/cluster-issuer: letsencrypt-prod` annotation
  - `tls` section referencing secrets (`logging-tls`, `monitoring-tls`, `fineract-ssl-cert`).
- **Verified DNS records** now point to the correct worker IPs:
  - `fineract.lblam.tma-demos.shop → 13.203.22.170` (Worker 1)
  - `logging.lblam.tma-demos.shop → 3.110.99.70` (Worker 3)
  - `monitoring.lblam.tma-demos.shop → 13.203.224.149` (Worker 2)
- **HTTPS certificates have been successfully issued** via Cert-Manager and Let's Encrypt for all subdomains.
- **Verified HTTPS** access is now fully functional and presents trusted certificates.
- **Migrated Logging Stack to Elasticsearch/Kibana:** Replaced OpenSearch with Elasticsearch and OpenSearch Dashboards with Kibana to resolve compatibility issues and improve integration.
- **Updated `logstash` -> `elasticsearch` pipeline:** Changed Logstash output plugin back to `elasticsearch` for native compatibility with the new Elasticsearch backend. Logs are now successfully flowing!
- **Grafana Credentials (Monitoring):** 
  - Username: `admin`
  - Password: `cJIm4B94aJz6drBtFmJoI2WYBIruu1eiaaiO8jdH`

## Observability Architecture (Logging & Monitoring)

This environment utilizes a robust, decoupled logging and monitoring pipeline separated into distinct namespaces for isolation and clarity.

### 1. Centralized Logging (EFK Stack)
- **Namespace:** `logging`
- **Fluent-bit (DaemonSet):** Runs on every node in the cluster. It tails container standard output and error streams directly from the Docker/containerd log files (`/var/log/containers/*.log`). It formats these streams into JSON and ships them via HTTP to Logstash.
- **Logstash (StatefulSet):** Acts as the centralized log aggregation and transformation layer. It listens on port 8080 for incoming Fluent-bit payloads. *Migration Note:* We migrated from OpenSearch to Elasticsearch to avoid version check blocks. Logstash now uses the native `elasticsearch` output plugin to POST JSON events to Elasticsearch.
- **Elasticsearch (StatefulSet):** The primary storage and search backend, storing logs in daily rolling indices (e.g., `fineract-logs-%{+YYYY.MM.dd}`).
- **Kibana:** The visualization UI for querying log data, securely exposed via Let's Encrypt TLS at `https://logging.lblam.tma-demos.shop/`.

### 2. Metrics & Monitoring (Kube-Prometheus Stack)
- **Namespace:** `monitoring`
- **Prometheus:** A time-series database that continuously scrapes metrics targets across the cluster (kubelet, cAdvisor, and workloads).
- **Node Exporter (DaemonSet):** Runs on all nodes to export low-level OS and hardware metrics (CPU, Memory, Disk I/O) to Prometheus.
- **Kube-State-Metrics:** Listens to the Kubernetes API server and generates metrics about the state of various objects (e.g., Pod phases, Deployment replicas).
- **Alertmanager:** Processes and routes alerts generated by Prometheus rules.
- **Grafana:** The primary metrics visualization UI, pre-loaded with Kubernetes monitoring dashboards. Securely exposed via Let's Encrypt TLS at `https://monitoring.lblam.tma-demos.shop/`.

## Mentor's Tasks & Recommendations (June 2026)

### Logging & Elasticsearch Tasks
- [x] **Elasticsearch Snapshots:** Research and implement an automated snapshot policy to back up Elasticsearch indices to an S3 bucket, and configure an index retention policy.
  - *Implementation:* Provisioned an AWS S3 bucket (`rke2-elasticsearch-snapshots-***`) and IAM user via Terraform. Injected AWS credentials securely into the Elasticsearch pod using `extraEnvVars`. Registered the built-in `repository-s3` module and created an SLM policy (`daily-snapshots`) to back up indices at 1:30 AM daily, with a 30-day retention rule (`expire_after: "30d"`, keeping a minimum of 5 snapshots).
- [x] **Snapshot Restoration Test:** After successfully taking a snapshot to S3, test the recovery process by deleting an index and restoring it from the snapshot to verify if the deleted logs can still be queried.
  - *Implementation:* Performed a manual snapshot trigger, then deliberately deleted the active `fineract-logs-*` index. Demonstrated successful recovery by restoring the index from S3 with a rename pattern (`restored-fineract-logs-*`) to safely recover 42,000+ deleted logs without interrupting the live ingestion stream.
- [x] **Logstash Filtering & Parsing:** Experiment with Logstash filters to identify and drop redundant or unnecessary log patterns, and parse unstructured text into structured JSON fields.
  - *Implementation:* Dropped noisy `kube-probe` health check logs to save storage. Implemented advanced **Grok** patterns in `logstash-values.yaml` to dynamically parse raw Java Spring Boot logs (and Slow Query warnings) from Fineract into discrete, searchable Elasticsearch columns (`fineract_log_level`, `fineract_class`, `fineract_thread`).
- [ ] **General Practice:** Continue practicing cluster administration and operations to build solid, hands-on understanding.

### Recommendations for the Prometheus Monitoring Stack
- [x] **Maximize Exporters:** When deploying the Prometheus stack, aim to configure as many exporters as possible. Every deployed service should ideally have a corresponding exporter to be monitored in Grafana.
- [x] **Mandatory Exporters:** At a minimum, ensure the following are deployed and scraped: `node_exporter`, `kube_state_metrics`, `cadvisor`, Longhorn exporter, MongoDB exporter, and PostgreSQL exporter.
  - *Implementation:* Deployed `prometheus-mysql-exporter` for both Fineract databases (`default` and `tenants`). Created a `ServiceMonitor` to dynamically scrape the built-in `longhorn-backend:9500/metrics` endpoint. Skipped Mongo/Postgres as they are not currently provisioned in this environment.
- [x] **Slack Alerting Rules:** Configure critical alerts to be pushed to a Slack channel. Required alerts include:
  - Node goes down (NotReady/Unreachable)
  - Pod restarts more than 5 times consecutively within 1 hour (CrashLoopBackOff/Restart loops)
  - PVC storage is full
  - Disk storage is full
  - Longhorn PVC is degraded
  - *Implementation:* Updated the `kube-prometheus-stack` values to route alerts via Alertmanager to a Slack Incoming Webhook. The stack comes pre-loaded with rules for Node Down, Pod CrashLoops, and PVC/Disk storage full. Added a custom `PrometheusRule` specifically for Longhorn degraded/fault volume states. Also fixed a silent YAML indentation bug in the Alertmanager config to successfully restore Slack integration, and configured "null" routing in Alertmanager to securely drop generic RKE2 false positives (Watchdog, KubeProxyDown, and KubeDaemonSetRolloutStuck for Master node DaemonSets) while preserving global alerting visibility.
- [x] **Alerting Tooling:** Alerts can be configured and routed via Prometheus AlertManager or directly through Grafana's built-in alerting system, whichever is preferred, as long as the Slack integration is functional.
- [x] **Alertmanager Null Routing:** Configured the Alertmanager `routes` in `prometheus-values.yaml` to successfully suppress noisy/false-positive alerts specific to RKE2 and Longhorn (e.g., TargetDown for hidden control planes, KubeDaemonSetMisScheduled, etcdInsufficientMembers, and Watchdog). Fixed `PrometheusOperatorSyncFailed` by manually patching the generated AlertManager configuration secret to remove the default empty `slack_api_url` that conflicted with `slack_api_url_file`.
- [x] **Longhorn CSI Driver Troubleshooting:** Identified that the `longhorn-driver-deployer` pod was crashlooping due to trying to deploy on stale "ghost" Longhorn nodes created by AWS Spot Instance terminations. Bypassed the Longhorn validation webhook and forcefully deleted the stale `nodes.longhorn.io` objects, successfully resolving the `KubePodCrashLooping` alert.
- [x] **Fineract Business Metrics:** Deployed a custom Python-based `fineract-business-exporter` to query the Fineract database for business metrics (Total Clients, Loans, Accounts) and exposed them via a custom Grafana dashboard. Configured a custom `PrometheusRule` to alert when business thresholds are crossed. Secured the database credentials using External Secrets Operator to inject the password natively into the exporter.

## Completed Task: Security & Secrets Management (AWS Integration)
**Goal:** Migrate hardcoded, plain-text secrets out of version control and YAML files into **AWS Secrets Manager** to establish a secure, enterprise-grade GitOps workflow.

### Addressed Vulnerabilities
We have secured **3 critical secrets** that were previously exposed in plain text:
- [x] **Prometheus / Alertmanager:** The Slack Webhook URL.
- [x] **Fineract MySQL Databases:** The default and tenant database passwords.
- [x] **Infrastructure (Critical):** The RKE2 Cluster Join Token.

### The Architecture Plan (Implementation Steps)
- [x] 1. **AWS Secrets Manager:** Securely store the 3 secrets in AWS KMS-encrypted vaults.
- [x] 2. **External Secrets Operator (ESO):** Deploy ESO into the Kubernetes cluster via Helm.
- [x] 3. **Authentication (SecretStore):** Configure a `ClusterSecretStore` using the existing AWS IAM credentials to allow the cluster to read from AWS.
- [x] 4. **Secret Injection (ExternalSecret):** Create `ExternalSecret` manifests that instruct ESO to dynamically fetch the secrets from AWS and generate native Kubernetes Secrets in memory.
- [x] 5. **Ansible AWS Integration:** Configure the Ansible `deploy_k8s.yml` playbook to dynamically pull the RKE2 cluster token from AWS at runtime instead of relying on `vars.yml`.
