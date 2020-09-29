
variable "aws_region" {
  description = "Please Enter AWS Region to deploy Infrastructure"
  type        = string
  default     = "eu-central-1"
}

variable "main_cidr" {
  type = string
  default = "10.0.0.0/16"
}

variable "web_ami" {
  description = "WebServer AMI ubuntu_18.04 + nginx"
  type = string
  default = "ami-09bc5a5273a373294"
}

#variable "client_ami" {
#  description = "Client AMI ubuntu_18.04 + ab + siege"
#  type = string
##  default = "ami-06c4ce4cd8402323f"
##  default = "ami-092391a11f8aa4b7b"
#  default     = data.aws_ami.latest_ubuntu.id
#}

variable "key_name" {
  type    = string
  default = "client_key"
}