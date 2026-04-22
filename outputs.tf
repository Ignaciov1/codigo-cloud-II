output "dns_balanceador" {
  description = "URL Maestra para acceder a la aplicación TechNova (Reemplaza a la antigua IP Pública)"
  value       = "http://${aws_lb.web_alb.dns_name}"
}

output "rds_endpoint" {
  description = "Endpoint de la base de datos RDS"
  value       = aws_db_instance.mysql_db.endpoint
}

output "ecr_repository_url_frontend" {
  description = "URL del repositorio ECR para el Frontend"
  value       = aws_ecr_repository.frontend.repository_url
}

output "ecr_repository_url_backend" {
  description = "URL del repositorio ECR para el Backend"
  value       = aws_ecr_repository.backend.repository_url
}