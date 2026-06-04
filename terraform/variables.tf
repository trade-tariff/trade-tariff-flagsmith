variable "environment" {
  description = "Deployment environment."
  type        = string
}

variable "region" {
  description = "AWS region to use."
  type        = string
}

variable "flagsmith_tag" {
  description = "Docker Hub tag for the flagsmith/flagsmith image."
  type        = string
  default     = "latest"
}

variable "edge_proxy_tag" {
  description = "Docker Hub tag for the flagsmith/edge-proxy image."
  type        = string
  default     = "latest"
}

variable "cpu" {
  description = "CPU units to use for each service."
  type        = number
}

variable "memory" {
  description = "Memory to allocate in MB for each service. Powers of 2 only."
  type        = number
}

variable "service_count" {
  description = "Desired number of tasks per service."
  type        = number
}

variable "min_capacity" {
  description = "Smallest number of tasks the service can scale-in to."
  type        = number
}

variable "max_capacity" {
  description = "Largest number of tasks the service can scale-out to."
  type        = number
}
