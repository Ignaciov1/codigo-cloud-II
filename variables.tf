variable "region" {
  description = "Región de AWS"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "Bloque de direcciones IP para la VPC"
  type        = string
  default     = "10.0.0.0/22"
}

variable "instance_type" {
  description = "Tipo de instancia EC2 para el Auto Scaling Group (Actualizado a t3.small por diagrama HA)"
  type        = string
  default     = "t3.small" 
}

variable "db_instance_class" {
  description = "Clase de instancia RDS (Actualizado a db.t3.small por diagrama HA)"
  type        = string
  default     = "db.t3.small"
}

variable "db_password" {
  description = "Contraseña maestra de la base de datos RDS"
  type        = string
  sensitive   = true
  default     = "PasswordSegura123"
}