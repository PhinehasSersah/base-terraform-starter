variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "project_tag" {
  description = "Value for the Project tag on every resource this module creates."
  type        = string
}

variable "existing_vpc_id" {
  type    = string
  default = "vpc-0cd88d4b77a4ad1f9"
}

variable "existing_subnet_id" {
  type    = string
  default = "subnet-0575121be28bbc508"   # or whichever one you pick
}