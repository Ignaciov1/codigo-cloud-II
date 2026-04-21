variable "region" {
  description = "Región de AWS"
  default     = "us-east-1"
}

variable "instance_type" {
  description = "Tipo de instancia EC2 (t3.micro para inicio, t3.medium para escala)"
  default     = "t3.micro" 
}

variable "db_instance_class" {
  description = "Clase de instancia RDS (db.t3.micro para inicio, db.t3.medium para escala)"
  default     = "db.t3.micro"
}