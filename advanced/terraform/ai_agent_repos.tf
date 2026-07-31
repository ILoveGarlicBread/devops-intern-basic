resource "aws_codecommit_repository" "ai_agent_app" {
  repository_name = "ai-agent-app"
  description     = "Repository for AI Agent application code (Dockerfile, Python)"
}

resource "aws_codecommit_repository" "ai_agent_manifests" {
  repository_name = "ai-agent-manifests"
  description     = "Repository for AI Agent Helm charts and GitOps manifests"
}

resource "aws_ecr_repository" "ai_agent_repo" {
  name                 = "ai-agent"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_repository" "fineract_mcp_server_repo" {
  name                 = "fineract-mcp-server"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }
}
