# Reuse-Configuration-Using-Terraform-Modules 
[![Build Status](https://travis-ci.org/joemccann/dillinger.svg?branch=master)](https://travis-ci.org/joemccann/dillinger)
<br />
<br />
A terraform project to automate the creation of a custom VPC instrasture from scratch using Terraform modules.

#### The code is built using the following versions:
| Provider | Terraform |
| ------ | ------ |
| terraform-provider-aws_v4.48.0_x5 | Terraform v1.3.6 |

## Requirements
- An IAM user with programmatic access with AmazonEC2FullAccess & AmazonRoute53FullAccess permissions attached.

## Why do you use modules? 
You might've created the infrastructure for all of your projects using the same code each time. If you decide to make it a module, this can be avoided. 
<br /> <br />
The module files need not have to be saved locally; they can instead be stored in github or even on AmazonS3. The module can be fetched from these sources using Terraform. <br /><br />
In this project I have configured terraform to read the modules from my modules repository: [AWS-VPC-Modules](https://github.com/sreehariskumar/AWS-VPC-Modules).

Use the following command to clone the repository
```s
git clone https://github.com/sreehariskumar/Reuse-Configuration-Using-Terraform-Modules
```
## Let's get started
### First, we will look into the contents of module files.

1. [AWS-VPC-Modules/variables.tf](https://github.com/sreehariskumar/AWS-VPC-Modules/blob/master/variables.tf) 

```s
locals {
  subnets = length(data.aws_availability_zones.available.names)
}
variable "project" {
  default = "test"
}
variable "environment" {}
variable "vpc_cidr" {}
variable "enable_nat_gateway" {
  type    = bool
  default = true
}
```
- We've created a local variable to create subnets depending on the number of availability in a particular region.
- The environment variable and the vpc_cidr block variable are configured to fetch input from the terraform variable file.
- The enable_nat_gateway variable is defined as a boolean function which accepts only true/false responses. We will look into this during configuration.

2. [AWS-VPC-Modules/datasourcce.tf](https://github.com/sreehariskumar/AWS-VPC-Modules/blob/master/datasourcce.tf)
```s
data "aws_availability_zones" "available" {
  state = "available"
}
```
- The datasource is defined to fetch the list of availability zones that are available in the particular region.

3. [AWS-VPC-Modules/output.tf](https://github.com/sreehariskumar/AWS-VPC-Modules/blob/master/output.tf)
```s
output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "public_subnets" {
  value = aws_subnet.public[*].id
}

output "private_subnets" {
  value = aws_subnet.private[*].id
}
```
- Output values are defined to print the value of defined resource which can be passed as input to other resources.

4. [AWS-VPC-Modules/main.tf](https://github.com/sreehariskumar/AWS-VPC-Modules/blob/master/main.tf)
```s
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.project}-${var.environment}"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.project}-${var.environment}"
  }
}

resource "aws_subnet" "public" {
  count                   = local.subnets
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.project}-${var.environment}-public${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count                   = local.subnets
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, "${local.subnets + count.index}")
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false
  tags = {
    Name = "${var.project}-${var.environment}-private${count.index + 1}"
  }
}

resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? 1 : 0
  vpc   = true
  tags = {
    Name = "${var.project}-${var.environment}-natgw"
  }
}

resource "aws_nat_gateway" "nat" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat.0.id
  subnet_id     = aws_subnet.public[0].id
  tags = {
    Name = "${var.project}-${var.environment}"
  }
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "${var.project}-${var.environment}-public"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.project}-${var.environment}-private"
  }
}

resource "aws_route" "enable_nat" {
  count                  = var.enable_nat_gateway ? 1 : 0
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.0.id
  depends_on             = [aws_route_table.private]
}

resource "aws_route_table_association" "public" {
  count          = local.subnets
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = local.subnets
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
```
- Create a VPC with public subnets and private subnet one for each availablility zone in the region
- Create an Internet Gateway for public access
- Creation of Elastic IP & NAT Gateway
- Adding public route for public access through Internet Gateway 
- Adding private route for public access thought NAT Gateway
- Associate public route tables with public subnets
- Associate private route tables with private subnets

#### Creation of Public & Private Subnets
```s
resource "aws_subnet" "public" {
  count                   = local.subnets
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.project}-${var.environment}-public${count.index + 1}"
  }
}
```
- The meta argument count will create one public subnets for each availability zone. This is achieved by meta argument combining with the locals variable we've defined earlier in the **variables.tf** file.
- The subnetting is calculated automatically with **cidrsubnet()** function.
- Identification of each subnet block is achieved using the **count.index** block
- The public subnets will be mapped with public ip using the **map_public_ip_on_launch** argument.

- Similarly, the private subnets are created.
- Public ip addresses will not be available for private subnets.

```s
resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? 1 : 0
  vpc   = true
  tags = {
    Name = "${var.project}-${var.environment}-natgw"
  }
}
```
- Understanding this part is tricky.
- Here, you could see that the variable **enable_nat_gateway** is defined as a IF condition.
- We may need to consider another file from the root directory: [prod.tfvars](https://github.com/sreehariskumar/Reuse-Configuration-Using-Terraform-Modules/blob/main/prod.tfvars)
```s
cidr_vpc      = "172.16.0.0/16"  
instance_type = "t2.micro"  
environment   = "prod"  
instance_ami  = "ami-0cca134ec43cf708f"  
enable_nat_gateway = true
```
- A tfvars file is used to create multiple environments for the same project by defining different values for the variables.
- We could see that the **enable_nat_gateway** argument is defined as true
- Also consider the [main.tf](https://github.com/sreehariskumar/Reuse-Configuration-Using-Terraform-Modules/blob/main/main.tf) file from the root directory:
```s
module "vpc" {
  source      = "github.com/sreehariskumar/AWS-VPC-Modules"
  project     = var.project
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
  enable_nat_gateway = var.enable_nat_gateway 
}
```
- Here we could see that the **enable_nat_gateway** argument depends on the variable **var.enable_nat_gateway**
- If the **enable_nat_gateway** argument is defined **true**, then:

>Count meta argument will be = 1 if var.enable_nat_gateway equal to “true” else >count =0. Moreover, count=1 means resource.aws_eip will run 1 time and one elastic ip will be created.

- If the **enable_nat_gateway** argument is defined **true**, then: elastic IP will not be created.

#### The same concept is used for the creation of NAT Gateway creation.
```s
resource "aws_nat_gateway" "nat" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat.0.id
  subnet_id     = aws_subnet.public[0].id
  tags = {
    Name = "${var.project}-${var.environment}"
  }
  depends_on = [aws_internet_gateway.igw]
}
```
- The **aws_nat_gateway** resource is executed only if the variable **enable_nat_gateway* is set to true, which will create the NAT gateway. 

```s
resource "aws_route" "enable_nat" {
  count                  = var.enable_nat_gateway ? 1 : 0
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.0.id
  depends_on             = [aws_route_table.private]
}
```
- You could see that the above resource is configured to run only if the variable **enable_nat_gateway** is set to **true**.
- To provide public access to the private subnet, a route entry should be added for traffic to pass through the NAT gateway.

### Now, we will look into the contents of project files.
#### [main.tf](https://github.com/sreehariskumar/Reuse-Configuration-Using-Terraform-Modules/blob/main/main.tf)
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
}```s
```
#### This configuration part is explained in detail in one of my earlier projects:
#### [Wordpress-Installation-via-Bastion-Server-using-Terraform](https://github.com/sreehariskumar/Wordpress-Installation-via-Bastion-Server-using-Terraform)


Run the following commands
```s
cd Reuse-Configuration-Using-Terraform-Modules
terraform init
terraform validate
terraform plan
terraform apply
```

<br />
<br />
Hi, 
With this project you've discovered how to use Terraform modules to automate the creation of infrastructure in this post. Now that you know how to use Terraform, you should feel confident in automating your AWS infrastructure.
