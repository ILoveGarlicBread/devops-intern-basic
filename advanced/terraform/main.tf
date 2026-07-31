provider "aws" {
  region = "ap-south-1"
}

# Fetch latest Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

# Fetch your existing Route 53 Hosted Zone
data "aws_route53_zone" "primary" {
  name         = "lblam.tma-demos.shop." # Replace with your exact root hosted zone name if different
  private_zone = false
}

# Fetch default network details for automatic multi-AZ scaling
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# --- SSH KEY PAIR ---
resource "aws_key_pair" "k8s_ssh_key" {
  key_name   = "rke2-cluster-internal-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

# --- SECURITY GROUP ---
resource "aws_security_group" "k8s_sg" {
  name        = "rke2-cluster-sg"
  description = "Security group for RKE2 Kubernetes cluster"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Allow public HTTP web traffic
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow public HTTPS secure web traffic
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow native kubectl access from within the VPC
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["172.31.0.0/16"]
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- MASTER NODE (RESTARTABLE SPOT) ---
resource "aws_instance" "k8s_master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium"
  key_name               = aws_key_pair.k8s_ssh_key.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.worker_profile.name

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # Removed Spot options to run as On-Demand (within $88 budget)
  # instance_market_options {
  #   market_type = "spot"
  #   spot_options {
  #     instance_interruption_behavior = "stop"
  #     spot_instance_type             = "persistent"
  #   }
  # }

  tags = {
    Name      = "RKE2-Master"
    AutoStart = "8:30"
    AutoStop  = "18:00"
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

# =========================================================================
# --- NEW: IAM PERMISSIONS FOR ROUTE 53 AUTO-UPDATE ---
# =========================================================================
resource "aws_iam_role" "worker_route53_role" {
  name = "rke2-worker-route53-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "route53_update_policy" {
  name        = "rke2-worker-route53-policy"
  description = "Allows worker nodes to update the Fineract subdomain IP"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:GetHostedZone",
          "route53:ListResourceRecordSets"
        ]
        Resource = "arn:aws:route53:::hostedzone/${data.aws_route53_zone.primary.zone_id}"
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "worker_attach" {
  role       = aws_iam_role.worker_route53_role.name
  policy_arn = aws_iam_policy.route53_update_policy.arn
}

resource "aws_iam_instance_profile" "worker_profile" {
  name = "rke2-worker-instance-profile"
  role = aws_iam_role.worker_route53_role.name
}

// ---------------------------------------------------------------------------
// DNS records for logging and monitoring subdomains
// ---------------------------------------------------------------------------
resource "aws_route53_record" "logging_subdomain" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "logging.lblam.tma-demos.shop."
  type    = "A"
  ttl     = 60
  records = [aws_instance.k8s_worker["3"].public_ip]
}

resource "aws_route53_record" "monitoring_subdomain" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "monitoring.lblam.tma-demos.shop"
  type    = "CNAME"
  ttl     = 300
  records = ["fineract.lblam.tma-demos.shop"]
}

# Fineract DNS record
resource "aws_route53_record" "fineract_subdomain" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "fineract.lblam.tma-demos.shop."
  type    = "A"
  ttl     = 60
  allow_overwrite = true
  records = [aws_instance.k8s_worker["1"].public_ip]
}

# --- WORKER NODES (HETEROGENEOUS SPOT CLUSTER) ---
locals {
  worker_config = {
    "1" = { name = "Fineract-Core", type = "t3.large", workload = "fineract", spot = false },
    "2" = { name = "App-Stack",     type = "t3.large", workload = "apps", spot = false },
    "3" = { name = "Messaging-Ops", type = "t3.large", workload = "messaging", spot = true }
  }
}

resource "aws_instance" "k8s_worker" {
  for_each               = local.worker_config
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = each.value.type
  key_name               = aws_key_pair.k8s_ssh_key.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.worker_profile.name

  root_block_device {
    volume_size           = 60
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # Conditionally use spot instances based on worker config to bypass on-demand vCPU limits
  dynamic "instance_market_options" {
    for_each = each.value.spot ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        instance_interruption_behavior = "stop"
        spot_instance_type             = "persistent"
      }
    }
  }

  user_data = <<-EOF
              #!/bin/bash
              # Wait for internet connection
              until ping -c 1 google.com &>/dev/null; do sleep 5; done
              apt-get update && apt-get install -y awscli jq

              # Determine Workload Type and DNS requirement based on config
              WORKLOAD="${each.value.workload}"
              if [ "$WORKLOAD" = "fineract" ]; then
                DOMAIN="fineract.lblam.tma-demos.shop"
              elif [ "$WORKLOAD" = "apps" ]; then
                DOMAIN="logging.lblam.tma-demos.shop"
              else
                DOMAIN=""
              fi

              if [ -n "$DOMAIN" ]; then
                PUBLIC_IP=$(curl -s https://checkip.amazonaws.com)
                ZONE_ID="${data.aws_route53_zone.primary.zone_id}"
                cat <<'EOF_JSON' > /tmp/route53-update.json
{
  "Comment": "Automated IP update on system boot",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$DOMAIN",
        "Type": "A",
        "TTL": 60,
        "ResourceRecords": [{ "Value": "$PUBLIC_IP" }]
      }
    }
  ]
}
EOF_JSON
                aws route53 change-resource-record-sets --hosted-zone-id $ZONE_ID --change-batch file:///tmp/route53-update.json

                # Create the persistent bash script for future reboots
                cat <<EOF_SCRIPT > /usr/local/bin/update-route53.sh
#!/bin/bash
ZONE_ID="${data.aws_route53_zone.primary.zone_id}"
DOMAIN="$DOMAIN"
EOF_SCRIPT

                cat <<'EOF_SCRIPT_2' >> /usr/local/bin/update-route53.sh
PUBLIC_IP=$(curl -s https://checkip.amazonaws.com)

cat <<EOF_JSON > /tmp/route53-update.json
{
  "Comment": "Automated IP update on system boot",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$DOMAIN",
        "Type": "A",
        "TTL": 60,
        "ResourceRecords": [{ "Value": "$PUBLIC_IP" }]
      }
    }
  ]
}
EOF_JSON
aws route53 change-resource-record-sets --hosted-zone-id $ZONE_ID --change-batch file:///tmp/route53-update.json
EOF_SCRIPT_2
              fi

              # Create systemd service for future boots
              cat <<'SERVICE' > /etc/systemd/system/update-route53.service
[Unit]
Description=Update Route 53 DNS on boot
After=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/update-route53.sh
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
SERVICE

              chmod +x /usr/local/bin/update-route53.sh
              systemctl daemon-reload
              systemctl enable update-route53.service
              systemctl start update-route53.service

              # --- RKE2 INSTALLATION WITH NODE LABELS ---
              mkdir -p /etc/rancher/rke2/
              cat <<EOT > /etc/rancher/rke2/config.yaml
server: https://${aws_instance.k8s_master.private_ip}:9345
token: "fineract-cluster-secret-2026"
node-label:
  - "workload=$WORKLOAD"
EOT

              curl -sfL https://get.rke2.io | TYPE="agent" sh -
              systemctl daemon-reload
              systemctl enable rke2-agent.service
              systemctl start rke2-agent.service
  EOF

  tags = {
    Name      = "RKE2-Worker-${each.key}"
    Workload  = each.value.name
    AutoStart = "8:30"
    AutoStop  = "18:00"
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes = [ami]
  }
}

# =========================================================================
# --- ELASTICSEARCH S3 SNAPSHOT RESOURCES ---
# =========================================================================

# S3 Bucket for Elasticsearch Snapshots
resource "aws_s3_bucket" "es_snapshots" {
  bucket_prefix = "rke2-elasticsearch-snapshots-"
}

resource "aws_s3_bucket_public_access_block" "es_snapshots_block" {
  bucket                  = aws_s3_bucket.es_snapshots.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket for Loki Logs
resource "aws_s3_bucket" "loki_logs" {
  bucket_prefix = "rke2-loki-logs-"
}

resource "aws_s3_bucket_public_access_block" "loki_logs_block" {
  bucket                  = aws_s3_bucket.loki_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket for Backups (Velero & Logical)
resource "aws_s3_bucket" "cluster_backups" {
  bucket_prefix = "rke2-cluster-backups-"
}

resource "aws_s3_bucket_public_access_block" "cluster_backups_block" {
  bucket                  = aws_s3_bucket.cluster_backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM User for Elasticsearch
resource "aws_iam_user" "es_snapshot_user" {
  name = "es-snapshot-user"
}

# Access Key for the IAM User
resource "aws_iam_access_key" "es_snapshot_key" {
  user = aws_iam_user.es_snapshot_user.name
}

# IAM Policy for S3 access
resource "aws_iam_policy" "es_snapshot_policy" {
  name        = "es-snapshot-s3-policy"
  description = "Allows Elasticsearch to read/write to the snapshot S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:ListBucketMultipartUploads",
          "s3:ListBucketVersions"
        ]
        Resource = [
          aws_s3_bucket.es_snapshots.arn,
          aws_s3_bucket.loki_logs.arn,
          aws_s3_bucket.cluster_backups.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ]
        Resource = [
          "${aws_s3_bucket.es_snapshots.arn}/*",
          "${aws_s3_bucket.loki_logs.arn}/*",
          "${aws_s3_bucket.cluster_backups.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds",
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach Policy to User
resource "aws_iam_user_policy_attachment" "es_snapshot_user_attach" {
  user       = aws_iam_user.es_snapshot_user.name
  policy_arn = aws_iam_policy.es_snapshot_policy.arn
}

# --- OUTPUTS ---
output "master_public_ip" {
  value       = aws_instance.k8s_master.public_ip
}

output "master_private_ip" {
  value       = aws_instance.k8s_master.private_ip
}

output "es_snapshot_bucket" {
  value = aws_s3_bucket.es_snapshots.id
}

output "loki_logs_bucket" {
  value = aws_s3_bucket.loki_logs.id
}

output "cluster_backups_bucket" {
  value = aws_s3_bucket.cluster_backups.id
}

output "es_access_key" {
  value = aws_iam_access_key.es_snapshot_key.id
}

output "es_secret_key" {
  value     = aws_iam_access_key.es_snapshot_key.secret
  sensitive = true
}

# aws KMS setup for vault auto unseal
resource "aws_kms_key" "vault_unseal" {
      description             = "Vault auto-unseal key"
      deletion_window_in_days = 7
      enable_key_rotation     = true
    }

    resource "aws_kms_alias" "vault_unseal_alias" {
      name          = "alias/vault-auto-unseal"
      target_key_id = aws_kms_key.vault_unseal.key_id
    }

    resource "aws_iam_policy" "vault_kms_policy" {
      name        = "vault-kms-auto-unseal"
      description = "Allows Vault to auto-unseal using KMS"

      policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Action = [
              "kms:Encrypt",
              "kms:Decrypt",
              "kms:DescribeKey"
            ]
            Effect   = "Allow"
            Resource = aws_kms_key.vault_unseal.arn
          },
        ]
      })
    }
    resource "aws_iam_role_policy_attachment" "vault_kms_attach" {
      role       = aws_iam_role.worker_route53_role.name
      policy_arn = aws_iam_policy.vault_kms_policy.arn
    }


# =========================================================================
# --- AWS SSM PARAMETER STORE SECRETS ---
# =========================================================================

resource "aws_ssm_parameter" "prometheus_slack_webhook" {
  name  = "prometheus-slack-webhook"
  type  = "SecureString"
  value = "CHANGE_ME_MANUALLY"
  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "fineract_db_passwords" {
  name  = "fineract-db-passwords"
  type  = "SecureString"
  value = "CHANGE_ME_MANUALLY"
  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "s3_backup_keys" {
  name  = "s3-backup-keys"
  type  = "SecureString"
  value = "CHANGE_ME_MANUALLY"
  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "rke2_cluster_token" {
  name  = "rke2-cluster-token"
  type  = "SecureString"
  value = "CHANGE_ME_MANUALLY"
  lifecycle {
    ignore_changes = [value]
  }
}

# =========================================================================
# --- ANSIBLE INVENTORY GENERATION ---
# =========================================================================
resource "local_file" "ansible_inventory" {
  filename = "../ansible/hosts.ini"
  content  = <<-EOF
[master]
${aws_instance.k8s_master.private_ip} ansible_host=${aws_instance.k8s_master.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa

[worker]
%{ for id, worker in aws_instance.k8s_worker }
${worker.private_ip} ansible_host=${worker.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa
%{ endfor }

[k8s_cluster:children]
master
worker
EOF
}

# =========================================================================
# --- NODE-LEVEL IAM FOR SECRETS MANAGER ---
# =========================================================================
resource "aws_iam_policy" "worker_secrets_policy" {
  name        = "rke2-worker-secrets-policy"
  description = "Allows worker nodes to read from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds",
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "worker_secrets_attach" {
  role       = aws_iam_role.worker_route53_role.name
  policy_arn = aws_iam_policy.worker_secrets_policy.arn
}

resource "aws_iam_policy" "worker_bedrock_policy" {
  name        = "rke2-worker-bedrock-policy"
  description = "Allows worker nodes to invoke Bedrock models"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock-mantle:*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "worker_bedrock_attach" {
  role       = aws_iam_role.worker_route53_role.name
  policy_arn = aws_iam_policy.worker_bedrock_policy.arn
}


resource "aws_route53_record" "argocd_cname" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "argocd.lblam.tma-demos.shop"
  type    = "CNAME"
  ttl     = 300
  records = ["fineract.lblam.tma-demos.shop"]
}

resource "aws_route53_record" "ai_agent_cname" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "ai.lblam.tma-demos.shop"
  type    = "CNAME"
  ttl     = 300
  records = ["fineract.lblam.tma-demos.shop"]
}
