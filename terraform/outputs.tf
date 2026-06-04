output "flagsmith_url" {
  description = "Public URL for the Flagsmith dashboard and API."
  value       = local.flags_url
}

output "edge_proxy_url" {
  description = "Public URL for the Flagsmith Edge Proxy."
  value       = local.edge_origin
}
