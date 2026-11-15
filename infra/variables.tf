variable "location" {
  type    = string
  default = "eastus"
}

variable "project" {
  type    = string
  default = "flaskopenai" # lowercase letters/digits only (used in ACR name)
}

variable "environment" {
  type    = string
  default = "dev"
}

# Object ID of the identity your APP GitHub workflow logs in as
variable "app_deployer_principal_id" {
  type = string
}

# Port your container listens on. The placeholder image listens on 80.
variable "target_port" {
  type    = number
  default = 80
}

variable "key_vault_purge_protection" {
  type    = bool
  default = false # set true in prod; blocks purging, so a destroyed vault's name stays reserved
}

variable "OPENAI_MODEL" {
  type    = string
  default = "gpt-4o-mini"
}
