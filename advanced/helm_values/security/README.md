# Security & Secrets Management Architecture

This document outlines the security controls, secrets management, and encryption mechanisms deployed across the cluster (located in `advanced/helm_values/security`).

## 1. Secrets Management (HashiCorp Vault & ESO)

### HashiCorp Vault (High Availability)
- **Deployment:** Deployed as a 3-replica StatefulSet (`vault`, `vault-active`, `vault-standby`).
- **Storage:** Uses Integrated Raft Storage for high availability and consensus.
- **Auto-Unseal:** Initially deployed using manual Shamir's Secret Sharing (threshold 3/5), but later migrated to **AWS KMS Auto-Unseal**. If a pod crashes, it automatically unseals itself via AWS KMS without human intervention.
- **Security:** Vault internal communication is secured via TLS. Upgraded Vault Kubernetes Auth from using a static ServiceAccount `token_reviewer_jwt` to purely zero-trust. Vault now dynamically utilizes its own ephemeral pod token (`/var/run/secrets/kubernetes.io/serviceaccount/token`) to authenticate against the Kubernetes TokenReview API, completely eliminating the need for permanent secrets and preventing token expiration lockouts in K8s 1.24+.

### External Secrets Operator (ESO)
- **Functionality:** Replaced direct AWS Secrets Manager/SSM integrations. 
- **Authentication:** Authenticates to Vault via K8s Auth using the `eso-role`.
- **Injection:** Dynamically fetches secrets from Vault (KV v2) and generates native Kubernetes Secrets in memory.
- **Managed Secrets:**
  - `prometheus-slack-webhook` (Alertmanager)
  - `fineract-db-passwords` (MySQL default, tenant, and master credentials)
  - Velero AWS S3 credentials
  - *Future:* Dynamic Secret Engines for ephemeral AWS STS tokens and MySQL users.

## 2. Infrastructure Security

### Kube-bench & RKE2 Hardening
- Executed Aqua `kube-bench` CIS benchmark scans.
- Hardened RKE2 Kubelet configurations via Ansible by:
  - Enforcing strict Webhook authentication.
  - Disabling anonymous access.
  - Restricting cryptographic ciphers.

### Trivy Vulnerability Management
- Remediated Kubernetes Security Posture (KSV) misconfigurations:
  - Enforced `readOnlyRootFilesystem: true` via `emptyDir` mounts for `/tmp` and `/var/cache/nginx`.
  - Dropped unnecessary capabilities.
  - Enforced `runAsNonRoot: true`.
- Migrated legacy `mariadb:11.4` (15 HIGH/CRITICAL CVEs) to `bitnami/mariadb:latest`. Solved non-root volume permission issues by injecting `fsGroup: 10001` into the Pod Security Context.

### Pod Security Admissions
- Enforced the Kubernetes `restricted` Pod Security Standards on the `default` namespace to actively block privileged containers and host path mounts.

## 3. Application Security (Fineract Decryption)
- **Database Password Separation:** Refactored Fineract's shared password into 3 distinct credentials (`tenantDbPassword`, `defaultDbPassword`, `fineractMasterPassword`) enforcing the principle of least privilege.
- **AES Payload Rotation:** Engineered a `CronJob` (`fineract-db-sync`) to manually execute Fineract's `DatabasePasswordEncryptor` utility. It generates new AES and BCrypt hashes and injects them directly into the `fineract_tenants.tenant_server_connections` table when ESO rotates the Vault secret, preventing `CrashLoopBackOff` decryption failures.

## 4. Ingress & TLS (Cert-Manager)
- **Cert-Manager:** Deployed with a `ClusterIssuer` (`letsencrypt-prod`).
- **TLS Certificates:** Successfully issues valid HTTPS Let's Encrypt certificates for all domains (`fineract.*`, `monitoring.*`). 
