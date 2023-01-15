# Reuse-Configuration-Using-Terraform-Modules 
[![Build Status](https://travis-ci.org/joemccann/dillinger.svg?branch=master)](https://travis-ci.org/joemccann/dillinger)
<br />
A terraform project to automate the creation of a custom VPC instrasture from scratch using Terraform modules.

#### The code is built using the following versions:
| Provider | Terraform |
| ------ | ------ |
| terraform-provider-aws_v4.48.0_x5 | Terraform v1.3.6 |

## Requirements
- An IAM user with programmatic access with AmazonEC2FullAccess & AmazonRoute53FullAccess permissions attached.

## Why do you use modules? 
You might've created the infrastructure for all of your projects using the same code each time. If you decide to make it a module, this can be avoided. <br /><br />
The module files need not have to be saved locally; they can instead be stored in github or even on AmazonS3. The module can be fetched from these sources using Terraform. <br /><br />
In this project I have configured terraform to read the modules from my modules repository: [AWS-VPC-Modules](https://github.com/sreehariskumar/AWS-VPC-Modules).

## Let's get started
### First we will look into the contents of module files.

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

- Similarly, the private subnets are created but, public ip addresses will not be available in private subnets.
