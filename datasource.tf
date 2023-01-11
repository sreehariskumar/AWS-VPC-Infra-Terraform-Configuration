data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_route53_zone" "mydomain" {
  name         = var.public_domain
  private_zone = false
}

data "template_file" "backend" {
  template = file("${path.module}/backend.sh")
  vars = {
    DB_NAME = var.db_name
    DB_USER = var.db_user
    DB_PASS = var.db_pass
  }
}

data "template_file" "frontend" {
  template = file("${path.module}/frontend.sh")
  vars = {
    DB_NAME = var.db_name
    DB_USER = var.db_user
    DB_PASS = var.db_pass
    DB_HOST = local.db_host
  }
}
