################################################################################
# Karpenter Terraform Module
# Installs Karpenter via Helm, creates SQS queue for spot interruptions,
# and configures the controller IAM role.
################################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

################################################################################
# SQS — Spot interruption queue
################################################################################

resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = "karpenter-interruption-${var.cluster_name}"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = var.tags
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = ["events.amazonaws.com", "sqs.amazonaws.com"] }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.karpenter_interruption.arn
    }]
  })
}

################################################################################
# EventBridge rules — forward interruption signals to SQS
################################################################################

resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name        = "karpenter-spot-interruption-${var.cluster_name}"
  description = "Spot instance 2-minute interruption notice"
  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Spot Instance Interruption Warning"]
  })
  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "instance_state_change" {
  name          = "karpenter-instance-state-${var.cluster_name}"
  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Instance State-change Notification"]
  })
  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "rebalance_recommendation" {
  name          = "karpenter-rebalance-${var.cluster_name}"
  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Instance Rebalance Recommendation"]
  })
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "spot_interruption" {
  rule = aws_cloudwatch_event_rule.spot_interruption.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}
resource "aws_cloudwatch_event_target" "instance_state_change" {
  rule = aws_cloudwatch_event_rule.instance_state_change.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}
resource "aws_cloudwatch_event_target" "rebalance_recommendation" {
  rule = aws_cloudwatch_event_rule.rebalance_recommendation.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

################################################################################
# Karpenter Helm release
################################################################################

resource "helm_release" "karpenter" {
  namespace        = "kube-system"
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = var.karpenter_version
  create_namespace = false
  wait             = true
  timeout          = 300

  values = [
    jsonencode({
      settings = {
        clusterName       = var.cluster_name
        clusterEndpoint   = var.cluster_endpoint
        interruptionQueue = aws_sqs_queue.karpenter_interruption.name
      }
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = var.karpenter_irsa_role_arn
        }
      }
      controller = {
        resources = {
          requests = { cpu = "500m"; memory = "512Mi" }
          limits   = { cpu = "1";    memory = "1Gi" }
        }
      }
      # Run Karpenter on system nodes only
      tolerations = [{ key = "CriticalAddonsOnly"; operator = "Exists" }]
      nodeSelector = { role = "system" }
      replicas     = 2   # HA for Karpenter controller itself
      podDisruptionBudget = { minAvailable = 1 }
    })
  ]
}

variable "cluster_name"          { type = string }
variable "cluster_endpoint"      { type = string }
variable "karpenter_irsa_role_arn" { type = string }
variable "karpenter_version"     { type = string; default = "1.0.0" }
variable "tags"                  { type = map(string); default = {} }

output "interruption_queue_name" { value = aws_sqs_queue.karpenter_interruption.name }
output "interruption_queue_arn"  { value = aws_sqs_queue.karpenter_interruption.arn }
