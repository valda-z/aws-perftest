resource "aws_iam_policy" "alb_iam_policy" {
  policy = "${file("alb_iam_policy.json")}"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = "perftest-cluster"
  cluster_version = "1.26"

  cluster_endpoint_public_access  = true

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  # control_plane_subnet_ids = ["subnet-xyzde987", "subnet-slkjf456", "subnet-qeiru789"]

  eks_managed_node_groups = {
    t3 = {
      min_size     = 2
      max_size     = 16
      desired_size = 2

      instance_types = ["t3.xlarge"]

      iam_role_additional_policies = {
        EKSDownloadECRImage = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
        ALBIAMPolicy = aws_iam_policy.alb_iam_policy.arn
      }

      labels = {
        agentpool = "nodepool1"
      }
    }
  }

  # Fargate Profile(s)
  fargate_profiles = {
    default = {
      name = "fargate-default"
      selectors = [
        {
          namespace = "perftest"
        }
      ]
       iam_role_additional_policies = {
        EKSDownloadECRImage = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      }
   }
  }
}