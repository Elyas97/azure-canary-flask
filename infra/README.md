# Infrastructure

Terraform for everything the app runs on in Azure.

| Resource | Purpose |
|---|---|
| Resource group | Holds everything below |
| Container Registry (ACR) | Stores the app's Docker images |
| Key Vault | Holds the OpenAI API key |
| Managed identity | Lets the running app pull images and read the key |
| Log Analytics | App logs |
| Container Apps environment + Container App | Runs the app, in multiple-revision mode for canary releases |
| Role assignments | Least-privilege access between all of the above |

## 1. Prerequisites (create these first, by hand)

Terraform can't create these for itself. Do them once in the Azure portal.

1. **Resource providers.** Subscriptions → your subscription → Resource providers. Register `Microsoft.App`, `Microsoft.OperationalInsights`, `Microsoft.ContainerRegistry`, `Microsoft.KeyVault`, `Microsoft.ManagedIdentity`.
2. **State storage.** A storage account with a private container named `tfstate`. Blob versioning and soft delete on, shared key access off (Entra ID auth only). Give **yourself** `Storage Blob Data Contributor` on that container.
3. **App identity.** Entra ID → App registrations → `gh-flaskopenai-app`, with one federated credential (GitHub entity: Branch `main`). Copy the **object ID** of its service principal (Entra ID → Enterprise applications). It is not the client ID. Terraform needs it as a variable.
4. **Your own rights.** To apply locally you need Owner on the subscription (or Contributor plus User Access Administrator), because Terraform creates role assignments.

Only needed for the pipelines (skip for a local-only run):

5. **Infra identity.** An app registration `gh-flaskopenai-infra` with federated credentials for Pull request, Branch `main` and Environment `infra`. Give it Contributor and Role Based Access Control Administrator on the subscription, and Storage Blob Data Contributor on the `tfstate` container.
6. **GitHub config.** Create an environment `infra` with a required reviewer. Add these under Settings → Secrets and variables → Actions:

   | Type | Name | Value |
   |---|---|---|
   | Secret | `AZURE_TENANT_ID` | tenant ID |
   | Secret | `AZURE_SUBSCRIPTION_ID` | subscription ID |
   | Secret | `INFRA_AZURE_CLIENT_ID` | client ID of the infra identity |
   | Secret | `APP_AZURE_CLIENT_ID` | client ID of the app identity |
   | Variable | `TFSTATE_RG` / `TFSTATE_SA` / `TFSTATE_CONTAINER` | state storage names |
   | Variable | `APP_DEPLOYER_PRINCIPAL_ID` | object ID from step 3 |
   | Variable | `IMAGE_NAME` | image repo name, e.g. `mini-agent` |

## 2. Deploy

```bash
az login
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
cd infra
```

Create two files. Both are gitignored.

```hcl
# backend.hcl
resource_group_name  = "<state resource group>"
storage_account_name = "<state storage account>"
container_name       = "tfstate"
```
```hcl
# terraform.tfvars
app_deployer_principal_id = "<object ID from prerequisite 3>"
location                  = "eastus2"
```

Then run:

```bash
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

If the apply fails creating role assignments or the Key Vault secret, run it again. Role propagation can lag a minute. Commit `.terraform.lock.hcl` after the first `init`.

## 3. After the first apply

1. **Set the OpenAI key.** Terraform only creates a placeholder, so the real key never enters state.
   ```bash
   az role assignment create --role "Key Vault Secrets Officer" \
     --assignee-object-id $(az ad signed-in-user show --query id -o tsv) \
     --assignee-principal-type User \
     --scope $(az keyvault show -n $(terraform output -raw key_vault_name) --query id -o tsv)

   az keyvault secret set --vault-name $(terraform output -raw key_vault_name) \
     --name openai-api-key --value '<key>'
   ```
2. **Switch the port.** The Container App starts on a placeholder image on port 80. Set `target_port` in `variables.tf` to `8000` (the app's port) and apply again.
3. **Give the app pipeline its settings.** Add GitHub variables `ACR_NAME`, `RESOURCE_GROUP`, `CONTAINER_APP` from `terraform output`. Then `app.yml` can ship the app.

## 4. Changes from now on

Once the pipelines are set up, let [`infra.yml`](../.github/workflows/infra.yml) apply changes and stop applying locally, so there's one audit trail.

- A PR that changes `infra/` runs `fmt`, `validate` and `plan` and comments the plan.
- Merging to `main` plans again, waits for approval on the `infra` environment, and applies that plan.

## 5. Tear down

```bash
terraform destroy
```

This removes only what Terraform created. The state storage, the identities and the GitHub config stay, because you made them by hand.

## Reference

### Who can do what

| Identity | Role | Scope | Created by |
|---|---|---|---|
| Running app (managed identity) | `AcrPull` | the registry | Terraform |
| Running app (managed identity) | `Key Vault Secrets User` | the Key Vault | Terraform |
| App pipeline | `AcrPush` | the registry | Terraform |
| App pipeline | `Contributor` | the Container App only | Terraform |
| Infra pipeline | Contributor + RBAC Administrator | the subscription | you |
| Infra pipeline and you | Storage Blob Data Contributor | the state container | you |

The Container App starts on a placeholder image. `ignore_changes` stops Terraform from undoing the image, revision and traffic changes the app pipeline makes.

### Variables

| Variable | Default | Notes |
|---|---|---|
| `location` | `westeurope` | `eastus2` is usually cheaper |
| `project` | `flaskopenai` | lowercase letters and digits only (used in the ACR name) |
| `environment` | `dev` | |
| `app_deployer_principal_id` | none, required | object ID of the app identity's service principal |
| `target_port` | `80` | set to `8000` after the first apply |
| `key_vault_purge_protection` | `false` | set `true` in prod. It blocks purging, so a deleted vault's name stays reserved |

### Outputs
`ACR_NAME`, `RESOURCE_GROUP`, `CONTAINER_APP`, `key_vault_name`, `app_url`.

### Cost
The fixed cost is the registry (about $5/month). The Container App is pay-per-use. Set `min_replicas = 0` in `main.tf` to scale to zero when idle, at the price of a cold start. `daily_quota_gb` on the Log Analytics workspace caps logging cost.

### Common errors

| Error | Likely cause |
|---|---|
| `AuthorizationFailed` creating role assignments | Your user or the infra identity can't create role assignments |
| `AADSTS700213` / no matching federated identity | The credential's subject doesn't match what GitHub sent. Compare with the one printed in the error |
| `MissingSubscriptionRegistration` | A resource provider wasn't registered |
| Backend `403` | Missing Storage Blob Data Contributor on the container, or it hasn't propagated yet |
| Failure creating the Key Vault secret | Role propagation lag. Re-run |
