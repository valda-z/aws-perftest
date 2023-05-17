data "aws_availability_zones" "available" { state = "available" }
module "vpc" {
 source = "terraform-aws-modules/vpc/aws"
 version = "~> 3.19.0"

 azs = slice(data.aws_availability_zones.available.names, 0, 2) # Span subnetworks across multiple avalibility zones
 cidr = "10.0.0.0/16"
 create_igw = true # Expose public subnetworks to the Internet
 enable_nat_gateway = true # Hide private subnetworks behind NAT Gateway
 private_subnets = ["10.0.0.0/18", "10.0.64.0/18"]
 private_subnet_tags = {
   "kubernetes.io/role/internal-elb" = "1"
   "karpenter.sh/discovery" = local.name
 }
 public_subnets = ["10.0.128.0/18", "10.0.192.0/18"]
 public_subnet_tags = {
   "kubernetes.io/role/elb" = "1"
 }
}

// https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html

// helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=perftest-cluster