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

# VPC Endpoints
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "bill-vpc-endpoints-"
  vpc_id      = data.aws_vpc.default.id
  description = "Security group for VPC endpoints"

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
    description     = "Allow HTTPS from ECS tasks"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.ap-southeast-2.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.aws_subnets.default.ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.ap-southeast-2.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.aws_subnets.default.ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

# Security Groups
resource "aws_security_group" "alb" {
  name_prefix = "bill-alb-private-"
  vpc_id      = data.aws_vpc.default.id
  description = "Security group for private ALB"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.vpc_link.id]
    description = "Allow traffic from VPC Link only"
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bill-alb-private"
  }
}

resource "aws_security_group" "ecs_tasks" {
  name_prefix = "bill-ecs-tasks-"
  vpc_id      = data.aws_vpc.default.id
  description = "Security group for ECS tasks"

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    security_groups = [aws_security_group.alb.id]
    description = "Allow traffic from ALB only"
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bill-ecs-tasks"
  }
}

resource "aws_security_group" "vpc_link" {
  name_prefix = "bill-vpc-link-"
  vpc_id      = data.aws_vpc.default.id
  description = "Security group for VPC Link"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP from API Gateway"
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bill-vpc-link"
  }
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

# Private Application Load Balancer
resource "aws_lb" "main" {
  name               = "bill-alb-private"
  internal = true  # This makes it private
  load_balancer_type = "application"
  security_groups = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.default.ids

  enable_deletion_protection = false
  enable_http2               = true

  tags = {
    Name = "bill-alb-private"
  }
}

resource "random_id" "target_group_name" {
  byte_length = 8
}

resource "aws_lb_target_group" "app" {
  name        = random_id.target_group_name.id
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path = "/health"  # Adjust to your health check endpoint
    matcher             = "200"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "bill-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "app" {
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
          name  = "ASPNETCORE_HTTP_PORTS"
          value = "8080"
        },
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
          name      = "Discord__WebhookUrl"
          valueFrom = aws_secretsmanager_secret.discord_webhook_url.arn
        }
      ]

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
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

# ECS Service
resource "aws_ecs_service" "app" {
  name            = "bill-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "bill"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.app]
}

# API Gateway with VPC Link (Private access only)
resource "aws_apigatewayv2_vpc_link" "bill" {
  name       = "bill-vpc-link"
  security_group_ids = [aws_security_group.vpc_link.id]
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_apigatewayv2_api" "bill" {
  name          = "bill-api-private"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "inbox" {
  api_id             = aws_apigatewayv2_api.bill.id
  integration_type   = "HTTP_PROXY"
  integration_method = "POST"
  integration_uri    = aws_lb_listener.app.arn
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.bill.id
}

resource "aws_apigatewayv2_route" "inbox_post" {
  api_id    = aws_apigatewayv2_api.bill.id
  route_key = "POST /inbox"
  target    = "integrations/${aws_apigatewayv2_integration.inbox.id}"
  authorization_type = "AWS_IAM"

  depends_on = [aws_apigatewayv2_integration.inbox]
}

resource "aws_apigatewayv2_stage" "bill" {
  api_id      = aws_apigatewayv2_api.bill.id
  name        = "$default"
  auto_deploy = true
}

# EventBridge Configuration
resource "aws_iam_role" "eventbridge_api_gateway" {
  name = "event-bridge-api-gateway"

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

resource "aws_iam_role_policy" "eventbridge_api_gateway" {
  name = aws_iam_role.eventbridge_api_gateway.name
  role = aws_iam_role.eventbridge_api_gateway.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "execute-api:Invoke"
        ]
        Resource = "${aws_apigatewayv2_api.bill.execution_arn}/*/*"
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
  arn      = "${aws_apigatewayv2_api.bill.execution_arn}/POST/inbox"
  rule     = aws_cloudwatch_event_rule.schedule.name
  role_arn = aws_iam_role.eventbridge_api_gateway.arn
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
  arn      = "${aws_apigatewayv2_api.bill.execution_arn}/POST/inbox"
  rule     = aws_cloudwatch_event_rule.manual.name
  role_arn = aws_iam_role.eventbridge_api_gateway.arn
}

output "manual_trigger_command" {
  value = "aws events put-events --entries 'Source=bill.manual,DetailType=Manual Trigger,Detail=\"{}\"' --region ap-southeast-2"
}
