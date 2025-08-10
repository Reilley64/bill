provider "aws" {
  region = "ap-southeast-2"
}

variable "github_sha" {
  type = string
}

variable "discord_webhook_url" {
  type = string
}

# VPC and Networking
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_security_group" "default" {
  name   = "default"
  vpc_id = data.aws_vpc.default.id
}

# Secrets
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

# IAM Roles
resource "aws_iam_role" "ecs_task_execution" {
  name = "bill-ecs-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "bill-ecs-task-execution-secrets"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.aws_workmail_password.arn,
          aws_secretsmanager_secret.discord_webhook_url.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task" {
  name = "bill-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/bill"
  retention_in_days = 7
}

# ECS Cluster
resource "aws_ecs_cluster" "bill" {
  name = "bill"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "bill" {
  family             = "bill"
  network_mode       = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                = "256"
  memory             = "512"
  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = "bill"
      image = "ghcr.io/reilley64/bill/bill:main-${substr(var.github_sha, 0, 7)}"

      environment = [
        {
          name  = "AWS__WorkMail__Username"
          value = "bill@reilley.dev"
        }
      ]

      secrets = [
        {
          name      = "AWS__WorkMail__Password"
          valueFrom = aws_secretsmanager_secret.aws_workmail_password.arn
        },
        {
          name      = "Discord__Webhook__Url"
          valueFrom = aws_secretsmanager_secret.discord_webhook_url.arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = "ap-southeast-2"
          "awslogs-stream-prefix" = "ecs"
        }
      }

      essential = true
    }
  ])
}

# EventBridge Configuration
resource "aws_iam_role" "eventbridge_ecs" {
  name = "event-bridge-ecs"

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

resource "aws_iam_role_policy" "eventbridge_ecs" {
  name = aws_iam_role.eventbridge_ecs.name
  role = aws_iam_role.eventbridge_ecs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:RunTask"
        ]
        Resource = [
          aws_ecs_task_definition.bill.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          aws_iam_role.ecs_task_execution.arn,
          aws_iam_role.ecs_task.arn
        ]
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "bill-schedule"
  schedule_expression = "cron(0 23 * * ? *)"
  description         = "Daily schedule for bill processing"
}

resource "aws_cloudwatch_event_target" "schedule" {
  arn      = aws_ecs_cluster.bill.arn
  rule     = aws_cloudwatch_event_rule.schedule.name
  role_arn = aws_iam_role.eventbridge_ecs.arn

  ecs_target {
    task_definition_arn = aws_ecs_task_definition.bill.arn
    launch_type = "FARGATE"
    platform_version = "LATEST"

    network_configuration {
      subnets = data.aws_subnets.default.ids
      security_groups = [data.aws_security_group.default.id]
      assign_public_ip = true
    }
  }
}

resource "aws_cloudwatch_event_rule" "manual" {
  name        = "bill-manual"
  description = "Manual trigger for bill processing"

  event_pattern = jsonencode({
    source = ["bill.manual"]
    detail-type = ["Manual Trigger"]
  })
}

resource "aws_cloudwatch_event_target" "manual" {
  arn      = aws_ecs_cluster.bill.arn
  rule     = aws_cloudwatch_event_rule.manual.name
  role_arn = aws_iam_role.eventbridge_ecs.arn

  ecs_target {
    task_definition_arn = aws_ecs_task_definition.bill.arn
    launch_type = "FARGATE"
    platform_version = "LATEST"
    
    network_configuration {
      subnets = data.aws_subnets.default.ids
      security_groups = [data.aws_security_group.default.id]
      assign_public_ip = true
    }
  }
}

output "manual_trigger_command" {
  value = "aws events put-events --entries 'Source=bill.manual,DetailType=\"Manual Trigger\",Detail=\"{}\"'"
}
