module "vpc" {
  source      = "github.com/sreehariskumar/AWS-VPC-Modules"
  project     = var.project
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
  enable_nat_gateway = var.enable_nat_gateway 
}

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


resource "aws_security_group" "bastion" {
  name_prefix = "${var.project}-${var.environment}-bastion-"
  description = "Allow 22 from prefixlist"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 22
    to_port         = 22
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


resource "aws_security_group" "backend" {
  name_prefix = "${var.project}-${var.environment}-backend-"
  description = "Allow 22 from bastion server and 3306 access from frontend"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = var.backend_ports
    to_port         = var.backend_ports
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
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


resource "aws_security_group" "frontend" {
  name_prefix = "${var.project}-${var.environment}-frontend-"
  description = "allow 22 & frontend_ports traffic"
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

resource "aws_key_pair" "ssh_key" {
  key_name   = "${var.project}-${var.environment}"
  public_key = file("mykey.pub")
  tags = {
    "Name" = "${var.project}-${var.environment}"
  }
}

resource "aws_instance" "bastion" {
  ami                         = var.instance_ami
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.ssh_key.key_name
  associate_public_ip_address = true
  subnet_id                   = module.vpc.public_subnets.1
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  user_data                   = file("bastion.sh")
  user_data_replace_on_change = true
  tags = {
    Name = "${var.project}-${var.environment}-bastion"
  }
}

resource "aws_instance" "frontend" {
  ami                         = var.instance_ami
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.ssh_key.key_name
  associate_public_ip_address = true
  subnet_id                   = module.vpc.public_subnets.0
  vpc_security_group_ids      = [aws_security_group.frontend.id]
  user_data                   = data.template_file.frontend.rendered
  user_data_replace_on_change = true
  tags = {
    Name = "${var.project}-${var.environment}-frontend"
  }
  depends_on = [aws_instance.backend]
}

resource "aws_instance" "backend" {
  ami                         = var.instance_ami
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.ssh_key.key_name
  associate_public_ip_address = false
  subnet_id                   = module.vpc.private_subnets.0
  vpc_security_group_ids      = [aws_security_group.backend.id]
  user_data                   = data.template_file.backend.rendered
  user_data_replace_on_change = true
  tags = {
    Name = "${var.project}-${var.environment}-backend"
  }
  depends_on = [module.vpc.nat]
}

resource "aws_route53_zone" "private" {
  name = var.private_domain
  vpc {
    vpc_id = module.vpc.vpc_id
  }
}

resource "aws_route53_record" "db" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "db.${var.private_domain}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.backend.private_ip]
}

resource "aws_route53_record" "wordpress" {
  zone_id = data.aws_route53_zone.mydomain.zone_id
  name    = "wordpress.${var.public_domain}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.frontend.public_ip]
}
