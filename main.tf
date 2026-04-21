provider "aws" {
  region = var.region
}

# --- BÚSQUEDA DE AMI UBUNTU 24.04 ---
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] 

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# --- RED (VPC /22 y Subredes) ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/22"
  enable_dns_hostnames = true
  tags = { Name = "VPC-TechNova" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# --- 2 Subredes Públicas (Web/Aplicación) ---
resource "aws_subnet" "public_web" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true
  
  # AQUI ESTÁ EL CAMBIO: El nombre que se verá en la consola
  tags = { Name = "Subred-Publica-Web-1A" } 
}

resource "aws_subnet" "public_web_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}b"
  map_public_ip_on_launch = true
  
  tags = { Name = "Subred-Publica-Web-1B" } 
}

# --- 2 Subredes Privadas (Datos) ---
resource "aws_subnet" "private_data_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.region}a"
  
  tags = { Name = "Subred-Privada-BD-1A" } 
}

resource "aws_subnet" "private_data_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.region}b"
  
  tags = { Name = "Subred-Privada-BD-1B" } 
}

# --- Tablas de Enrutamiento ---
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_web.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_assoc_2" {
  subnet_id      = aws_subnet.public_web_2.id
  route_table_id = aws_route_table.public_rt.id
}

# --- SEGURIDAD (Security Groups) [cite: 46] ---
resource "aws_security_group" "ec2_sg" {
  name   = "sg_web_server"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

resource "aws_security_group" "rds_sg" {
  name   = "sg_rds_mysql"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }
}

# --- REPOSITORIOS ECR [cite: 78] ---
resource "aws_ecr_repository" "frontend" { name = "tienda-tech-frontend" }
resource "aws_ecr_repository" "backend"  { name = "tienda-tech-backend" }

# --- CÓMPUTO (EC2 con Automatización) [cite: 40, 78] ---
resource "aws_instance" "web_app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_web.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name               = "vockey" 
  
  iam_instance_profile   = "LabInstanceProfile"

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y docker.io docker-compose-v2 git mysql-client-core-8.0 unzip
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ubuntu
              
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              unzip awscliv2.zip
              ./aws/install
              rm -rf awscliv2.zip ./aws
              EOF

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
    encrypted   = true # Cumple IE1.4 
  }

  tags = { Name = "EC2-TechNova-Solutions" }
}

resource "aws_eip" "web_eip" { instance = aws_instance.web_app.id }

# --- BASE DE DATOS (RDS MySQL 8.4) [cite: 41, 53] ---
resource "aws_db_subnet_group" "rds_subnets" {
  name       = "main-rds-group"
  subnet_ids = [aws_subnet.private_data_1.id, aws_subnet.private_data_2.id]
}

resource "aws_db_instance" "mysql_db" {
  allocated_storage      = 50
  engine                 = "mysql"
  engine_version         = "8.4"
  instance_class         = var.db_instance_class
  db_name                = "technovadb"
  username               = "admin"
  password               = "PasswordSegura123"
  db_subnet_group_name   = aws_db_subnet_group.rds_subnets.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true
  storage_encrypted      = true # Cumple IE1.4 
}