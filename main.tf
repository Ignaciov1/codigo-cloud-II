# ==============================================================================
# PROVEEDOR Y DATOS
# ==============================================================================
provider "aws" {
  region = var.region
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# Obtener automáticamente el ID de la cuenta actual para evitar el error 403
data "aws_caller_identity" "current" {}

# ==============================================================================
# CAPA 1: NETWORKING (VPC Y SUBREDES)
# ==============================================================================
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  tags                 = { Name = "VPC-TechNova-HA" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "IGW-TechNova" }
}

# Subredes Públicas (Capa Web)
resource "aws_subnet" "public_1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true
  tags                    = { Name = "Subred-Publica-1A" }
}

resource "aws_subnet" "public_1b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}b"
  map_public_ip_on_launch = true
  tags                    = { Name = "Subred-Publica-1B" }
}

# Subredes Privadas (Capa de Datos)
resource "aws_subnet" "private_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.region}a"
  tags              = { Name = "Subred-Privada-RDS-1A" }
}

resource "aws_subnet" "private_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.region}b"
  tags              = { Name = "Subred-Privada-RDS-1B" }
}

# Enrutamiento
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "pub_1a" {
  subnet_id      = aws_subnet.public_1a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "pub_1b" {
  subnet_id      = aws_subnet.public_1b.id
  route_table_id = aws_route_table.public_rt.id
}

# ==============================================================================
# CAPA 2: SEGURIDAD (SECURITY GROUPS)
# ==============================================================================
resource "aws_security_group" "alb_sg" {
  name   = "sg_alb_technova"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3001
    to_port     = 3001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2_sg" {
  name   = "sg_ec2_technova"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port       = 3001
    to_port         = 3001
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds_sg" {
  name   = "sg_rds_technova"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }
}

# ==============================================================================
# CAPA 3: ALTA DISPONIBILIDAD (ALB & ASG)
# ==============================================================================
resource "aws_lb" "web_alb" {
  name               = "technova-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]
}

resource "aws_lb_target_group" "web_tg" {
  name     = "technova-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_target_group" "backend_tg" {
  name     = "technova-tg-3001"
  port     = 3001
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-499"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

resource "aws_lb_listener" "backend_listener" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = "3001"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend_tg.arn
  }
}

resource "aws_launch_template" "web_template" {
  name_prefix   = "technova-tpl-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = "vockey"
  
  iam_instance_profile { name = "LabInstanceProfile" }

  network_interfaces {
    security_groups             = [aws_security_group.ec2_sg.id]
    associate_public_ip_address = true
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              # 1. Actualizar e instalar dependencias
              apt-get update -y
              apt-get install -y docker.io docker-compose-v2 git mysql-client-core-8.0 wget
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ubuntu

              # 2. Descargar el código
              cd /home/ubuntu
              git clone https://github.com/Ignaciov1/ECR-DOCKER-CLOUD-2.git
              cd ECR-DOCKER-CLOUD-2/tienda-tech-EC2

              # 3. Crear el archivo .env con TODAS las credenciales
              cat <<EOT > .env
              DB_HOST=${aws_db_instance.mysql_db.address}
              DB_USER=admin
              DB_PASSWORD=PasswordSegura123
              DB_NAME=technovadb
              EOT

              # 4. >>> INYECCIÓN SQL SEGURA E INTELIGENTE <<<
              TABLAS=$(mysql -h ${aws_db_instance.mysql_db.address} -u admin -pPasswordSegura123 -N -B -e "SHOW TABLES IN technovadb;")
              
              if [ -z "$TABLAS" ]; then
                echo "La base de datos está vacía. Ejecutando init.sql..."
                mysql -h ${aws_db_instance.mysql_db.address} -u admin -pPasswordSegura123 technovadb < /home/ubuntu/ECR-DOCKER-CLOUD-2/tienda-tech-EC2/tienda-tech-db/init.sql
              else
                echo "La base de datos ya tiene información. Protegiendo datos y omitiendo inyección..."
              fi

              # 5. CREAR EL SERVICIO SYSTEMD
              cat << 'EOT' > /etc/systemd/system/app-compose.service
              [Unit]
              Description=Servicio Docker Compose para TechNova
              Requires=docker.service
              After=docker.service

              [Service]
              Type=oneshot
              RemainAfterExit=yes
              WorkingDirectory=/home/ubuntu/ECR-DOCKER-CLOUD-2/tienda-tech-EC2
              ExecStart=/usr/bin/docker compose up -d --build
              ExecStop=/usr/bin/docker compose down

              [Install]
              WantedBy=multi-user.target
              EOT

              # 6. Activar y arrancar el servicio automáticamente
              systemctl daemon-reload
              systemctl enable app-compose.service
              systemctl start app-compose.service

              # 7. INSTALAR Y CONFIGURAR CLOUDWATCH AGENT
              cd /home/ubuntu
              wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
              dpkg -i -E ./amazon-cloudwatch-agent.deb
              
              cat << 'EOT' > /opt/aws/amazon-cloudwatch-agent/bin/config.json
              {
                "agent": {
                  "metrics_collection_interval": 60,
                  "run_as_user": "root"
                },
                "metrics": {
                  "append_dimensions": {
                    "InstanceId": "$${aws:InstanceId}"
                  },
                  "metrics_collected": {
                    "cpu": {
                      "measurement": ["cpu_usage_active"],
                      "metrics_collection_interval": 60,
                      "totalcpu": true
                    },
                    "mem": {
                      "measurement": ["mem_used_percent"],
                      "metrics_collection_interval": 60
                    },
                    "disk": {
                      "measurement": ["used_percent"],
                      "metrics_collection_interval": 60,
                      "resources": ["/"]
                    }
                  }
                }
              }
              EOT
              
              /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json
              EOF
  )
}

resource "aws_autoscaling_group" "web_asg" {
  vpc_zone_identifier = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]
  desired_capacity    = 1
  max_size            = 3
  min_size            = 1
  
  target_group_arns   = [
    aws_lb_target_group.web_tg.arn, 
    aws_lb_target_group.backend_tg.arn
  ]

  launch_template {
    id      = aws_launch_template.web_template.id
    version = "$Latest"
  }

  # ETIQUETA DE BACKUP: Vital para que la Capa 7 funcione automáticamente
  tag {
    key                 = "Backup"
    value               = "true"
    propagate_at_launch = true
  }

  # ETIQUETA DE NOMBRE: Para identificar las instancias en la consola de EC2
  tag {
    key                 = "Name"
    value               = "TechNova-Web-Server"
    propagate_at_launch = true
  }
}

# ==============================================================================
# CAPA 4: BASE DE DATOS (RDS MULTI-AZ)
# ==============================================================================
resource "aws_db_subnet_group" "rds_subnets" {
  name       = "rds-subnet-group"
  subnet_ids = [aws_subnet.private_1a.id, aws_subnet.private_1b.id]
}

resource "aws_db_instance" "mysql_db" {
  allocated_storage      = 50
  engine                 = "mysql"
  engine_version         = "8.4"
  instance_class         = var.db_instance_class
  db_name                = "technovadb"
  username               = "admin"
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.rds_subnets.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true
  storage_encrypted      = true
  multi_az               = true
}

# ==============================================================================
# CAPA 5: REPOSITORIOS ECR (CONTENEDORES)
# ==============================================================================
resource "aws_ecr_repository" "frontend" { 
  name = "tienda-tech-frontend" 
}

resource "aws_ecr_repository" "backend" { 
  name = "tienda-tech-backend" 
}

# ==============================================================================
# CAPA 6: OBSERVABILIDAD Y MONITOREO (CLOUDWATCH Y SNS)
# ==============================================================================
resource "aws_sns_topic" "alertas_technova" {
  name = "technova-alertas-topic"
}

resource "aws_sns_topic_subscription" "alerta_email" {
  topic_arn = aws_sns_topic.alertas_technova.arn
  protocol  = "email"
  endpoint  = "ig.sariego@duocuc.cl" 
}

resource "aws_cloudwatch_metric_alarm" "cpu_alta" {
  alarm_name          = "TechNova-CPU-Alta"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Se activará si el promedio de CPU del ASG supera el 80%."
  alarm_actions       = [aws_sns_topic.alertas_technova.arn]
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_asg.name
  }
}

resource "aws_cloudwatch_dashboard" "dashboard_ec2_nuevo" {
  dashboard_name = "TechNova-Dashboard-Graficos" 
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric",
        x      = 0, y = 0, width = 8, height = 6,
        properties = {
          metrics = [
            [ { "expression": "SEARCH('Namespace=\"CWAgent\" MetricName=\"cpu_usage_active\"', 'Average', 60)", "id": "q1" } ]
          ],
          view    = "singleValue",
          region  = "us-east-1",
          title   = "Uso de CPU por Instancia (%)"
        }
      },
      {
        type   = "metric",
        x      = 8, y = 0, width = 8, height = 6,
        properties = {
          metrics = [
            [ { "expression": "SEARCH('Namespace=\"CWAgent\" MetricName=\"mem_used_percent\"', 'Average', 60)", "id": "q2" } ]
          ],
          view    = "gauge",
          yAxis   = { left = { min = 0, max = 100 } },
          region  = "us-east-1",
          title   = "RAM por Instancia (%)"
        }
      },
      {
        type   = "metric",
        x      = 16, y = 0, width = 8, height = 6,
        properties = {
          metrics = [
            [ { "expression": "SEARCH('Namespace=\"CWAgent\" MetricName=\"disk_used_percent\"', 'Average', 60)", "id": "q3" } ]
          ],
          view    = "pie",
          region  = "us-east-1",
          title   = "Disco por Instancia (%)"
        }
      }
    ]
  })
}

resource "aws_cloudwatch_dashboard" "dashboard_rds" {
  dashboard_name = "TechNova-Monitor-RDS"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric",
        x      = 0, y = 0, width = 8, height = 3,
        properties = {
          metrics = [ ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.mysql_db.identifier] ],
          view    = "singleValue",
          region  = "us-east-1",
          stat    = "Average",
          period  = 300,
          title   = "CPU RDS (%)"
        }
      },
      {
        type   = "metric",
        x      = 8, y = 0, width = 8, height = 3,
        properties = {
          metrics = [ ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.mysql_db.identifier] ],
          view    = "singleValue",
          region  = "us-east-1",
          stat    = "Average",
          period  = 300,
          title   = "Conexiones DB (Actuales)"
        }
      },
      {
        type   = "metric",
        x      = 16, y = 0, width = 8, height = 3,
        properties = {
          metrics = [ ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", aws_db_instance.mysql_db.identifier] ],
          view    = "singleValue",
          region  = "us-east-1",
          stat    = "Average",
          period  = 300,
          title   = "Memoria RAM Libre DB (Bytes)"
        }
      }
    ]
  })
}

# ==============================================================================
# CAPA 7: BACKUP Y RECUPERACIÓN (REQUISITO PRUEBA 8)
# ==============================================================================
resource "aws_backup_vault" "technova_vault" {
  name        = "BovedaTechNova-IaC"
}

resource "aws_backup_plan" "technova_plan" {
  name = "PlanContingenciaTechNova"

  rule {
    rule_name         = "RespaldoDiario7Dias"
    target_vault_name = aws_backup_vault.technova_vault.name
    
    # CRON CORREGIDO: 04:30 AM UTC equivale exactamente a las 00:30 AM en Chile actual.
    schedule          = "cron(35 21 * * ? *)"

    lifecycle {
      delete_after = 7
    }
  }
}

resource "aws_backup_selection" "technova_selection" {
  iam_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
  
  name         = "SeleccionRecursosTechNova"
  plan_id      = aws_backup_plan.technova_plan.id

  resources = [
    aws_db_instance.mysql_db.arn
  ]

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = "true"
  }
}