output "vpc-module-return" {
  value = module.vpc
}

#the URL to access the site
output "WordPress-URL" {
  value = "http://${aws_route53_record.wordpress.name}"
}
