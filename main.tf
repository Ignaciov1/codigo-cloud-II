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

  # --- NUEVO: Permite tráfico al balanceador por el puerto 3001 ---
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

  # --- NUEVO: Permite a las EC2 recibir tráfico del balanceador en el 3001 ---
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

# --- NUEVO: Target Group para Backend (Puerto 3001) ---
resource "aws_lb_target_group" "backend_tg" {
  name     = "technova-tg-3001"
  port     = 3001
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  # --- NUEVO: Health Check tolerante para la API (acepta 404) ---
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

# --- NUEVO: Listener para Puerto 3001 ---
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
              apt-get update -y
              apt-get install -y docker.io docker-compose-v2 git mysql-client-core-8.0
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ubuntu
              EOF
  )
}

resource "aws_autoscaling_group" "web_asg" {
  vpc_zone_identifier = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]
  desired_capacity    = 2
  max_size            = 4
  min_size            = 2
  
  # --- ACTUALIZADO: Registrar en ambos grupos (80 y 3001) ---
  target_group_arns   = [
    aws_lb_target_group.web_tg.arn, 
    aws_lb_target_group.backend_tg.arn
  ]

  launch_template {
    id      = aws_launch_template.web_template.id
    version = "$Latest"
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