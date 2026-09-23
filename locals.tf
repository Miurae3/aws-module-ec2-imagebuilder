locals {
  resource_names = {
    infrastructure_configuration = var.name
    iam_role                      = "${var.name}-role"
    instance_profile              = "${var.name}-profile"
    security_group                = "${var.name}-sg"
  }

  instance_profile_policy_arns = {
    image_builder = "arn:${data.aws_partition.current.partition}:iam::aws:policy/EC2InstanceProfileForImageBuilder"
    container     = "arn:${data.aws_partition.current.partition}:iam::aws:policy/EC2InstanceProfileForImageBuilderECRContainerBuilds"
    ssm           = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  iam_role_tags = merge(
    var.tags,
    {
      Name = local.resource_names.iam_role
    }
  )

  instance_profile_tags = merge(
    var.tags,
    {
      Name = local.resource_names.instance_profile
    }
  )

  security_group_tags = merge(
    var.tags,
    {
      Name = local.resource_names.security_group
    }
  )

  infrastructure_configuration_tags = merge(
    var.tags,
    {
      Name = local.resource_names.infrastructure_configuration
    }
  )
}
