# Copy these into GitHub repo Variables
output "ACR_NAME" {
  value = azurerm_container_registry.acr.name
}
output "RESOURCE_GROUP" {
  value = azurerm_resource_group.main.name
}
output "CONTAINER_APP" {
  value = azurerm_container_app.app.name
}
output "key_vault_name" {
  value = azurerm_key_vault.kv.name
}
output "app_url" {
  value = "https://${azurerm_container_app.app.ingress[0].fqdn}"
}
