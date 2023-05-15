data "aws_availability_zones" "available" { state = "available" }
module "vpc" {
 source = "terraform-aws-modules/vpc/aws"
 version = "~> 3.19.0"

 azs = slice(data.aws_availability_zones.available.names, 0, 2) # Span subnetworks across multiple avalibility zones
 cidr = "10.0.0.0/16"
 create_igw = true # Expose public subnetworks to the Internet
 enable_nat_gateway = true # Hide private subnetworks behind NAT Gateway
 private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
 private_subnet_tags = {
   "kubernetes.io/role/internal-elb" = "1"
 }
 public_subnets = ["10.0.101.0/24", "10.0.102.0/24"]
 public_subnet_tags = {
   "kubernetes.io/role/elb" = "1"
 }
}

// https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html

// helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=perftest-cluster