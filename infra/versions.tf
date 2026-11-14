terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
  }

  # Remaining settings come from: terraform init -backend-config=... (see bootstrap output)
  # In CI set ARM_USE_OIDC=true, ARM_CLIENT_ID, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID.
  backend "azurerm" {
    key              = "app.tfstate"
    use_azuread_auth = true
  }
}

provider "azurerm" {
  features {}
}
