variable "aws_region" {
  description = "Región AWS por defecto"
  type        = string
  default     = "mx-central-1"
}

variable "project_name" {
  description = "Prefijo de recursos del proyecto"
  type        = string
  default     = "aditsystem"
}

variable "environment" {
  description = "Entorno (dev, staging, prod)"
  type        = string
}
