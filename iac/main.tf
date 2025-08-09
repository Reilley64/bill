provider "aws" {
  region = "ap-southeast-2"
}

variable "application_version" {
  type = string
}

variable "discord_webhook_url" {
  type = string
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "beanstalk_private" {
  name_prefix = "beanstalk-private-"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
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
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = data.aws_vpc.default.id
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value = join(",", data.aws_subnets.default.ids)
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBScheme"
    value     = "internal"
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "SecurityGroups"
    value     = aws_security_group.beanstalk_private.id
  }

  setting {
    namespace = "aws:elbv2:loadbalancer"
    name      = "SecurityGroups"
    value     = aws_security_group.beanstalk_private.id
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerType"
    value     = "network"
  }

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

resource "aws_apigatewayv2_vpc_link" "bill" {
  name       = "bill-vpc-link"
  security_group_ids = [aws_security_group.beanstalk_private.id]
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_apigatewayv2_api" "bill" {
  name          = "bill-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_credentials = false
    allow_headers     = ["*"]
    allow_methods     = ["*"]
    allow_origins     = ["*"]
    expose_headers    = ["*"]
    max_age           = 86400
  }
}

data "aws_lb" "bill" {
  tags = {
    "elasticbeanstalk:environment-name" = aws_elastic_beanstalk_environment.environment.name
  }

  depends_on = [aws_elastic_beanstalk_environment.environment]
}

data "aws_lb_listener" "bill" {
  load_balancer_arn = data.aws_lb.bill.arn
  port = 80
}

resource "aws_apigatewayv2_integration" "inbox_post" {
  api_id             = aws_apigatewayv2_api.bill.id
  integration_type   = "HTTP_PROXY"
  integration_method = "POST"
  integration_uri    = data.aws_lb_listener.bill.arn
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.bill.id
}


resource "aws_apigatewayv2_route" "inbox_post" {
  api_id    = aws_apigatewayv2_api.bill.id
  route_key = "POST /inbox"
  target    = "integrations/${aws_apigatewayv2_integration.inbox_post.id}"
}

resource "aws_apigatewayv2_stage" "bill" {
  api_id      = aws_apigatewayv2_api.bill.id
  name        = "prod"
  auto_deploy = true
}

resource "aws_iam_role" "scheduler" {
  name = "bill-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = aws_iam_role.scheduler.name
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "events:InvokeApiDestination"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_cloudwatch_event_connection" "bill" {
  name               = "bill"
  authorization_type = "API_KEY"
  auth_parameters {
    api_key {
      key   = "x-api-key"
      value = "test"
    }
  }
}

resource "aws_cloudwatch_event_api_destination" "bill_inbox" {
  name                = "bill-inbox"
  invocation_endpoint = "${aws_apigatewayv2_api.bill.api_endpoint}/prod/inbox"
  http_method         = "POST"
  connection_arn      = aws_cloudwatch_event_connection.bill.arn
}

resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "bill-schedule"
  schedule_expression = "cron(0 23 * * ? *)"
}


resource "aws_cloudwatch_event_target" "schedule" {
  arn      = aws_cloudwatch_event_api_destination.bill_inbox.arn
  rule     = aws_cloudwatch_event_rule.schedule.name
  role_arn = aws_iam_role.scheduler.arn
}

resource "aws_cloudwatch_event_rule" "manual" {
  name = "bill-manual"

  event_pattern = jsonencode({
    source = ["bill.manual"]
    detail-type = ["Manual Trigger"]
  })
}

resource "aws_cloudwatch_event_target" "manual" {
  arn      = aws_cloudwatch_event_api_destination.bill_inbox.arn
  rule     = aws_cloudwatch_event_rule.manual.name
  role_arn = aws_iam_role.scheduler.arn
}
