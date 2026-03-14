# EpicBook Full-Stack Web Application on AWS — Terraform Deployment Guide

Deployed and documented by **Osenat Alonge** | Senior DevOps Engineer | TOVADEL Academy

---

## What You Will Build

A fully production-ready full-stack EpicBook application on AWS using pure Terraform. EC2 instance running Node.js/Express backend with Nginx as reverse proxy, connected to Amazon RDS MySQL database in a private subnet.

```
Internet
    │
    ▼
EC2 Instance — Node.js + Nginx (public subnet)
    │
    ▼
Amazon RDS MySQL (private subnet)
```

---

## Architecture Overview

| Component | Service | Subnet | Access |
|-----------|---------|--------|--------|
| Web + App | EC2 Ubuntu 22.04 | 10.0.1.0/24 (public) | Public via port 80 |
| Database | Amazon RDS MySQL 8.0 | 10.0.2.0/24 (private) | EC2 only on port 3306 |

---

## Prerequisites

Before you start make sure you have the following installed and configured:

```bash
# Check AWS CLI
aws --version
aws sts get-caller-identity

# Check Terraform
terraform -v

# Check Git
git --version
```

---

## Project Structure

```
terraform-epicbook-aws/
├── main.tf        # Provider + VPC + Networking + Security Groups
├── rds.tf         # Amazon RDS MySQL instance
├── ec2.tf         # EC2 instance + outputs
└── .gitignore     # Protects sensitive files
```

---

## Step 1 — Create the Project Directory

```bash
mkdir terraform-epicbook-aws
cd terraform-epicbook-aws
```

---

## Step 2 — Create main.tf

This file contains the AWS provider, VPC, public and private subnets, Internet Gateway, route tables and security groups for EC2 and RDS.

```bash
cat > main.tf << 'EOF'
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "epicbook-vpc" }
}

# Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = { Name = "epicbook-public-subnet" }
}

# Private Subnet for RDS
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = { Name = "epicbook-private-subnet" }
}

# Extra Private Subnet for RDS Subnet Group
resource "aws_subnet" "private2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1c"

  tags = { Name = "epicbook-private-subnet-2" }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "epicbook-igw" }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "epicbook-public-rt" }
}

# Route Table Association
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# EC2 Security Group
resource "aws_security_group" "ec2" {
  name        = "epicbook-ec2-sg"
  description = "Allow SSH, HTTP and app port"
  vpc_id      = aws_vpc.main.id

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
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "epicbook-ec2-sg" }
}

# RDS Security Group
resource "aws_security_group" "rds" {
  name        = "epicbook-rds-sg"
  description = "Allow MySQL from EC2 only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "epicbook-rds-sg" }
}
EOF
```

---

## Step 3 — Create rds.tf

This file provisions the RDS MySQL instance in a private subnet group.

```bash
cat > rds.tf << 'EOF'
# RDS Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "epicbook-db-subnet-group"
  subnet_ids = [aws_subnet.private.id, aws_subnet.private2.id]

  tags = { Name = "epicbook-db-subnet-group" }
}

# RDS MySQL Instance
resource "aws_db_instance" "mysql" {
  identifier             = "epicbook-mysql"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = "bookstore"
  username               = "epicadmin"
  password               = "Epic12345678"
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  skip_final_snapshot    = true

  tags = { Name = "epicbook-mysql" }
}

# RDS Output
output "rds_endpoint" {
  value       = aws_db_instance.mysql.endpoint
  description = "RDS MySQL endpoint"
}
EOF
```

---

## Step 4 — Create ec2.tf

This file launches the EC2 instance with Nginx and Node.js pre-installed via user_data.

```bash
cat > ec2.tf << 'EOF'
resource "aws_instance" "epicbook" {
  ami                         = "ami-0261755bbcb8c4a84"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  associate_public_ip_address = true
  key_name                    = "olusola"

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get upgrade -y
    apt-get install -y git nginx mysql-client
    systemctl start nginx
    systemctl enable nginx
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
  EOF

  tags = { Name = "epicbook-ec2" }
}

output "ec2_public_ip" {
  value       = aws_instance.epicbook.public_ip
  description = "Public IP of EC2 instance"
}

output "app_url" {
  value       = "http://${aws_instance.epicbook.public_ip}"
  description = "EpicBook app URL"
}

output "ssh_command" {
  value       = "ssh -i ~/.ssh/id_rsa ubuntu@${aws_instance.epicbook.public_ip}"
  description = "SSH command"
}
EOF
```

> **Note:** Replace `olusola` with your own AWS key pair name. If you do not have one create it with:
> ```bash
> aws ec2 create-key-pair --key-name my-key --query "KeyMaterial" --output text > ~/.ssh/my-key.pem
> chmod 400 ~/.ssh/my-key.pem
> ```

---

## Step 5 — Create .gitignore

```bash
cat > .gitignore << 'EOF'
*.tfstate
*.tfstate.backup
*.tfstate.lock.info
tfplan
*.tfplan
.terraform/
.terraform.lock.hcl
crash.log
*.tfvars
*.tfvars.json
.env
.env.local
*.pem
*.key
.DS_Store
*.log
EOF
```

---

## Step 6 — Run Terraform Pipeline

```bash
# Initialise
terraform init

# Validate
terraform validate

# Plan
terraform plan

# Apply — RDS takes 5-10 minutes
terraform apply
```

Type `yes` when prompted.

---

## Step 7 — Get Outputs

```bash
terraform output
```

Save the following values — you will need them:
- `ec2_public_ip` — to SSH into the instance
- `rds_endpoint` — to configure the database connection

---

## Step 8 — SSH Into EC2

```bash
ssh -i ~/.ssh/id_rsa ubuntu@<ec2-public-ip>
```

---

## Step 9 — Verify Node.js Version

```bash
node -v
```

If it shows v10 upgrade to v18:

```bash
sudo apt remove -y nodejs npm
sudo apt autoremove -y
sudo dpkg --purge nodejs
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs
node -v
```

---

## Step 10 — Clone and Configure EpicBook

```bash
git clone https://github.com/pravinmishraaws/theepicbook.git
cd theepicbook
```

Update the database config using Python to avoid JSON issues:

```bash
python3 << 'PYEOF'
import json
config = {
    "development": {
        "username": "epicadmin",
        "password": "Epic12345678",
        "database": "bookstore",
        "host": "<your-rds-endpoint-without-port>",
        "dialect": "mysql",
        "dialectOptions": {
            "ssl": {
                "rejectUnauthorized": False
            }
        }
    },
    "test": {
        "username": "epicadmin",
        "password": "Epic12345678",
        "database": "bookstore",
        "host": "<your-rds-endpoint-without-port>",
        "dialect": "mysql"
    },
    "production": {
        "username": "epicadmin",
        "password": "Epic12345678",
        "database": "bookstore",
        "host": "<your-rds-endpoint-without-port>",
        "dialect": "mysql"
    }
}
with open('config/config.json', 'w') as f:
    json.dump(config, f, indent=2)
print('Config written successfully')
PYEOF
```

> **Important:** Use the RDS endpoint WITHOUT the port number. Remove `:3306` from the end.

---

## Step 11 — Import Database

```bash
# Import schema
mysql -h <rds-endpoint> -u epicadmin -pEpic12345678 bookstore < db/BuyTheBook_Schema.sql

# Import authors
mysql -h <rds-endpoint> -u epicadmin -pEpic12345678 bookstore < db/author_seed.sql

# Import books
mysql -h <rds-endpoint> -u epicadmin -pEpic12345678 bookstore < db/books_seed.sql

# Verify tables
mysql -h <rds-endpoint> -u epicadmin -pEpic12345678 bookstore -e "show tables;"
```

---

## Step 12 — Install and Start the App

```bash
cd ~/theepicbook
npm install

# Install PM2
sudo npm install -g pm2

# Kill any existing process on port 8080
sudo kill -9 $(sudo lsof -t -i:8080) 2>/dev/null

# Start with PM2
pm2 start server.js --name epicbook
pm2 save
pm2 status
```

---

## Step 13 — Configure Nginx

```bash
sudo tee /etc/nginx/sites-available/default << 'EOF'
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx
```

---

## Step 14 — Verify Deployment

Open in browser:
```
http://<ec2-public-ip>
```

You should see the EpicBook application with:
- Home page loading correctly
- Books displayed from the database
- Navigation to Gallery, Products and Cart working
- Add to Cart and Checkout flow connected to MySQL

---

## Step 15 — Push to GitHub

```bash
# Exit EC2 first
exit

# Initialise git in project folder
cd ~/terraform-epicbook-aws
git init
git remote add origin https://github.com/<your-username>/terraform-epicbook-aws.git
git add .
git status
git commit -m "EpicBook full-stack deployment on AWS with Terraform"
git push -u origin main
```

---

## Step 16 — Destroy Resources

Always destroy after testing to avoid unnecessary AWS costs:

```bash
terraform destroy --auto-approve
```

---

## Common Issues and Fixes

### Issue 1 — RDS Password Invalid
AWS RDS does not allow special characters like `@` in passwords.

**Fix:** Use alphanumeric passwords only:
```
Epic12345678   ✅ correct
Epic@12345678  ❌ rejected
```

### Issue 2 — Node.js v10 Too Old
Ubuntu VMs on AWS come with Node.js v10 by default. The application requires Node 18.

**Fix:**
```bash
sudo apt remove -y nodejs npm
sudo apt autoremove -y
sudo dpkg --purge nodejs
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs
```

### Issue 3 — JSON Syntax Error in config.json
Manual editing of config.json can introduce syntax errors causing the app to crash.

**Fix:** Always use Python to write JSON files:
```bash
python3 -c "import json; print(json.dumps(json.load(open('config/config.json')), indent=2))"
```

### Issue 4 — Port 8080 Already in Use
A previous Node.js process is still running on port 8080.

**Fix:**
```bash
sudo kill -9 $(sudo lsof -t -i:8080)
pm2 start server.js --name epicbook
```

### Issue 5 — RDS Endpoint Includes Port
The config.json host field must not include the port number.

**Fix:** Use only the hostname part:
```
epicbook-mysql.xxxx.us-east-1.rds.amazonaws.com    ✅ correct
epicbook-mysql.xxxx.us-east-1.rds.amazonaws.com:3306  ❌ wrong
```

### Issue 6 — Cannot Connect to RDS
The EC2 security group is not in the RDS security group inbound rules.

**Fix:** Verify the RDS security group allows port 3306 from the EC2 security group ID — not from a CIDR block.

---

## Tech Stack

| Tool | Purpose |
|------|---------|
| Terraform | Infrastructure as Code |
| AWS VPC | Network isolation |
| AWS EC2 | Application server |
| Amazon RDS MySQL 8.0 | Managed database |
| Node.js 18 | Application runtime |
| Nginx | Reverse proxy |
| PM2 | Process manager |
| Sequelize | ORM for MySQL |

---

## Author

**Osenat Alonge**
Senior DevOps Engineer | Founder of TOVADEL Academy

LinkedIn: linkedin.com/in/osenat-alonge-84379124b
GitHub: github.com/etaoko333
TOVADEL Academy: tovadelacademy.co.uk

---

## Acknowledgements

This project was completed as part of the DevOps Micro Internship (DMI) Cohort-2 organised by Pravin Mishra.

Application Repository: https://github.com/pravinmishraaws/theepicbook
Join DMI free: https://lnkd.in/dzJGHptZ
