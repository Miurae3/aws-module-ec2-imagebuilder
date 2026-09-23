output "infrastructure_configuration_arn" {
  description = "ARN of the EC2 Image Builder infrastructure configuration for use by later Image Builder resources."
  value       = aws_imagebuilder_infrastructure_configuration.this.arn
}
