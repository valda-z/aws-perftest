resource "aws_iam_policy" "alb_iam_policy" {
  policy = "${file("alb_iam_policy.json")}"
}

locals {
  cluster_name = "perftest-cluster"
  name   = local.cluster_name
  region = "eu-west-1"

  tags = {
    Example    = local.name
  }
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
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

  manage_aws_auth_configmap = true
  aws_auth_roles = [
      # We need to add in the Karpenter node IAM role for nodes launched by Karpenter
      {
        rolearn  = module.karpenter.role_arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups = [
          "system:bootstrappers",
          "system:nodes",
        ]
      },
    ]

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

      ami_type = "BOTTLEROCKET_x86_64"
      platform = "bottlerocket"

      labels = {
        agentpool = "bottlerocket"
      }
    }
  }

    tags = merge(local.tags, {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "karpenter.sh/discovery" = local.name
  })
}

module "karpenter" {
  source = "terraform-aws-modules/eks/aws//modules/karpenter"

  cluster_name           = module.eks.cluster_name
  irsa_oidc_provider_arn = module.eks.oidc_provider_arn

  policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    EKSDownloadECRImage = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    ALBIAMPolicy = aws_iam_policy.alb_iam_policy.arn
  }

  tags = local.tags
}

data "kubectl_file_documents" "metrics_server" {
    content = file("metrics-server.yaml")
}

resource "kubectl_manifest" "metrics_server" {
    for_each  = data.kubectl_file_documents.metrics_server.manifests
    yaml_body = each.value
    depends_on = [ module.eks ]
}

resource "helm_release" "alb_controller" {
  namespace        = "kube-system"
  create_namespace = false

  name                = "alb-controller"
  repository          = "https://aws.github.io/eks-charts"
  chart               = "aws-load-balancer-controller"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }
}

resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true

  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart               = "karpenter"
  version             = "v0.21.1"

  set {
    name  = "settings.aws.clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "settings.aws.clusterEndpoint"
    value = module.eks.cluster_endpoint
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.karpenter.irsa_arn
  }

  set {
    name  = "settings.aws.defaultInstanceProfile"
    value = module.karpenter.instance_profile_name
  }

  set {
    name  = "settings.aws.interruptionQueueName"
    value = module.karpenter.queue_name
  }
  
}

resource "kubectl_manifest" "karpenter_provisioner" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1alpha5
    kind: Provisioner
    metadata:
      name: default
    spec:
      requirements:
        - key: node.kubernetes.io/instance-type
          operator: In
          values:
            - t3.xlarge
            - t3.large
      providerRef:
        name: default
      ttlSecondsAfterEmpty: 30
  YAML

  depends_on = [
    helm_release.karpenter
  ]
}

resource "kubectl_manifest" "karpenter_node_template" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1alpha1
    kind: AWSNodeTemplate
    metadata:
      name: default
    spec:
      amiFamily: Bottlerocket
      subnetSelector:
        karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelector:
        karpenter.sh/discovery: "karpenter-${module.eks.cluster_name}"
      tags:
        karpenter.sh/discovery: ${module.eks.cluster_name}
  YAML

  depends_on = [
    helm_release.karpenter
  ]
}

