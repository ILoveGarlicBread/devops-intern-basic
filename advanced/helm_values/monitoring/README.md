# Kubernetes Monitoring Architecture

This document outlines the monitoring stack deployed in the cluster, primarily managed via the files located in `advanced/helm_values/monitoring`.

## Core Components
The core monitoring stack is built on top of the `kube-prometheus-stack` Helm chart. 

### 1. Prometheus
- **Scraping & Storage:** Runs as a StatefulSet via the Prometheus Operator. Uses Longhorn (`longhorn-static`) to provision a 10Gi Persistent Volume for time-series data storage.
- **Node Selection:** Pinned to nodes with the label `workload: messaging`.
- **Exporters:** Uses `prometheus-node-exporter` (including control-plane tolerations) and `kube-state-metrics` (configured to monitor custom Kanister `ActionSet` resources for backup statuses).

### 2. Grafana
- **Access:** Exposed via Ingress on `monitoring.lblam.tma-demos.shop` with TLS (managed by `cert-manager`). 
- **Storage:** Persisted via a 4Gi Longhorn volume.
- **Credentials:** 
  - **Username:** `admin`
  - **Password:** `oZnDLpcZ7UshGTkxIImaIAQSIPA4w1GUXF9Jjaqc`
- **Data Sources:** Connected to Prometheus by default. It also includes an additional data source connecting to Loki (`http://loki-read.logging.svc.cluster.local:3100`) for seamless log correlation.
- **Dashboards:** Automatically provisions custom dashboards via `dashboardproviders.yaml`, referencing pre-built dashboards (e.g., Blackbox Exporter, Longhorn, Velero, Nginx Ingress, Vault, Kanister, MySQL, Fineract Business).

### 3. Alertmanager
- **Routing & Inhibitions:** Configured to inhibit warnings if a critical alert of the same type is firing. Contains specific null-routes for common ghost alerts (e.g., `Watchdog`, `KubeProxyDown`, unneeded Longhorn warnings).
- **Notifications:** Configured with a Slack receiver (`slack-notifications`). The webhook URL is dynamically pulled from the `prometheus-slack-webhook` secret (which is populated via External Secrets Operator).

## Custom Exporters & ServiceMonitors

### A. Blackbox Exporter (`blackbox-exporter.yaml`)
Used to probe endpoints over HTTP to ensure applications are reachable from within the cluster.
- **Probes:**
  - `http_fineract`: Probes `fineract.lblam.tma-demos.shop` and ensures the HTML body matches `.*[Ff]ineract.*|.*[Mm]ifos.*`.
  - `http_grafana`: Probes Grafana and validates the response matches `.*Grafana.*`.
  - `http_argocd`: Probes ArgoCD.
  - `http_2xx`: A generic probe checking external connectivity (e.g., `github.com`).
- **Configuration:** Employs a custom `dnsPolicy: None` with Google/Cloudflare DNS (`8.8.8.8`) to ensure it tests external DNS resolution via Route53, avoiding internal cluster DNS caching.

### B. Fineract Business Exporter (`fineract-business-exporter.yaml`)
A custom deployment leveraging `burningalchemist/sql_exporter:latest` to extract business metrics directly from the MySQL database.
- **Metrics Collected:**
  - `fineract_clients_total`: Total number of clients (`m_client`).
  - `fineract_accounts_total`: Total savings accounts (`m_savings_account`).
  - `fineract_loans_total`: Total loans (`m_loan`).
- **Security:** Pulls the database password dynamically from the `fineract-db-passwords` secret.

### C. MySQL Exporters (`mysql-default-values.yaml`, `mysql-tenants-values.yaml`)
Dedicated Helm releases to scrape MySQL system metrics for both the Fineract Default and Fineract Tenants databases.

### D. Other Integrations
- **Longhorn:** Custom Prometheus Rules and ServiceMonitors to track volume health and capacity (`longhorn-prometheus-rules.yaml`, `longhorn-servicemonitor.yaml`).
- **Kanister:** Custom ServiceMonitors and Dashboards (`kanister-servicemonitor.yaml`, `kanister-dashboard-cm.yaml`) to track the success/failure states of logical database backups.
- **External Secrets Operator:** Custom dashboards to monitor secret syncing (`external-secrets-dashboard.yaml`).
