# AI Agent Implementation Guide

This guide documents the implementation of the AI Agent using the official OpenAI Agents SDK, configured to run against AWS Bedrock (Claude 3 Haiku) and deployed via ArgoCD.

## 🔗 Official Quickstart Resources
*   **OpenAI Agents Guide:** [https://platform.openai.com/docs/guides/agents](https://platform.openai.com/docs/guides/agents)
*   **Python SDK Repository:** [https://github.com/openai/openai-agents-python](https://github.com/openai/openai-agents-python)

## 🏗️ Architecture Overview
Because the `openai-agents` package expects OpenAI-compatible API endpoints, we use **LiteLLM** as a translation layer. LiteLLM spins up a local proxy inside the container that automatically routes OpenAI-formatted requests to the AWS Bedrock API securely.

1.  **AI App (`advanced/ai-agent/app/main.py`)**: Uses the OpenAI Agents SDK to define the agent, tools, and instructions.
2.  **Translation Layer (`litellm`)**: Proxies requests from `http://localhost:4000` to AWS Bedrock (`bedrock/anthropic.claude-3-haiku-20240307-v1:0`).
3.  **Containerization (`advanced/ai-agent/app/Dockerfile`)**: Packages the Python 3.11 environment, SDK, LiteLLM, and boto3.
4.  **Deployment (`advanced/ai-agent/helm/ai-agent`)**: A Helm chart that provisions the Kubernetes Deployment, injecting AWS credentials from the cluster node's IAM role.
5.  **CI/CD Pipeline (`advanced/ai-agent/buildspec.yml`)**: An AWS CodeBuild pipeline that automates building the Docker image and pushing it to Amazon ECR.
6.  **GitOps (`advanced/ci-cd/argocd/ai-agent-app.yaml`)**: An ArgoCD application that automatically synchronizes the Helm chart into the Kubernetes cluster.

## 🛠️ Step-by-Step Implementation

### Step 1: Python Application & Proxy Integration
We created the core application in `advanced/ai-agent/app/main.py`. The script starts the `litellm` background server upon initialization, pointing it to the Bedrock model. It then creates the `OpenAI` client directed at `localhost:4000`, bypassing the need for a real OpenAI API key, and relying on standard AWS credentials (`boto3`) under the hood.

### Step 2: Dockerizing the Agent
We added `advanced/ai-agent/app/requirements.txt` containing `openai-agents`, `litellm`, and `boto3`. 
The `Dockerfile` installs these dependencies into a lightweight `python:3.11-slim` image and executes `main.py`.

### Step 3: Helm Chart Scaffolding
We ran `helm create ai-agent` to scaffold a Kubernetes chart. 
We customized `values.yaml` and patched `deployment.yaml` to ensure the pod receives the `AWS_REGION` environment variable. In a production cluster running on AWS EKS or RKE2 on EC2, `boto3` inside the pod automatically inherits the node's IAM role (or IRSA if configured), making authentication against Bedrock seamless.

### Step 4: Continuous Integration (CI)
We created an AWS CodeBuild `buildspec.yml`. This defines three phases:
1.  **Pre-build**: Authenticates Docker with Amazon ECR.
2.  **Build**: Builds the Docker image from `advanced/ai-agent/app/Dockerfile`.
3.  **Post-build**: Pushes the image to ECR tagged with the Git commit hash, ensuring traceablility.

### Step 5: Continuous Deployment (CD)
We created `advanced/ci-cd/argocd/ai-agent-app.yaml`. When applied to the cluster, ArgoCD automatically monitors the `advanced/ai-agent/helm/ai-agent` directory in CodeCommit. As soon as the Helm chart or its configuration changes, ArgoCD automatically synchronizes those changes into the `ai-agent` namespace.

## 🚀 How to Expand the Agent
To add new capabilities to the agent (for example, allowing it to query Fineract databases):
1.  Open `advanced/ai-agent/app/main.py`.
2.  Define a new Python function (e.g., `def query_database(query: str):`).
3.  Add the function name to the `tools=[get_weather, query_database]` list when initializing the `Agent`.
4.  Commit the change. CodeBuild will build the new image, and ArgoCD will roll out the updated pod!
