#----------------------------------------------
# fetching the modules from a GitHub repository
#----------------------------------------------

module "vpc" {
  source             = "github.com/sreehariskumar/AWS-VPC-Modules"
  project            = var.project
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  enable_nat_gateway = var.enable_nat_gateway
}

#----------------------------------------------
# creating a prefix list to be add public ip's into security groups
#----------------------------------------------

resource "aws_ec2_managed_prefix_list" "prefix_list" {
  name           = "${var.project}-${var.environment}-prefixlist"
  address_family = "IPv4"
  max_entries    = length(var.public_ips)
  dynamic "entry" {
    for_each = var.public_ips
    iterator = ip
    content {
      cidr = ip.value
    }
  }

  tags = {
    Name = "${var.project}-${var.environment}-prefixlist"
  }
}


#----------------------------------------------
# creating security group for bastion server
#----------------------------------------------

resource "aws_security_group" "bastion" {
  name_prefix = "${var.project}-${var.environment}-bastion-"
  description = "Allow 22 from prefixlist"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = var.bastion_ports
    to_port         = var.bastion_ports
    protocol        = "tcp"
    prefix_list_ids = [aws_ec2_managed_prefix_list.prefix_list.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project}-${var.environment}-bastion"
  }
}


#----------------------------------------------
# creating security group for backend server
#----------------------------------------------

resource "aws_security_group" "backend" {
  name_prefix = "${var.project}-${var.environment}-backend-"
  description = "Allow 22 from bastion & 3306 access from frontend"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = var.backend_ports
    to_port         = var.backend_ports
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }

  ingress {
    from_port       = var.bastion_ports
    to_port         = var.bastion_ports
    protocol        = "tcp"
    cidr_blocks     = var.ssh_to_backend == true ? ["0.0.0.0/0"] : null
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project}-${var.environment}-backend"
  }
}


#----------------------------------------------
# creating security group for frontend server
#----------------------------------------------

resource "aws_security_group" "frontend" {
  name_prefix = "${var.project}-${var.environment}-frontend-"
  description = "allow 22 from bastion & frontend_ports traffic"
  vpc_id      = module.vpc.vpc_id

  dynamic "ingress" {
    for_each = toset(var.frontend_ports)
    iterator = port
    content {
      from_port        = port.value
      to_port          = port.value
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  ingress {
    from_port       = var.bastion_ports
    to_port         = var.bastion_ports
    protocol        = "tcp"
    cidr_blocks     = var.ssh_to_frontend == true ? ["0.0.0.0/0"] : null
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    "Name" = "${var.project}-${var.environment}-frontend"
  }
}


resource "local_file" "backend" {
  filename = "backend.txt"
  content  = data.template_file.backend.rendered
}

resource "local_file" "frontend" {
  filename = "frontend.txt"
  content  = data.template_file.frontend.rendered
}



#----------------------------------------------
# creating a ssh key pair
#----------------------------------------------

resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}


#----------------------------------------------
# importing private key
#----------------------------------------------

resource "aws_key_pair" "ssh_key" {
  key_name   = "${var.project}-${var.environment}"
  public_key = tls_private_key.key.public_key_openssh
  provisioner "local-exec" {
    command = "echo '${tls_private_key.key.private_key_pem}' > ./mykey.pem ; chmod 400 ./mykey.pem"
  }
  provisioner "local-exec" {
    when    = destroy
    command = "rm -rf ./mysshkey.pem"
  }

  tags = {
    "Name" = "${var.project}-${var.environment}"
  }
}


#----------------------------------------------
# launching bastion instance
#----------------------------------------------

resource "aws_instance" "bastion" {
  ami                         = var.instance_ami
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.ssh_key.key_name
  associate_public_ip_address = true
  subnet_id                   = module.vpc.public_subnets.0
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  user_data                   = file("bastion.sh")
  user_data_replace_on_change = true

  tags = {
    Name = "${var.project}-${var.environment}-bastion"
  }
}


#----------------------------------------------
# launching frontend instance
#----------------------------------------------

resource "aws_instance" "frontend" {
  ami                         = var.instance_ami
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.ssh_key.key_name
  associate_public_ip_address = true
  subnet_id                   = module.vpc.public_subnets.1
  vpc_security_group_ids      = [aws_security_group.frontend.id]
  user_data                   = data.template_file.frontend.rendered
  user_data_replace_on_change = true
  depends_on                  = [aws_instance.backend]

  tags = {
    Name = "${var.project}-${var.environment}-frontend"
  }
}


#----------------------------------------------
# launching backend instance
#----------------------------------------------

resource "aws_instance" "backend" {
  ami                         = var.instance_ami
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.ssh_key.key_name
  associate_public_ip_address = false
  subnet_id                   = module.vpc.private_subnets.0
  vpc_security_group_ids      = [aws_security_group.backend.id]
  user_data                   = data.template_file.backend.rendered
  user_data_replace_on_change = true
  depends_on                  = [module.vpc]

  tags = {
    Name = "${var.project}-${var.environment}-backend"
  }
}


#----------------------------------------------
# creating a private hosted zone
#----------------------------------------------

resource "aws_route53_zone" "private" {
  name = var.private_domain
  vpc {
    vpc_id = module.vpc.vpc_id
  }
}


#----------------------------------------------
# creating a record in private hosted zone to access db host
#----------------------------------------------

resource "aws_route53_record" "db" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "db.${var.private_domain}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.backend.private_ip]
}


#----------------------------------------------
# create a record in public hosted zone to access the wp site
#----------------------------------------------

resource "aws_route53_record" "wordpress" {
  zone_id = data.aws_route53_zone.mydomain.zone_id
  name    = "wordpress.${var.public_domain}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.frontend.public_ip]
}
