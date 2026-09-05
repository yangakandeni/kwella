variable "project_name" {
  description = "The name of the project, used as a prefix for all named resources."
  type        = string
  default     = "kwella"
}

variable "environment" {
  description = "The deployment environment (e.g. production, staging, dev)."
  type        = string
  default     = "production"
}

variable "aws_region" {
  description = "The AWS region in which all resources will be provisioned."
  type        = string
  default     = "af-south-1"
}

variable "flat_rate_zar" {
  description = <<-EOT
    Config-level flat rate (ZAR, per passenger seat) used by the bidding
    engine's fare floor: total_fare >= flat_rate x 6 seats (README.md §3A).
    Deliberately a Terraform variable rather than a code constant, since it
    moves with fuel-price hikes and must be changeable without a redeploy.
  EOT
  type        = number
  default     = 10.00
}
