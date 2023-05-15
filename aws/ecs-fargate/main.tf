 locals {
    container_name = "perftest-container"
    container_port = 80
    cluster_name = "perftest-cluster"
 }

module "ecs" {
 source  = "terraform-aws-modules/ecs/aws"
 version = "~> 4.1.3"

 cluster_name = local.cluster_name

 # * Allocate 20% capacity to FARGATE and then split
 # * the remaining 80% capacity 50/50 between FARGATE
 # * and FARGATE_SPOT.
 fargate_capacity_providers = {
  FARGATE = {
   default_capacity_provider_strategy = {
    base   = 20
    weight = 50
   }
  }
  FARGATE_SPOT = {
   default_capacity_provider_strategy = {
    weight = 50
   }
  }
 }
}

variable "container_image" {
 type = string
}

data "aws_iam_role" "ecs_task_execution_role" { name = "ecsTaskExecutionRole" }

resource "aws_ecs_task_definition" "this" {
 container_definitions = jsonencode([{
  environment: [
   { name = "NODE_ENV", value = "production" }
  ],
  essential = true,
  image = var.container_image,
  name = local.container_name,
  portMappings = [{ containerPort = local.container_port }],
 }])
 cpu = "512"
 execution_role_arn = data.aws_iam_role.ecs_task_execution_role.arn
 family = "family-of-perftest-tasks"
 memory = "1024"
 network_mode = "awsvpc"
 requires_compatibilities = ["FARGATE"]
}

resource "aws_ecs_service" "this" {
 cluster = module.ecs.cluster_id
 desired_count = 1
 launch_type = "FARGATE"
 name = "perftest-service"
 task_definition = resource.aws_ecs_task_definition.this.arn

 lifecycle {
  ignore_changes = [desired_count] # Allow external changes to happen without Terraform conflicts, particularly around auto-scaling.
 }

 load_balancer {
  container_name = local.container_name
  container_port = local.container_port
  target_group_arn = module.alb.target_group_arns[0]
 }

 network_configuration {
  security_groups = [module.vpc.default_security_group_id]
  subnets = module.vpc.private_subnets
 }
}

resource "aws_appautoscaling_target" "this" {
  max_capacity       = 256
  min_capacity       = 32
  resource_id        = "service/${module.ecs.cluster_name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "this" {
  name               = "cpu-utilization"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  service_namespace  = aws_appautoscaling_target.this.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 25.0
    scale_in_cooldown  = 5
    scale_out_cooldown = 60
  }
}

output "url" { value = "http://${module.alb.lb_dns_name}" }


