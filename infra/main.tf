data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

locals {
  base = "${var.project}-${var.environment}"
  tags = { project = var.project, environment = var.environment, managed_by = "terraform" }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.base}"
  location = var.location
  tags     = local.tags
}

# ---------- Registry ----------
resource "azurerm_container_registry" "acr" {
  name                = "acr${var.project}${var.environment}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false # identity-based pulls only, no admin password
  tags                = local.tags
}

# ---------- Identity for the running app ----------
resource "azurerm_user_assigned_identity" "app" {
  name                = "id-${local.base}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.tags
}

# ---------- Key Vault ----------
resource "azurerm_key_vault" "kv" {
  name                       = "kv-${var.project}-${random_string.suffix.result}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true # RBAC, no access policies
  soft_delete_retention_days = 7
  purge_protection_enabled   = var.key_vault_purge_protection
  tags                       = local.tags
}

# Terraform's own identity may create the (placeholder) secret
resource "azurerm_role_assignment" "tf_kv_officer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_secret" "openai" {
  name         = "openai-api-key"
  value        = "REPLACE_ME" # real value is set out-of-band, never in Terraform/state
  key_vault_id = azurerm_key_vault.kv.id
  depends_on   = [azurerm_role_assignment.tf_kv_officer] # RBAC can take a minute; re-run apply if it races

  lifecycle {
    ignore_changes = [value]
  }
}

# ---------- Least-privilege RBAC ----------
# The running app: pull images, read secrets. Nothing else.
resource "azurerm_role_assignment" "app_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

resource "azurerm_role_assignment" "app_kv_read" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

# The app's GitHub pipeline: push images, and manage ONLY this container app.
resource "azurerm_role_assignment" "ci_acr_push" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = var.app_deployer_principal_id
}

resource "azurerm_role_assignment" "ci_app_contributor" {
  scope                = azurerm_container_app.app.id
  role_definition_name = "Contributor"
  principal_id         = var.app_deployer_principal_id
}

# ---------- Container Apps ----------
resource "azurerm_log_analytics_workspace" "logs" {
  name                = "log-${local.base}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_container_app_environment" "env" {
  name                       = "cae-${local.base}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id
  tags                       = local.tags
}

resource "azurerm_container_app" "app" {
  name                         = "ca-${local.base}"
  resource_group_name          = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_app_environment.env.id
  revision_mode                = "Multiple" # required for canary traffic splitting
  tags                         = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.app.id
  }

  # Container App pulls the key from Key Vault itself; GitHub never sees it
  secret {
    name                = "openai-api-key"
    key_vault_secret_id = azurerm_key_vault_secret.openai.versionless_id
    identity            = azurerm_user_assigned_identity.app.id
  }

  ingress {
    external_enabled = true
    target_port      = var.target_port
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 1
    max_replicas = 3

    container {
      name   = "app"
      image  = "mcr.microsoft.com/k8se/quickstart:latest" # placeholder; the pipeline owns the image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name        = "OPENAI_API_KEY"
        secret_name = "openai-api-key"
      }

      env {
        name  = "OPENAI_MODEL"
        value = var.OPENAI_MODEL
      }
    }
  }

  # The pipeline owns image, revision suffix and canary weights. Don't let apply undo them.
  lifecycle {
    ignore_changes = [
      template[0].container[0].image,
      template[0].revision_suffix,
      ingress[0].traffic_weight,
    ]
  }

  depends_on = [
    azurerm_role_assignment.app_acr_pull,
    azurerm_role_assignment.app_kv_read,
  ]
}
