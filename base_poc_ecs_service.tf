# resource "aws_iam_policy" "ecs_exec_policy" {
#   name = "ecs_exec_policy"
 
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action   = ["ssmmessages:CreateControlChannel",
#                     "ssmmessages:CreateDataChannel",
#                     "ssmmessages:OpenControlChannel",
#                     "ssmmessages:OpenDataChannel"
#                     ]
#         Effect   = "Allow"
#         Resource = "*"
#       },
#     ]
#   })
# }

# resource "aws_iam_role" "ecs_task_execution_role" {
#   name = "role-name"
 
#   assume_role_policy  = data.aws_iam_policy_document.ecs_task_execution_role_base.json
# }
 
# resource "aws_iam_role_policy_attachment" "ecs-task-execution-role-policy-attachment" {
#   role       = aws_iam_role.ecs_task_execution_role.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
# }
# resource "aws_iam_role_policy_attachment" "task_s3" {
#   role       = "${aws_iam_role.ecs_task_role_for_database.name}"
#   policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
# }

########### tmp



####

# data "aws_route53_zone" "private_dns_domain" {
#   zone_id = var.private_dns_zone_id
# }

# resource "aws_service_discovery_instance" "example" {
#   instance_id = "example-instance-id"
#   service_id  = aws_service_discovery_service.example.id

#   attributes = {
#     AWS_INSTANCE_IPV4 = "172.18.0.1"
#     custom_attribute  = "custom"
#   }
# }
