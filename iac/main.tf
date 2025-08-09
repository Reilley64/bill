provider "aws" {
  region = "ap-southeast-2"
}

variable "application_version" {
  type = string
}

variable "discord_webhook_url" {
  type = string
}

resource "random_password" "aws_workmail_password" {
  length = 64
}

resource "aws_secretsmanager_secret" "aws_workmail_password" {
  name = "bill/aws/workmail/password"
}

resource "aws_secretsmanager_secret_version" "aws_workmail_password" {
  secret_id     = aws_secretsmanager_secret.aws_workmail_password.id
  secret_string = random_password.aws_workmail_password.result
}

resource "aws_secretsmanager_secret" "discord_webhook_url" {
  name = "bill/discord/webhook/url"
}

resource "aws_secretsmanager_secret_version" "discord_webhook_url" {
  secret_id     = aws_secretsmanager_secret.discord_webhook_url.id
  secret_string = var.discord_webhook_url
}

resource "aws_iam_role" "application" {
  name = "bill"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "application" {
  role       = aws_iam_role.application.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_instance_profile" "application" {
  name = aws_iam_role.application.name
  role = aws_iam_role.application.name
}

resource "aws_elastic_beanstalk_application" "application" {
  name = "bill"
}

resource "aws_elastic_beanstalk_environment" "environment" {
  name                = "production"
  application         = aws_elastic_beanstalk_application.application.name
  solution_stack_name = "64bit Amazon Linux 2023 v3.5.3 running .NET 9"
  version_label       = var.application_version

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.application.name
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "AWS__WorkMail__Username"
    value     = "bill@reilley.dev"
  }
}
