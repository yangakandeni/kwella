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
