variable "name" {
  description = "Base name used to identify the EC2 Image Builder infrastructure configuration and its supporting resources."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,58}$", var.name))
    error_message = "The name must contain 1 to 59 alphanumeric characters, hyphens, or underscores, and must start with an alphanumeric character."
  }
}

variable "subnet_id" {
  description = "ID of an existing subnet where EC2 Image Builder build instances will be launched. The subnet must provide the outbound connectivity required by the build."
  type        = string

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "The subnet_id must be a valid AWS subnet ID."
  }
}

variable "instance_types" {
  description = "EC2 instance types allowed for Image Builder builds. The default is a cost-oriented x86_64 baseline and should be increased only when the build requires more CPU or memory."
  type        = set(string)
  default     = ["t3.micro"]

  validation {
    condition = length(var.instance_types) > 0 && alltrue([
      for instance_type in var.instance_types :
      length(trimspace(instance_type)) > 0
    ])

    error_message = "The instance_types set must contain at least one non-empty EC2 instance type."
  }
}

variable "tags" {
  description = "Tags to be applied to the resources created by this module and propagated to EC2 build resources when supported."
  type        = map(string)
  default     = {}

  validation {
    condition     = length(var.tags) <= 30
    error_message = "The tags map supports at most 30 entries because EC2 Image Builder resource_tags accepts a maximum of 30 tags."
  }
}
