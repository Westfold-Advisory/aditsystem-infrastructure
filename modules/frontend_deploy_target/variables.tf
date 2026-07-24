variable "project_name" {
  description = "Prefijo base del proyecto"
  type        = string
}

variable "environment" {
  description = "Nombre corto del entorno para recursos AWS"
  type        = string
}

variable "aws_region" {
  description = "Región AWS donde se crea el bucket frontend"
  type        = string
}

variable "frontend_repository_owner" {
  description = "Owner del repositorio frontend en GitHub"
  type        = string
}

variable "frontend_repository_name" {
  description = "Nombre del repositorio frontend en GitHub"
  type        = string
}

variable "github_environment_name" {
  description = "Nombre del GitHub Environment usado por el workflow frontend"
  type        = string
}

variable "bucket_name_override" {
  description = "Nombre explícito del bucket frontend; si no se indica se deriva automáticamente"
  type        = string
  default     = null
}

variable "cloudfront_distribution_id" {
  description = "Distribution ID de CloudFront; habilita permisos de invalidación cuando no está vacío"
  type        = string
  default     = ""
}
