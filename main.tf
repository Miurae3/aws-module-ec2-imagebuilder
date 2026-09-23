resource "aws_iam_role" "this" {
  name        = local.resource_names.iam_role
  description = "EC2 instance role used by EC2 Image Builder for Linux container image builds."

  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = local.iam_role_tags
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = local.instance_profile_policy_arns

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "this" {
  name = local.resource_names.instance_profile
  role = aws_iam_role.this.name

  tags = local.instance_profile_tags
}

resource "aws_security_group" "this" {
  name        = local.resource_names.security_group
  description = "Security group for EC2 Image Builder Linux container build instances."
  vpc_id      = data.aws_subnet.this.vpc_id

  tags = local.security_group_tags
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.this.id
  description       = "Allow HTTPS egress required by Image Builder, Systems Manager, AWS services, and container registries."

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_imagebuilder_infrastructure_configuration" "this" {
  name        = local.resource_names.infrastructure_configuration
  description = "Infrastructure used by EC2 Image Builder for Linux container image builds."

  instance_profile_name = aws_iam_instance_profile.this.name
  instance_types        = var.instance_types

  subnet_id          = var.subnet_id
  security_group_ids = [aws_security_group.this.id]

  terminate_instance_on_failure = true

  instance_metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  resource_tags = var.tags
  tags          = local.infrastructure_configuration_tags

  depends_on = [
    aws_iam_role_policy_attachment.this,
  ]
}
