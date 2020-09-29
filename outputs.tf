output "data_aws_availability_zones" {
  value = data.aws_availability_zones.available.names
}

output "data_aws_caller_identity" {
  value = data.aws_caller_identity.current.account_id
}

output "data_aws_region_name" {
  value = data.aws_region.current.name
}

output "data_aws_region_description" {
  value = data.aws_region.current.description
}

output "web_loadbalancer_url" {
  value = aws_elb.internal_elb.dns_name
}