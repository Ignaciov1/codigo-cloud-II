output "ec2_public_ip" {
  description = "IP Pública de la instancia EC2"
  value       = aws_eip.web_eip.public_ip
}

output "rds_endpoint" {
  description = "Endpoint de la base de datos RDS"
  value       = aws_db_instance.mysql_db.endpoint
}

output "ecr_repository_url_frontend" {
  value = aws_ecr_repository.frontend.repository_url
}

output "ecr_repository_url_backend" {
  value = aws_ecr_repository.backend.repository_url
}