################################################################################
# Karpenter IRSA — IAM Role for Service Account
# Grants the Karpenter controller permission to provision/manage EC2 instances
################################################################################

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "karpenter_controller" {
  name = "karpenter-controller-${var.cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = var.oidc_provider_arn }
      Condition = {
        StringEquals = {
          "${replace(var.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:kube-system:karpenter"
          "${replace(var.oidc_provider_url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "karpenter_controller" {
  name = "karpenter-controller-policy"
  role = aws_iam_role.karpenter_controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "EC2Operations"; Effect = "Allow"
        Action = [
          "ec2:CreateLaunchTemplate", "ec2:CreateFleet", "ec2:RunInstances",
          "ec2:CreateTags", "ec2:TerminateInstances", "ec2:DeleteLaunchTemplate",
          "ec2:DescribeLaunchTemplates", "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups", "ec2:DescribeSubnets",
          "ec2:DescribeImages", "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings", "ec2:DescribeAvailabilityZones",
          "ec2:DescribeSpotPriceHistory"
        ]
        Resource = "*" },
      { Sid = "IAMPassRole"; Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/KarpenterNodeRole-${var.cluster_name}" },
      { Sid = "EKSAccess"; Effect = "Allow"
        Action = ["eks:DescribeCluster"]
        Resource = "arn:aws:eks:*:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}" },
      { Sid = "SQSInterruption"; Effect = "Allow"
        Action = ["sqs:DeleteMessage", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
        Resource = var.interruption_queue_arn },
      { Sid = "PricingAPI"; Effect = "Allow"
        Action = ["pricing:GetProducts"]
        Resource = "*" }
    ]
  })
}

variable "cluster_name"          { type = string }
variable "oidc_provider_arn"     { type = string }
variable "oidc_provider_url"     { type = string }
variable "interruption_queue_arn" { type = string }
variable "tags"                  { type = map(string); default = {} }

output "role_arn"  { value = aws_iam_role.karpenter_controller.arn }
output "role_name" { value = aws_iam_role.karpenter_controller.name }
