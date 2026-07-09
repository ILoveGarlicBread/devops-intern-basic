# Cluster Context & Environment Rules

## Environment Details
- **OS:** Ubuntu Master Node
- **Kubernetes Distribution:** RKE2
- **Namespace:** fineract
- **Storage Provider:** Longhorn (RWO)

## Binary & Tool Paths
- **kubectl:** Always use `/var/lib/rancher/rke2/bin/kubectl` (do not look in standard PATH).
- **helm:** Available via `sudo helm`.
- Always append `--kubeconfig /etc/rancher/rke2/rke2.yaml` or use the RKE2 environment context when running commands.

## Application Architecture (Apache Fineract)
- **Database Pod 1:** `fineract-default-0` (StatefulSet, MariaDB 11.4, holds business/client data).
- **Database Pod 2:** `fineract-tenants-0` (StatefulSet, MariaDB 11.4, holds tenant routing data).
- **Backend Pod:** `fineract-backend-*` (Deployment, Java/Spring Boot app, handles Flyway migrations).
- **Proxy/UI:** `fineract-nginx-proxy` and `fineract-ui`.

## Operational Rules
- Never use brute-force loops or sleep timers to poll logs unless explicitly requested. If waiting for a pod, use `kubectl wait`.
- When generating SQL data injection scripts, remember that `m_office` requires core branches (Hanoi, Da Nang, Saigon, Can Tho) to exist before injecting clients.
- Keep terminal tool execution targeted and precise to preserve token quota.

## Current Learning Projects
- **Helm Mastery:** Practicing deployments using the Bitnami Helm Library.
- **Scope:** Mongo, PostgreSQL, Kafka, Redis, RabbitMQ, Memcached, Qdrant, Milvus, MySQL, and Kube-Prometheus.
- **Goal:** Achieve professional fluency in Helm, specifically focusing on deep-diving into and understanding the internal structure, templating patterns, and parameter configurations of Bitnami charts. So make sure the explain the steps and terminology for me

## Deployed Bitnami Learning Stack (June 2026)
Deployed on a single t3a.large node with resource-optimized configurations:

### 1. Redis (Namespace: `redis`)
- **Mode:** Standalone
- **Auth:** Disabled (Learning mode)
- **Limits:** 128Mi Memory
- **Access:** `redis-master.redis.svc.cluster.local:6379`

### 2. PostgreSQL (Namespace: `postgresql`)
- **Mode:** Standalone (Primary only)
- **Password:** `password123`
- **Limits:** 256Mi Memory
- **Access:** `postgresql.postgresql.svc.cluster.local:5432`

### 3. RabbitMQ (Namespace: `rabbitmq`)
- **Mode:** Standalone
- **Password:** `password123` (User: `user`)
- **Limits:** 512Mi Memory
- **Access:** `rabbitmq.rabbitmq.svc.cluster.local:5672` (AMQP) / `15672` (Management UI)

*Note: All deployments use `--set` overrides for resource requests/limits to maintain node stability.*

