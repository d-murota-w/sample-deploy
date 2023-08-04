terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "ap-northeast-1"
}

data "aws_availability_zones" "available" {}
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-hvm-*-x86_64-gp2"]
  }
}

################################################################################
# VPC Module
################################################################################

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "d-murota-ipv6"

  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 1)
  public_subnets  = [for k, v in slice(data.aws_availability_zones.available.names, 0, 1) : cidrsubnet("10.0.0.0/16", 8, k + 4)]
  private_subnets = [for k, v in slice(data.aws_availability_zones.available.names, 0, 1) : cidrsubnet("10.0.0.0/16", 8, k)]

  enable_nat_gateway = false

  create_database_subnet_route_table     = true
  create_database_internet_gateway_route = true

  enable_ipv6                                   = true
  public_subnet_assign_ipv6_address_on_creation = true
  create_egress_only_igw                        = true

  public_subnet_ipv6_prefixes  = [0]
  private_subnet_ipv6_prefixes = [3]

}
module "endpoints" {
  source                = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  vpc_id                = module.vpc.vpc_id
  create_security_group = true
  security_group_rules = {
    ingress_https = {
      description = "HTTPS from VPC"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }
  endpoints = {
    s3 = {
      # interface endpoint
      service = "s3"
    },
  }
}
module "web_server_sg" {
  source = "terraform-aws-modules/security-group/aws//modules/http-80"

  name        = "web-server"
  description = "Security group for web-server with HTTP ports open within VPC"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  #ingress_ipv6_cidr_blocks = ["::0/0"]
}

module "internal_ssh_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "user-service"
  description = "Security group for user-service with ssh ports open within VPC"
  vpc_id      = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      rule                     = "ssh-tcp"
      source_security_group_id = module.eic_sg.security_group_id
    }
  ]
  egress_with_source_security_group_id = [
    {
      rule                     = "all-all"
      source_security_group_id = module.eic_sg.security_group_id
    }
  ]
}

module "iam_read_only_policy" {
  source = "terraform-aws-modules/iam/aws//modules/iam-read-only-policy"

  name        = "example"
  path        = "/"
  description = "My example read-only policy"

  allowed_services = ["s3"]
}

module "iam_assumable_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"

  trusted_role_services = [
    "ec2.amazonaws.com",
  ]

  create_role             = true
  create_instance_profile = true
  role_name               = "CodeDeployDemo-EC2-Instance-Profile"

  custom_role_policy_arns = [
    module.iam_read_only_policy.arn
  ]
}

data "aws_ssm_parameter" "amazonlinux2" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-kernel-5.10-hvm-x86_64-gp2"
}

locals {
  user_data = <<-EOT
    #!/bin/bash
    yum update -y
    yum install ruby -y 
    yum install wget -y
    cd /home/ec2-user
    wget https://aws-codedeploy-ap-northeast-1.s3.dualstack.ap-northeast-1.amazonaws.com/latest/install
    chmod +x ./install
  EOT
}
#  ./install auto
module "ec2_instance" {
  source = "terraform-aws-modules/ec2-instance/aws"
  name   = "single-instance"
  # ami                         = "ami-0e25eba2025eea319"
  ami                         = data.aws_ssm_parameter.amazonlinux2.value
  instance_type               = "t3.micro"
  vpc_security_group_ids      = [module.web_server_sg.security_group_id, module.internal_ssh_sg.security_group_id]
  subnet_id                   = module.vpc.public_subnets[0]
  create_iam_instance_profile = false
  iam_instance_profile        = module.iam_assumable_role.iam_instance_profile_id
  user_data_base64            = base64encode(local.user_data)
}

resource "aws_ec2_instance_connect_endpoint" "example" {
  subnet_id          = module.vpc.public_subnets[0]
  preserve_client_ip = false
  security_group_ids = [module.eic_sg.security_group_id]
}

module "eic_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "user-service"
  description = "Security group for user-service with custom ports open within VPC"
  vpc_id      = module.vpc.vpc_id

  egress_with_cidr_blocks = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "SSH"
      cidr_blocks = "10.0.0.0/16"
    },
  ]
}

