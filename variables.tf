variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-1"
}
 
variable "vpc_cidr" {
  description = "CIDR block for this environment's VPC."
  type        = string
  default     = "10.20.0.0/16"
}
 variable "instance_type" {
  description = "EC2 instance type for the web tier."
  type        = string
  default     = "t3.micro"
}

variable "instance_count" {
  description = "Number of web-tier instances to run."
  type        = number
  default     = 1
}

variable "project_tag" {
  description = "Value used for the Project tag on every resource this config creates."
  type        = string
  default     = "kente-retail"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair to associate with the web-tier instance(s), for the SSH access Ansible will use."
  type        = string
  default     = "ansible-key-pair"
}
