data "aws_vpc" "vpc" {
  tags = { Name = "trade-tariff-${var.environment}-vpc" }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc.id]
  }

  tags = {
    Name = "*private*"
  }
}

# HTTP target groups created by the common stack's ALB (see
# environments/<env>/common/alb.tf -> http_services in the terraform repo).
data "aws_lb_target_group" "flagsmith" {
  name = "flagsmith-http"
}

data "aws_lb_target_group" "flagsmith_edge" {
  name = "flagsmith-edge-http"
}

# Dedicated Flagsmith ECS security group (HTTP 8000 from the ALB).
data "aws_security_group" "this" {
  name = "flagsmith-ecs-${var.environment}"
}

# Full postgres:// connection string, created by the rds module in common.
data "aws_secretsmanager_secret" "database" {
  name = "flagsmith-connection-string"
}

data "aws_secretsmanager_secret_version" "database" {
  secret_id = data.aws_secretsmanager_secret.database.id
}

# Operator-managed Django config (SECRET_KEY etc.).
data "aws_secretsmanager_secret" "configuration" {
  name = "flagsmith-configuration"
}

data "aws_secretsmanager_secret_version" "configuration" {
  secret_id = data.aws_secretsmanager_secret.configuration.id
}

# Operator-managed edge-proxy config (server-side environment key).
data "aws_secretsmanager_secret" "edge_configuration" {
  name = "flagsmith-edge-configuration"
}

data "aws_secretsmanager_secret_version" "edge_configuration" {
  secret_id = data.aws_secretsmanager_secret.edge_configuration.id
}

data "aws_sns_topic" "slack_topic" {
  name = "slack-topic"
}
