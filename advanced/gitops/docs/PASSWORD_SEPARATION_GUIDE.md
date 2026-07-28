# Fineract Database Password Separation Guide

Currently, your architecture relies on a single shared `password` in HashiCorp Vault for the Fineract Master Password, the `fineract-default` database, and the `fineract-tenants` database. This violates the principle of least privilege. 

This guide outlines the step-by-step process to separate these into three distinct credentials (`tenantDbPassword`, `defaultDbPassword`, `fineractMasterPassword`).

## Phase 1: Update HashiCorp Vault

Update the `fineract-db-passwords` secret in your `production-vault` KV store to include three separate keys instead of one global `password` key:

```bash
# 1. Access the Vault pod (bypassing TLS verification for local access)
kubectl exec -n vault -it vault-0 -- sh

# 2. Login using your Initial Root Token
> vault login <YOUR_INITIAL_ROOT_TOKEN>

# 3. Update the secret with the new distinct passwords
> vault kv put secret/fineract-db-passwords \
  rootPassword="<super-secret-root>" \
  tenantDbPassword="<tenant-db-secret>" \
  defaultDbPassword="<default-db-secret>" \
  fineractMasterPassword="<fineract-master-secret>"

# 4. Exit the pod
> exit
```

## Phase 2: Update External Secrets

You need to update your Kubernetes `ExternalSecret` manifests so they map the new distinct Vault keys to the correct Kubernetes Secret keys.

### 1. Update `fineract-default-ext`
Modify the `fineract-default` ExternalSecret to sync the `defaultDbPassword` and the `fineractMasterPassword`.

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: fineract-default-ext
  namespace: fineract
spec:
  # ... (keep existing storeRef and refreshInterval) ...
  target:
    name: fineract-default
  data:
  - secretKey: database-password
    remoteRef:
      key: fineract-db-passwords
      property: defaultDbPassword
  - secretKey: master-password
    remoteRef:
      key: fineract-db-passwords
      property: fineractMasterPassword
  - secretKey: database-root-password
    remoteRef:
      key: fineract-db-passwords
      property: rootPassword
```

### 2. Update `fineract-tenants-ext`
Modify the `fineract-tenants` ExternalSecret to specifically pull `tenantDbPassword`.

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: fineract-tenants-ext
  namespace: fineract
spec:
  # ...
  target:
    name: fineract-tenants
  data:
  - secretKey: database-password
    remoteRef:
      key: fineract-db-passwords
      property: tenantDbPassword
  - secretKey: database-root-password
    remoteRef:
      key: fineract-db-passwords
      property: rootPassword
```

## Phase 3: Update Kubernetes Deployments

You must update the environment variables in both the Application and the Database manifests so they use the separated passwords.

### 1. Update Fineract Server (`advanced/fineract/templates/fineract-server-deployment.yml`)
```yaml
            # Password for connecting to the fineract_tenants DB
            - name: FINERACT_HIKARI_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: fineract-tenants
                  key: database-password
            - name: fineract_tenants_pwd
              valueFrom:
                secretKeyRef:
                  name: fineract-tenants
                  key: database-password

            # Password for the fineract_default DB (tenant data)
            - name: FINERACT_DEFAULT_TENANTDB_PWD
              valueFrom:
                secretKeyRef:
                  name: fineract-default
                  key: database-password

            # Fineract Master Password for decrypting AES payloads
            - name: FINERACT_TENANT_MASTERPASSWORD
              valueFrom:
                secretKeyRef:
                  name: fineract-default
                  key: master-password
```

### 2. Update MariaDB Default (`advanced/fineract/templates/mysql-default.yaml`)
Update the `MARIADB_PASSWORD` block to pull from the `fineract-default` secret instead of the old shared secret:
```yaml
            - name: MARIADB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: fineract-default
                  key: database-password
```

### 3. Update MariaDB Tenants (`advanced/fineract/templates/mysql-tenants.yaml`)
Update the `MARIADB_PASSWORD` block to pull from the `fineract-tenants` secret:
```yaml
            - name: MARIADB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: fineract-tenants
                  key: database-password
```

## Phase 4: Refactor the `fineract-db-sync` CronJob

Since Fineract relies on AES encryption to store the `fineract_default` database password inside the `fineract_tenants` database, the auto-sync script must now pull all three passwords to generate the correct hash.

In `advanced/fineract/templates/fineract-backup-cronjob.yaml` (or wherever your `fineract-db-sync` cronjob is defined), update the environment block:

```yaml
            env:
            - name: DEFAULT_DB_PWD
              valueFrom:
                secretKeyRef:
                  name: fineract-default
                  key: database-password
            - name: TENANT_DB_PWD
              valueFrom:
                secretKeyRef:
                  name: fineract-tenants
                  key: database-password
            - name: MASTER_PWD
              valueFrom:
                secretKeyRef:
                  name: fineract-default
                  key: master-password
```

**Script Logic Update:** The bash script (`sync.sh`) inside `fineract-db-sync-script` ConfigMap must be updated so that it generates the BCrypt hash using `$MASTER_PWD` and generates the AES payload encrypting `$DEFAULT_DB_PWD` using `$MASTER_PWD`.

## Phase 5: Fix the Monitoring Exporters

Earlier, we updated the Prometheus MySQL exporters to use the single synced `password`. After separation, you must update their ExternalSecrets and Helm values so that:
- `mysql-exporter-default` connects using the `defaultDbPassword`.
- `mysql-exporter-tenants` connects using the `tenantDbPassword`.

Update `external-secrets-db.yaml` in the `monitoring` namespace to sync `defaultDbPassword` and `tenantDbPassword`, and point the respective Helm values (`mysql-default-values.yaml` and `mysql-tenants-values.yaml`) to those exact keys.

## Phase 6: Understanding Rotation Limitations

Fineract's database routing architecture imposes strict limitations on how passwords can be rotated. Because Fineract stores the credentials for its default tenant database encrypted *inside* the master tenant database, some passwords cannot be dynamically rotated without manual intervention:

1. **The Tenants DB Password (`TENANT_DB_PWD`) - FULLY AUTOMATED ✅**
   You can rotate the `fineract_tenants` database password as often as you want. Fineract connects to this database using a plain-text environment variable in Kubernetes (`FINERACT_HIKARI_PASSWORD`). When the Vault secret changes, Kubernetes injects the new password, and the CronJob automatically updates MySQL. No Java encryption is needed.

2. **The Default DB Password (`DEFAULT_DB_PWD`) - MANUAL ❌**
   If you rotate the password for the `fineract_default` database, Fineract will crash. Fineract reads the `tenant_server_connections` table inside the tenants DB, reads the `schema_password` column, and decrypts it using the Master Password. If you change the default DB password, you **must** manually run the Java `DatabasePasswordEncryptor` utility to generate a new AES string representing that new password, and then update the DB sync script with the new hardcoded payload.

3. **The Master Password (`MASTER_PWD`) - MANUAL ❌**
   If you change the Master Password, Fineract will crash because it won't be able to decrypt the AES payload stored in the database. You must use the Java tool to generate a new BCrypt hash *and* a new AES payload for the `DEFAULT_DB_PWD`, and manually update the `tenant_server_connections` database table.
