# Centralized Logging Architecture

This document outlines the logging pipeline deployed in the cluster (located in `advanced/helm_values/logging`).

## Current Architecture (OTel + Loki)

The logging stack has been redesigned for extreme resource efficiency, transitioning away from the RAM-heavy EFK stack.

### 1. OpenTelemetry Agent (DaemonSet)
- Runs on every node in the cluster.
- **Log Collection:** Uses the `filelog` receiver to tail `/var/log/pods/*`.
- **Parsing & Assembly:** 
  - Uses `regex_parser` to extract Kubernetes metadata.
  - Perfectly stitches together multiline Java Spring Boot stack traces using the `recombine` operator.
- **Label Transformation:** Uses a `transform` processor to promote crucial log attributes (like pod and namespace names) into resource attributes, allowing Loki to index them as searchable labels (e.g., `service_name`).

### 2. OpenTelemetry Gateway (Deployment)
- Acts as the aggregation layer.
- Batches logs from all DaemonSet agents and exports them natively via `otlphttp` to the Loki distributor.

### 3. Grafana Loki (Distributed)
- **Storage:** Lightweight log storage system that replaces Elasticsearch.
- **Indexing:** Does *not* perform full-text indexing. It only indexes Kubernetes labels (like `app`, `namespace`, `service_name`), storing the raw text chunks to save massive amounts of RAM and CPU.
- **Access:** Queried directly from Grafana via LogQL (`http://loki-read.logging.svc.cluster.local:3100`).

---

## Decommissioned Architecture (Legacy EFK Stack)

*Note: This stack was removed because Elasticsearch regularly consumed 3GB+ of RAM, starving the cluster's microservices.*

- **Fluent-bit (DaemonSet):** Tailed `/var/log/containers/*.log`, formatted logs to JSON, and shipped them to Logstash.
- **Logstash (StatefulSet):** Aggregated logs on port 8080. Utilized complex **Grok** patterns to dynamically parse raw Java Spring Boot logs and Slow Query warnings into discrete Elasticsearch columns (`fineract_log_level`, `fineract_class`, `fineract_thread`).
- **Elasticsearch (StatefulSet):** Stored logs in daily rolling indices (`fineract-logs-%{+YYYY.MM.dd}`). Had S3 snapshot capabilities (SLM policies) enabled for disaster recovery.
- **Kibana:** Used for log visualization before migrating to Grafana Explore.
