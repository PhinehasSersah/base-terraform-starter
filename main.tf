terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket         = "kente-retail-tfstate-lab-145023116067-eu-west-1-an"
    key            = "networking/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "kente-retail-tflock"
    encrypt        = true
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  # No backend block on purpose -- this ships exactly as last sprint left it,
  # with state local to whoever's machine last ran `terraform apply`.
}

provider "aws" {
  region = var.aws_region
}
