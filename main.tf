# Terraform state will be stored in S3
terraform {
  backend "s3" {
    bucket = "tf-running-state-ashutau"
    key    = "terraform.tfstate"
    region = "eu-central-1"
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_vpcs" "my_vpcs" {}
data "aws_ami" "latest_ubuntu" {
  owners      = ["099720109477"]
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }
}
data "aws_sns_topic" "asg_topic" {
    name = var.sns_topic_name
}

resource "aws_vpc" "main_vpc" {
  cidr_block = var.main_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "Main VPC"
  }
}

resource "aws_subnet" "main_public_1" {
  vpc_id            = aws_vpc.main_vpc.id
  availability_zone = data.aws_availability_zones.available.names[0]
  cidr_block        = "10.0.11.0/24"
  tags = {
    Name    = "Public Subnet-1 in ${data.aws_availability_zones.available.names[0]}"
    Account = "Subnet in Account ${data.aws_caller_identity.current.account_id}"
    Region  = data.aws_region.current.description
  }
}

resource "aws_subnet" "main_public_2" {
  vpc_id            = aws_vpc.main_vpc.id
  availability_zone = data.aws_availability_zones.available.names[1]
  cidr_block        = "10.0.12.0/24"
  tags = {
    Name    = "Public Subnet-2 in ${data.aws_availability_zones.available.names[1]}"
    Account = "Subnet in Account ${data.aws_caller_identity.current.account_id}"
    Region  = data.aws_region.current.description
  }
}

resource "aws_subnet" "main_private_1" {
  vpc_id            = aws_vpc.main_vpc.id
  availability_zone = data.aws_availability_zones.available.names[0]
  cidr_block        = "10.0.21.0/24"
  tags = {
    Name    = "Private Subnet-1 in ${data.aws_availability_zones.available.names[0]}"
    Account = "Subnet in Account ${data.aws_caller_identity.current.account_id}"
    Region  = data.aws_region.current.description
  }
}

resource "aws_subnet" "main_private_2" {
  vpc_id            = aws_vpc.main_vpc.id
  availability_zone = data.aws_availability_zones.available.names[1]
  cidr_block        = "10.0.22.0/24"
  tags = {
    Name    = "Private Subnet-2 in ${data.aws_availability_zones.available.names[1]}"
    Account = "Subnet in Account ${data.aws_caller_identity.current.account_id}"
    Region  = data.aws_region.current.description
  }
}

#create internet gateway
resource "aws_internet_gateway" "main_vpc_igw" {
  vpc_id = aws_vpc.main_vpc.id
  tags = {
      Name = "Main IGW"
  }
}

#Add igw route to main route table
resource "aws_route" "internet_access" {
  route_table_id         = aws_vpc.main_vpc.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main_vpc_igw.id
}

# Associate Public subnet 1 to public route table
resource "aws_route_table_association" "public_subnet_1_association" {
    subnet_id = aws_subnet.main_public_1.id
    route_table_id = aws_vpc.main_vpc.main_route_table_id
}

# Associate Public subnet 2 to public route table
resource "aws_route_table_association" "public_subnet_2_association" {
    subnet_id = aws_subnet.main_public_2.id
    route_table_id = aws_vpc.main_vpc.main_route_table_id
}

resource "aws_route_table" "private_route_table" {
    vpc_id = aws_vpc.main_vpc.id
    tags = {
      Name = "Private route table"
  }
}

# Associate Private subnet 1 to private route table
resource "aws_route_table_association" "private_subnet_1_association" {
    subnet_id = aws_subnet.main_private_1.id
    route_table_id = aws_route_table.private_route_table.id
}

# Associate Private subnet 2 to private route table
resource "aws_route_table_association" "private_subnets_2_association" {
    subnet_id = aws_subnet.main_private_2.id
    route_table_id = aws_route_table.private_route_table.id
}

# Create Security Group for internal ELB
resource "aws_security_group" "internal_elb" {
  name        = "HTTP-internal-ELB"
  description = "HTTP-internal-ELB"
  vpc_id = aws_vpc.main_vpc.id

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create Security Group for WebServer
resource "aws_security_group" "web" {
  name = "Dynamic Security Group"
  vpc_id = aws_vpc.main_vpc.id

  dynamic "ingress" {
    for_each = ["80", "22"]
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name  = "HTTP-SSH"
  }
}

# Create Security Group for Client
resource "aws_security_group" "client" {
  name = "SSH-Only"
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name  = "SSH-Only"
  }
}

resource "aws_launch_configuration" "web" {
  name_prefix     = "WebServer-HA-LC-"
  image_id        = var.web_ami
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.web.id]

  lifecycle {
    create_before_destroy = true
  }
}

#resource "tls_private_key" "client" {
#  algorithm = "RSA"
#  rsa_bits  = 4096
#}

#resource "aws_key_pair" "generated_key" {
#  key_name   = var.key_name
#  public_key = tls_private_key.client.public_key_openssh
#}


resource "aws_launch_configuration" "client" {
  name_prefix                 = "Client-HA-LC-"
#  image_id                    = var.client_ami
  image_id                    = data.aws_ami.latest_ubuntu.id
  instance_type               = "t2.micro"
  security_groups             = [aws_security_group.client.id]
  associate_public_ip_address = true
  user_data                   = file("client_data.sh")
#  key_name                    = aws_key_pair.generated_key.key_name
  key_name                    = "frankfurt_key"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "web" {
  name                 = "ASG-${aws_launch_configuration.web.name}"
  launch_configuration = aws_launch_configuration.web.name
  min_size             = 1
  max_size             = 4
#  min_elb_capacity     = 1
  desired_capacity     = 2
  health_check_type    = "ELB"
  vpc_zone_identifier  = [aws_subnet.main_private_1.id, aws_subnet.main_private_2.id]
  load_balancers       = [aws_elb.internal_elb.name]

  dynamic "tag" {
    for_each = {
      Name   = "WebServer in ASG"
      TAGKEY = "TAGVALUE"
    }
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "client" {
  name                 = "ASG-${aws_launch_configuration.client.name}"
  launch_configuration = aws_launch_configuration.client.name
  min_size             = 1
  max_size             = 2
  #min_elb_capacity     = 1
  desired_capacity     = 1
  health_check_type    = "EC2"
  vpc_zone_identifier  = [aws_subnet.main_public_1.id, aws_subnet.main_public_2.id]

  dynamic "tag" {
    for_each = {
      Name   = "Client in ASG"
      TAGKEY = "TAGVALUE"
    }
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_elb" "internal_elb" {
  name               = "WebServer-HA-internal-ELB"
  internal           = true
#  availability_zones = [data.aws_availability_zones.available.names[0], data.aws_availability_zones.available.names[1]]
  subnets            = [aws_subnet.main_private_1.id, aws_subnet.main_private_2.id]
  security_groups    = [aws_security_group.web.id]
  listener {
    lb_port           = 80
    lb_protocol       = "http"
    instance_port     = 80
    instance_protocol = "http"
  }
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 10
  }
  tags = {
    Name = "WebServer-Highly-Available-ELB"
  }
}

# Create email notification. aws sns topic with subscription created manually
# because the email endpoint needs to be authorized with email confirmation
resource "aws_autoscaling_notification" "asg_notifications" {
  group_names = [
    aws_autoscaling_group.web.name,
  ]

  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  ]

  topic_arn = data.aws_sns_topic.asg_topic.arn
}
