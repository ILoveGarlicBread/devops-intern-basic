# CI/CD & GitOps Architecture

This document outlines the continuous integration and continuous deployment stack implemented in the cluster (located in `advanced/ci-cd`).

## Strategy Overview
The cluster has been shifted from manual Helm execution to a declarative, pull-based GitOps model.

## 1. Continuous Deployment (ArgoCD)
- **Pattern:** Adopts the "App of Apps" GitOps pattern.
- **Adoption Strategy:** Utilizing Brownfield cluster adoption methodologies to safely bring the existing, live Fineract environment under ArgoCD management without destroying the running resources.
- **Current State:** Staged and actively syncing components like Jenkins, Cert-Manager, and the Monitoring stack.
- **Fixes:** Resolved a CORS Preflight/Mixed-Content error in the Fineract UI proxy that blocked login by enforcing HTTPS returns in the Helm templates.

## 2. Continuous Integration (Jenkins & Kaniko)
- **History (AWS CodeBuild Pivot):** Originally planned to use AWS CodeBuild for building AI Agent Docker images. Due to a hard `0.0` concurrent build Service Quota (AWS anti-fraud lock) and the inability of Lambda CodeBuild environments to run Privileged Mode (required for `docker build`), the CI pipeline was pivoted to a self-hosted Jenkins instance.
- **Deployment Strategy:** Deployed natively inside the Kubernetes cluster via an ArgoCD "Umbrella Chart" (`advanced/ci-cd/jenkins/Chart.yaml` dependencies).
- **Configuration (JCasC):** Uses Configuration as Code for provisioning.
- **Dockerless Builds (Kaniko):** Replaced standard `docker build` within the Jenkins pipeline with a Google Kaniko sidecar. Kaniko securely builds images inside the RKE2 containerd environment without requiring root access or a Docker daemon. It dynamically inherits the EC2 worker node's IAM profile (`rke2-worker-route53-role` + `AmazonEC2ContainerRegistryPowerUser`) to securely push to AWS ECR.
- **GitOps Loop Prevention (`[skip ci]`):** Implemented a pipeline validation stage to detect and halt on `[skip ci]` commit messages. This successfully prevents the classic infinite CI/CD loop caused by Jenkins committing Helm manifests back to the same monorepo it polls.
- **GitOps SSH Authentication Fixes:** Resolved Jenkins SSH `git push` failures to AWS CodeCommit by explicitly setting `export GIT_SSH_COMMAND="ssh -i \${SSH_KEY} -o StrictHostKeyChecking=no -o User=\${SSH_USERNAME}"`, forcing Git to authenticate using the AWS IAM Key ID instead of the default container username.
- **Fixes:** Resolved a `VersionCompatibilityException` during initialization by upgrading the Jenkins controller image tag to `latest-jdk17`, satisfying the minimum requirements of the newest pipeline plugins.
