terraform {
  backend "s3" {
    bucket         = "REPLACE_ME_TERRAFORM_STATE_BUCKET"
    key            = "staging/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "REPLACE_ME_TF_LOCKS"
    encrypt        = true
  }
}
