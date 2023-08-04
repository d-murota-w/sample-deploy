# ----------------------------------
# IAM
# ----------------------------------
#resource "aws_iam_role" "sample_app_deploy_role" {
#  name = "sample_app_deploy_role-role"
#
#  assume_role_policy = <<EOF
#{
#  "Version": "2012-10-17",
#  "Statement": [
#    {
#      "Sid": "",
#      "Effect": "Allow",
#      "Principal": {
#        "Service": "codedeploy.amazonaws.com"
#      },
#      "Action": "sts:AssumeRole"
#    }
#  ]
#}
#EOF
#}
#
#resource "aws_iam_role_policy_attachment" "code_deploy_policy_attachments" {
#  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
#  role       = aws_iam_role.sample_app_deploy_role.name
#}
#
module "s3_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket = "d-murota-test-s3-bucket"
  acl    = "private"

  control_object_ownership = true
  object_ownership         = "ObjectWriter"

  #versioning = {
  #  enabled = true
  #}
}
module "iam_assumable_role_codedeploy" {
  source = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"

  trusted_role_services = [
    "codedeploy.amazonaws.com",
  ]

  create_role       = true
  role_requires_mfa = false
  role_name         = "CodeDeployServiceRole"

  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
  ]
}
## ----------------------------------
## CodeDeploy
## ----------------------------------
resource "aws_codedeploy_app" "sample_app" {
  name = "test-cs-app"
}

resource "aws_codedeploy_deployment_group" "sample_app_deploy_group" {
  app_name              = aws_codedeploy_app.sample_app.name
  deployment_group_name = "test-cs-appgroup"
  service_role_arn      = module.iam_assumable_role_codedeploy.iam_role_arn

  ec2_tag_set {
    ec2_tag_filter {
      key   = "Name"
      type  = "KEY_AND_VALUE"
      value = "single-instance"
    }
  }

  #auto_rollback_configuration {
  #  enabled = true
  #  events  = ["DEPLOYMENT_FAILURE"]
  #}
}

