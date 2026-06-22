# fineract

<link rel="icon" href="https://raw.githubusercontent.com/maximilianoPizarro/botpress-helm-chart/main/favicon-152.ico" type="image/x-icon" >
<p align="left">
<img src="https://img.shields.io/badge/redhat-CC0000?style=for-the-badge&logo=redhat&logoColor=white" alt="Redhat">
<img src="https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white" alt="kubernetes">
<img src="https://img.shields.io/badge/helm-0db7ed?style=for-the-badge&logo=helm&logoColor=white" alt="Helm">
<img src="https://img.shields.io/badge/shell_script-%23121011.svg?style=for-the-badge&logo=gnu-bash&logoColor=white" alt="shell">
<a href="https://www.linkedin.com/in/maximiliano-gregorio-pizarro-consultor-it"><img src="https://img.shields.io/badge/LinkedIn-0077B5?style=for-the-badge&logo=linkedin&logoColor=white" alt="linkedin" /></a>
<a href="https://artifacthub.io/packages/search?repo=fineract-openshift"><img src="https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/fineract" alt="Artifact Hub" /></a>
</p>

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square)

Apache Fineract is an open source microfinance platform that provides a robust and scalable solution for financial institutions, enabling the management of loans, savings, customers and financial reporting.

**Homepage:** <https://github.com/apache/fineract>

### TL;DR

Apache Fineract is an open-source platform for microfinance that provides core banking functionality for lending, savings and client management. This deployment architecture uses two separate MariaDB instances (one for the default/global database and one for tenant data), with an NGINX server acting as the application gateway/reverse proxy. Default admin credentials shipped in this chart are: user `mifos` and password `password`. This deployment requires at least 4 vCPU for the Fineract backend (for Liquibase migrations) and 16 GiB of RAM for the entire architecture.

# Architecture

<div align="center">
  <img src="https://maximilianopizarro.github.io/fineract/fineract-openshift.png" width="900"/>
</div>

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| fineractServer.admin.user | string | `"mifos"` | Default admin username |
| fineractServer.admin.password | string | `"password"` | Default admin password (change in production) |
| fineractServer.extraEnv | object | See `values.yaml` | Dictionary of key/value pairs to pass as environment variables to the backend pods They will be evaluated as Helm templates |
| fineractServer.extraSecretEnv | object | `{}` | Same as `extraEnv` but passed as secrets |
| fineractServer.image.name | string | `"apache/fineract"` | Fineract Docker image name |
| fineractServer.image.tag | string | `"latest"` | Fineract Docker image tag |
| fineractServer.replicas | int | `1` | Number of backend pods |
| fineractServer.resources | object | `{"limits":{"cpu":"1000m","memory":"1Gi"}}` | Resource settings for Backend pods |
| fineractUI.image.name | string | `"openmf/community-app"` | Frontend Docker image name |
| fineractUI.image.tag | string | `"latest"` | Frontend Docker image tag |
| fineractUI.replicas | int | `1` | Number of frontend pods |
| fineractUI.resources | object | `{"limits":{"cpu":"100m","memory":"100Mi"}}` | Resource settings for UI pods |
| global.db.defaultDb | string | `"fineract_default"` | DB name for default/global database |
| global.db.tenantsDb | string | `"fineract_tenants"` | DB name for tenants database |
| mysql.primary | object | see `values.yaml` | Primary MariaDB instance (global/default DB) settings |
| mysql.primary.enabled | bool | `true` | Install primary MariaDB? |
| mysql.primary.auth.username | string | `"fineract"` | DB user for primary DB |
| mysql.primary.auth.password | string | `""` | Please change these... |
| mysql.primary.auth.rootPassword | string | `""` | Please change these... |
| mysql.tenants | object | see `values.yaml` | Separate MariaDB instance for tenant databases |
| mysql.tenants.enabled | bool | `true` | Install tenants MariaDB? |
| mysql.tenants.auth.username | string | `"fineract_tenant"` | DB user for tenants DB |
| mysql.tenants.auth.password | string | `""` | Please change these... |
| mysql.tenants.auth.rootPassword | string | `""` | Please change these... |
| mysql.initdbScripts | object | see `values.yaml` | Dictionary of init scripts to run on initial MySQL setup __WARNING__! These db init scripts will only be executed on a brand new, uninitialized instance! Further changes will be ignored after the first init, unless you wipe the underlying PV/PVC volumes |
| nginx | object | see `values.yaml` | NGINX reverse proxy / ingress gateway configuration |
| nginx.enabled | bool | `false` | Deploy NGINX gateway? |
| nginx.image.name | string | `"nginx"` | NGINX image name |
| nginx.image.tag | string | `"stable"` | NGINX image tag |
| nginx.replicas | int | `1` | Number of nginx pods |
| nginx.service.type | string | `"ClusterIP"` | Service type for NGINX |
| ingress.annotations | object | `{}` | Ingress annotations |
| ingress.enabled | bool | `false` | Create Ingress? |
| ingress.hosts | list | `[]` |  |
| ingress.tls | list | `[]` | TLS settings |
| service.type | string | `"ClusterIP"` | Service type for Fineract and UI services |
