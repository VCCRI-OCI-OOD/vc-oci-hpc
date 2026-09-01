  terraform {
    backend "oci" {
        namespace = "sdqtav66ik4q"
        bucket    = "terraform-states"
        key       = "infra/terraform.tfstate"
    }
  }
