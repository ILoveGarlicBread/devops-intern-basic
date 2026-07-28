resource "aws_codecommit_repository" "ai_agent_app" {
  repository_name = "ai-agent-app"
  description     = "Repository for AI Agent application code (Dockerfile, Python)"
}

resource "aws_codecommit_repository" "ai_agent_manifests" {
  repository_name = "ai-agent-manifests"
  description     = "Repository for AI Agent Helm charts and GitOps manifests"
}
