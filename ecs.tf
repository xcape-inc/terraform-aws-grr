data "aws_ecs_cluster" "ecs_cluster_for_service" {
  cluster_name = var.ecs_cluster_name
}

# TODO: is this specific enough?
data "aws_iam_policy_document" "ecs_task_execution_role_base" {
  version = "2012-10-17"
  statement {
    sid = ""
    effect = "Allow"
    actions = ["sts:AssumeRole"]
 
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_service_discovery_private_dns_namespace" "grr" {
  name        = "${var.grr_frontend_sub_domain}.${var.private_dns_domain}"
  description = "The internal discovery namespace used by tasks for GRR for ${var.grr_project}"
  vpc         = var.service_vpc_id
}
