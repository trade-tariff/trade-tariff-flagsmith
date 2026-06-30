locals {
  # Public domain per environment (matches the terraform repo's common stacks).
  domains = {
    development = "dev.trade-tariff.service.gov.uk"
    staging     = "staging.trade-tariff.service.gov.uk"
    production  = "trade-tariff.service.gov.uk"
  }
  domain      = local.domains[var.environment]
  flags_host  = "flags.${local.domain}"
  edge_host   = "flags-edge.${local.domain}"
  flags_url   = "https://${local.flags_host}"
  edge_origin = "https://${local.edge_host}"

  # Operator-managed config secrets, expanded into individual env vars.
  config_map = jsondecode(try(data.aws_secretsmanager_secret_version.configuration.secret_string, "{}"))
  flagsmith_managed_env_var_names = [
    "ACCESS_LOG_LOCATION",
    "ALLOW_REGISTRATION_WITHOUT_INVITE",
    "DATABASE_URL",
    "DJANGO_ALLOWED_HOSTS",
    "DJANGO_CSRF_TRUSTED_ORIGINS",
    "FLAGSMITH_DOMAIN",
    "LOG_LEVEL",
    "SECURE_PROXY_SSL_HEADER_NAME",
    "SECURE_PROXY_SSL_HEADER_VALUE",
    "USE_X_FORWARDED_HOST",
  ]
  config_env_vars = [
    for key, value in local.config_map : { name = key, value = tostring(value) }
    if !contains(local.flagsmith_managed_env_var_names, key)
  ]

  edge_config_map = jsondecode(try(data.aws_secretsmanager_secret_version.edge_configuration.secret_string, "{}"))
  edge_managed_env_var_names = [
    "API_URL",
  ]
  edge_config_env_vars = [
    for key, value in local.edge_config_map : { name = key, value = tostring(value) }
    if !contains(local.edge_managed_env_var_names, key)
  ]

  # Static env vars for the Flagsmith API.
  flagsmith_static_env_vars = [
    { name = "DATABASE_URL", value = data.aws_secretsmanager_secret_version.database.secret_string },
    { name = "DJANGO_ALLOWED_HOSTS", value = "*" },
    { name = "DJANGO_CSRF_TRUSTED_ORIGINS", value = local.flags_url },
    { name = "FLAGSMITH_DOMAIN", value = local.flags_host },
    { name = "USE_X_FORWARDED_HOST", value = "1" },
    { name = "SECURE_PROXY_SSL_HEADER_NAME", value = "HTTP_X_FORWARDED_PROTO" },
    { name = "SECURE_PROXY_SSL_HEADER_VALUE", value = "https" },
    { name = "ALLOW_REGISTRATION_WITHOUT_INVITE", value = tostring(lookup(local.config_map, "ALLOW_REGISTRATION_WITHOUT_INVITE", "true")) }
  ]

  flagsmith_logging_env_vars = [
    { name = "ACCESS_LOG_LOCATION", value = "-" },
    { name = "LOG_LEVEL", value = var.environment == "development" ? "DEBUG" : "INFO" },
  ]

  flagsmith_env_vars = concat(
    local.flagsmith_static_env_vars,
    local.flagsmith_logging_env_vars,
    local.config_env_vars,
  )

  # Static env vars for the Edge Proxy.
  edge_static_env_vars = [
    { name = "API_URL", value = "${local.flags_url}/api/v1" },
  ]

  edge_env_vars = concat(local.edge_static_env_vars, local.edge_config_env_vars)

  has_autoscaler = var.environment == "development" ? false : true
}
