# Grafana Tempo Distributed Tracing Guide

This guide documents the implementation of distributed tracing in the Kubernetes cluster using Grafana Tempo, OpenTelemetry, and S3 backend storage.

---

## 1. Overview & Architecture

Distributed tracing tracks requests end-to-end across multiple microservices (Ingress &rarr; UI &rarr; AI Agent &rarr; FastMCP &rarr; Fineract &rarr; MySQL).

```mermaid
flowchart LR
    subgraph Microservices
        App[Applications / Java Agent / Python OTel]
    end

    subgraph Collection
        OTel[OpenTelemetry Gateway]
    end

    subgraph Storage
        Tempo[Grafana Tempo Single-Binary]
        S3[(AWS S3: rke2-cluster-backups)]
        Longhorn[(Longhorn PVC 5Gi)]
    end

    subgraph Visualization
        Grafana[Grafana Dashboards]
    end

    App -->|OTLP 4317 gRPC / 4318 HTTP| OTel
    OTel -->|Forward Traces OTLP| Tempo
    Tempo -->|Write WAL / Blocks Cache| Longhorn
    Tempo -->|Flush Long-Term Blocks| S3
    Grafana -->|Query Traces| Tempo
    Grafana -.->|Trace-to-Logs Link| Loki[Loki Logs]
```

---

## 2. Components Configured

### A. External Secrets (S3 Credentials)
**File:** `advanced/gitops/manifests/secrets/external-secrets.yaml`
Creates `tempo-s3-secret` in the `monitoring` namespace by pulling `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` from Vault (`production-vault` / `s3-backup-keys`).

### B. Tempo Helm Values
**File:** `advanced/gitops/helm-values/monitoring/tempo-values.yaml`
* **Mode:** Single-binary mode (resource-efficient for `t3a.large` nodes).
* **Storage Backend:** AWS S3 (`rke2-cluster-backups-...` bucket) + Longhorn PVC (`5Gi`) for WAL and local block cache.
* **Receivers:** OTLP gRPC (`0.0.0.0:4317`) and OTLP HTTP (`0.0.0.0:4318`).
* **Metrics Generator:** Enabled `metricsGenerator` with `service_graphs`, `span_metrics`, and `local_blocks` processors to support TraceQL metric queries and Grafana trace rate calculations.

### C. Tempo ArgoCD Application
**File:** `advanced/gitops/applications/tempo-app.yaml`
* **Helm Chart:** `grafana/tempo` (version `1.24.4`).
* **Namespace:** `monitoring`.
* **Sync Policy:** Automated sync with prune and self-heal.

### D. Grafana Datasource & Log-Trace Correlation
**File:** `advanced/gitops/helm-values/monitoring/prometheus-values.yaml`
* Added **Tempo** datasource (`http://tempo.monitoring.svc.cluster.local:3200`).
* Added **Derived Fields** in Loki datasource to parse `traceID` or `trace_id` regex and provide direct one-click navigation from Loki log lines into Tempo trace waterfalls.

---

## 3. Deployment Commands & Verification

### Step 1: Deploy ExternalSecret & ArgoCD Application
```bash
# Apply the new external secrets and tempo application
kubectl apply -f advanced/gitops/manifests/secrets/external-secrets.yaml
kubectl apply -f advanced/gitops/applications/tempo-app.yaml
```

### Step 2: Verify S3 Secret Sync
```bash
kubectl get externalsecret tempo-s3-credentials-ext -n monitoring
kubectl get secret tempo-s3-secret -n monitoring
```

### E. OpenTelemetry Gateway Traces Pipeline
**File:** `advanced/gitops/helm-values/logging/otel-gateway-values.yaml`
Configured the `otlp/tempo` exporter and enabled the `traces` pipeline:
```yaml
exporters:
  otlp/tempo:
    endpoint: "tempo.monitoring.svc.cluster.local:4317"
    tls:
      insecure: true

service:
  pipelines:
    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [otlphttp]
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [otlp/tempo]
```

---

## 3. Deployment Commands & Verification

### Step 1: Deploy ExternalSecret & ArgoCD Applications
```bash
# Apply secrets and applications
kubectl apply -f advanced/gitops/manifests/secrets/external-secrets.yaml
kubectl apply -f advanced/gitops/applications/tempo-app.yaml
kubectl annotate application otel-gateway -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

### Step 2: Verify S3 Secret Sync
```bash
kubectl get externalsecret tempo-s3-credentials-ext -n monitoring
kubectl get secret tempo-s3-secret -n monitoring
```

### Step 3: Verify Tempo Pod & Service
```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=tempo
kubectl get svc -n monitoring -l app.kubernetes.io/name=tempo
```

### Step 4: Verify OTLP Receiver Endpoint
Inside the cluster, microservices can send traces to either the central **OTel Gateway** or directly to **Tempo**:
* **OTel Gateway (gRPC):** `otel-gateway-opentelemetry-collector.logging.svc.cluster.local:4317`
* **OTel Gateway (HTTP):** `otel-gateway-opentelemetry-collector.logging.svc.cluster.local:4318`
* **Tempo Direct (gRPC):** `tempo.monitoring.svc.cluster.local:4317`
* **Tempo Query & Metrics API:** `tempo.monitoring.svc.cluster.local:3200`

---

## 4. Next Step: Application Instrumentation
Attach OpenTelemetry Auto-Instrumentation to:
1. **Fineract (Java):** Mount `opentelemetry-javaagent.jar` in the `fineract-backend` pod or use environment variables (`JAVA_TOOL_OPTIONS: -javaagent:...`).
2. **AI Agent / FastMCP (Python):** Use OpenTelemetry Python SDK / instrumentation packages to send traces to `otel-gateway-opentelemetry-collector.logging.svc.cluster.local:4317`.
