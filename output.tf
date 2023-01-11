output "vpc-module-return" {
  value = module.vpc
}

output "WordPress-URL" {
  value = "http://${aws_route53_record.wordpress.name}"
}

output "backend" {
  value = data.template_file.backend.rendered
}

output "frontend" {
  value = data.template_file.frontend.rendered
}
