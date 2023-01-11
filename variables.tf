variable "project" {
  default     = "zomato"
  description = "project name"
}

variable "environment" {
  default     = "production"
  description = "project env"
}

variable "region" {
  default     = "ap-south-1"
  description = "project region"
}

variable "access_key" {
  default = "AKIASXJHQP6OXN7WYWF7"
  #description = project access key
}

variable "secret_key" {
  default = "Z9FkwaoBargnrt06J8i7ZVu/A+cj9Na3QhTzPzOt"
  #description = project secret key
}

variable "instance_ami" {
  default = "ami-0cca134ec43cf708f"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "vpc_cidr" {
  default = "172.16.0.0/16"
}

variable "private_domain" {
  default     = "sreehari.local"
  description = "domain in private hosted zone"
}

variable "public_domain" {
  default     = "1by2.online"
  description = "record to access wordpress website"
}

variable "db_name" {
  default = "wordpress"
}

variable "db_user" {
  default = "wordpress"
}

variable "db_pass" {
  default = "wordpress"
}

locals {
  db_host = "db.${var.private_domain}"
}

variable "public_ips" {
  type = list(string)
  default = [
    "49.37.233.72/32"
  ]
}

variable "frontend_ports" {
  type    = list(string)
  default = ["80", "443", "8080"]
}

variable "ssh_to_frontend" {
  default = false
}

variable "ssh_to_backend" {
  default = false
}

variable "backend_ports" {
  type    = number
  default = 3306
}

variable "bastion_ports" {
  type    = number
  default = 22
}

locals {
  common_tags = {
    "project"     = var.project
    "environemnt" = var.environment
  }
}
