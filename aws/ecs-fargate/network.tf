data "aws_availability_zones" "available" { state = "available" }
module "vpc" {
 source = "terraform-aws-modules/vpc/aws"
 version = "~> 3.19.0"

 azs = slice(data.aws_availability_zones.available.names, 0, 2) # Span subnetworks across multiple avalibility zones
 cidr = "10.0.0.0/16"
 create_igw = true # Expose public subnetworks to the Internet
 enable_nat_gateway = true # Hide private subnetworks behind NAT Gateway
 private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
 public_subnets = ["10.0.101.0/24", "10.0.102.0/24"]
}

module "alb" {
 source  = "terraform-aws-modules/alb/aws"
 version = "~> 8.4.0"

 load_balancer_type = "network" // "application"
 // security_groups = [module.vpc.default_security_group_id]
 subnets = module.vpc.public_subnets
 vpc_id = module.vpc.vpc_id

 security_group_rules = {
  ingress_all_http = {
   type        = "ingress"
   from_port   = 80
   to_port     = 80
   protocol    = "TCP"
   description = "Permit incoming HTTP requests from the internet"
   cidr_blocks = ["0.0.0.0/0"]
  }
  egress_all = {
   type        = "egress"
   from_port   = 0
   to_port     = 0
   protocol    = "-1"
   description = "Permit all outgoing requests to the internet"
   cidr_blocks = ["0.0.0.0/0"]
  }
 }

 http_tcp_listeners = [
  {
   # * Setup a listener on port 80 and forward all HTTP
   # * traffic to target_groups[0] defined below which
   # * will eventually point to our "Hello World" app.
   port               = 80
   protocol           = "TCP" // "HTTP"
   target_group_index = 0
  }
 ]

 target_groups = [
  {
   backend_port         = local.container_port
   backend_protocol     = "TCP" // "HTTP"
   target_type          = "ip"
   health_check         = {
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 5
    interval            = 10
    path                = "/testsimple"
    matcher             = "200-299"
   }
  }
 ]
}

resource "aws_security_group_rule" "http" {
  security_group_id = module.vpc.default_security_group_id
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}