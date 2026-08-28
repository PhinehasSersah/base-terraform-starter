locals {
  vpc_cidr_by_env = {
    dev     = "10.0.0.0/16"
    staging = "10.1.0.0/16"
  }
}

locals {
    instance_count_by_env = {
        dev     = 1
        staging = 2
    }
}                 