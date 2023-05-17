resource "aws_iam_policy" "alb_iam_policy" {
  policy = "${file("alb_iam_policy.json")}"
}

locals {
  cluster_name = "perftest-cluster"
}

module "ebs_csi_irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name             = "${local.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = local.cluster_name
  cluster_version = "1.26"

  cluster_endpoint_public_access  = true

  cluster_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
      most_recent = true
    }
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent              = true
      before_compute           = true
      configuration_values = jsonencode({
        env = {
          # Reference docs https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
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
          labels = {
              nodetype = "fargate"
          }
        }
      ]
       iam_role_additional_policies = {
        EKSDownloadECRImage = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      }
   }
  }
}

data "aws_eks_cluster" "eks_cluster" {
  name = module.eks.cluster_name
}
# Obtain TLS certificate for the OIDC provider
data "tls_certificate" "tls" {
  url = data.aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}
# Create OIDC Provider using TLS certificate
data "aws_iam_openid_connect_provider" "eks_ca_oidc_provider" {
  url             = data.aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}

# Policy document allowing Federated Access for IAM Cluster Autoscaler role
data "aws_iam_policy_document" "cluster_autoscaler_sts_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_iam_openid_connect_provider.eks_ca_oidc_provider.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:cluster-autoscaler"]
    }
    principals {
      identifiers = [data.aws_iam_openid_connect_provider.eks_ca_oidc_provider.arn]
      type        = "Federated"
    }
  }
}
# IAM Role for IAM Cluster Autoscaler
resource "aws_iam_role" "cluster_autoscaler" {
  assume_role_policy = data.aws_iam_policy_document.cluster_autoscaler_sts_policy.json
  name               = "${local.cluster_name}-cluster-autoscaler"
}
# IAM Policy for IAM Cluster Autoscaler role allowing ASG operations
resource "aws_iam_policy" "cluster_autoscaler" {
  name = "${local.cluster_name}-cluster-autoscaler"
  policy = jsonencode({
    Statement = [{
      Action = [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeTags",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "ec2:DescribeLaunchTemplateVersions"
      ]
      Effect   = "Allow"
      Resource = "*"
    }]
    Version = "2012-10-17"
  })
}
resource "aws_iam_role_policy_attachment" "eks_ca_iam_policy_attach" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}

output "ARNAutoscalerRole" {
  value = aws_iam_role.cluster_autoscaler.arn
}