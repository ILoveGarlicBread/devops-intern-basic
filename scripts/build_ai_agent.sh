#!/bin/bash
set -e

echo "Logging into Amazon ECR..."
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin 205714230466.dkr.ecr.ap-south-1.amazonaws.com

echo "Building the Docker image..."
cd /home/ubuntu/TMA-DevOps-Lam-Internship/advanced/ai-agent/app
docker build -t 205714230466.dkr.ecr.ap-south-1.amazonaws.com/ai-agent:latest .

echo "Pushing the Docker image to ECR..."
docker push 205714230466.dkr.ecr.ap-south-1.amazonaws.com/ai-agent:latest

echo "Restarting the Kubernetes Deployment to pull the new image..."
kubectl rollout restart deployment ai-agent -n ai-agent

echo "Done! The new AI Agent is deploying."
