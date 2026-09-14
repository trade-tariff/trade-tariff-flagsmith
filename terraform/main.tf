# Self-hosted Flagsmith — API/dashboard and edge proxy.
#
# Both are plain Django/FastAPI HTTP services pulled straight from Docker Hub and
# deployed via the shared ecs-service module, exactly like our other apps. The
# supporting infrastructure (database, security groups, secrets, ALB target
# groups, CloudFront) lives in the terraform repo's common stacks; this repo
# only deploys the running services against it.

module "flagsmith" {
  source = "git@github.com:trade-tariff/trade-tariff-platform-terraform-modules.git//aws/ecs-service?ref=aws/ecs-service-v3.3.1"

  region = var.region

  service_name  = "flagsmith"
  service_count = var.service_count

  cluster_name    = "trade-tariff-cluster-${var.environment}"
  subnet_ids      = data.aws_subnets.private.ids
  security_groups = [data.aws_security_group.this.id]

  target_group_arn = data.aws_lb_target_group.flagsmith.arn
  container_port   = 8000

  cloudwatch_log_group_name = "platform-logs-${var.environment}"

  docker_image = "flagsmith/flagsmith"
  docker_tag   = var.flagsmith_tag

  private_dns_namespace = "tariff.internal"

  cpu    = var.cpu
  memory = var.memory

  task_role_policy_arns = [aws_iam_policy.task.arn]
  enable_ecs_exec       = true

  # USER nobody (wolfi-baselayout) = UID/GID 65534:65534. /tmp/prometheus is baked
  # into the image (prometheus_client multiprocess metrics) but gets masked when /tmp
  # is mounted as its own ephemeral volume — must be listed separately, or
  # prometheus_client crashes with FileNotFoundError instead of creating the dir.
  readonly_root_filesystem = true
  writable_paths           = ["/tmp", "/tmp/prometheus"]
  container_user           = "65534:65534"

  service_environment_config = local.flagsmith_env_vars

  has_autoscaler = local.has_autoscaler
  min_capacity   = var.min_capacity
  max_capacity   = var.max_capacity

  autoscaling_metrics = {
    cpu = {
      metric_type  = "ECSServiceAverageCPUUtilization"
      target_value = 50
    }
    memory = {
      metric_type  = "ECSServiceAverageMemoryUtilization"
      target_value = 70
    }
  }

  enable_alarms       = var.enable_alarms
  cpu_alarm_threshold = 75

  sns_topic_arns               = [data.aws_sns_topic.slack_topic.arn]
  observability_sns_topic_arns = var.enable_observability_alerts ? [data.aws_sns_topic.slack_observability_topic[0].arn] : null
}

module "flagsmith_edge" {
  source = "git@github.com:trade-tariff/trade-tariff-platform-terraform-modules.git//aws/ecs-service?ref=aws/ecs-service-v3.3.1"

  # Edge fetches its environment document from the Flagsmith API over Cloud Map,
  # so the API service registration needs to exist before edge rolls forward.
  depends_on = [module.flagsmith]

  region = var.region

  service_name  = "flagsmith-edge"
  service_count = var.service_count

  cluster_name    = "trade-tariff-cluster-${var.environment}"
  subnet_ids      = data.aws_subnets.private.ids
  security_groups = [data.aws_security_group.this.id]

  target_group_arn = data.aws_lb_target_group.flagsmith_edge.arn
  container_port   = 8000

  cloudwatch_log_group_name = "platform-logs-${var.environment}"

  docker_image = "flagsmith/edge-proxy"
  docker_tag   = var.edge_proxy_tag
  skip_destroy = true

  private_dns_namespace = "tariff.internal"

  cpu    = var.cpu
  memory = var.memory

  task_role_policy_arns = [aws_iam_policy.task.arn]
  enable_ecs_exec       = true

  # USER nobody (Debian base-passwd, python:3.12-slim) is UID/GID 65534:65534.
  # edge-proxy caches in memory and logs to stdout — /tmp is kept writable as a margin.
  readonly_root_filesystem = true
  writable_paths           = ["/tmp"]
  container_user           = "65534:65534"

  service_environment_config = local.edge_env_vars

  has_autoscaler = local.has_autoscaler
  min_capacity   = var.min_capacity
  max_capacity   = var.max_capacity

  autoscaling_metrics = {
    cpu = {
      metric_type  = "ECSServiceAverageCPUUtilization"
      target_value = 50
    }
  }

  enable_alarms       = var.enable_alarms
  cpu_alarm_threshold = 75

  sns_topic_arns               = [data.aws_sns_topic.slack_topic.arn]
  observability_sns_topic_arns = var.enable_observability_alerts ? [data.aws_sns_topic.slack_observability_topic[0].arn] : null
}
