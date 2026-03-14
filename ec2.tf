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
    apt-get install -y nodejs npm git nginx mysql-client
    systemctl start nginx
    systemctl enable nginx
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
