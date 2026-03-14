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

# RDS Outputs
output "rds_endpoint" {
  value       = aws_db_instance.mysql.endpoint
  description = "RDS MySQL endpoint"
}
