output "topic_id" {
  description = "Resource ID of the Event Grid topic."
  value       = azurerm_eventgrid_topic.this.id
}

output "topic_name" {
  description = "Name of the Event Grid topic."
  value       = azurerm_eventgrid_topic.this.name
}

output "topic_endpoint" {
  description = "Publishing endpoint URL of the Event Grid topic."
  value       = azurerm_eventgrid_topic.this.endpoint
}

output "topic_primary_access_key" {
  description = "Primary access key for the topic (usable only when local_auth_enabled = true)."
  value       = azurerm_eventgrid_topic.this.primary_access_key
  sensitive   = true
}

output "topic_secondary_access_key" {
  description = "Secondary access key for the topic (usable only when local_auth_enabled = true)."
  value       = azurerm_eventgrid_topic.this.secondary_access_key
  sensitive   = true
}

output "topic_identity_principal_id" {
  description = "Principal ID of the topic's system-assigned managed identity."
  value       = azurerm_eventgrid_topic.this.identity[0].principal_id
}

output "queue_storage_account_id" {
  description = "Resource ID of the created queue Storage Account (null when create_queue_target = false)."
  value       = one(azurerm_storage_account.queue[*].id)
}

output "queue_storage_account_name" {
  description = "Name of the created queue Storage Account (null when create_queue_target = false)."
  value       = one(azurerm_storage_account.queue[*].name)
}

output "queue_name" {
  description = "Name of the created Storage Queue (null when create_queue_target = false)."
  value       = one(azurerm_storage_queue.this[*].name)
}

output "queue_url" {
  description = "Data-plane URL of the created Storage Queue (null when create_queue_target = false)."
  value       = one(azurerm_storage_queue.this[*].url)
}

output "event_subscription_ids" {
  description = "Map of subscription name => Event Grid event subscription ID."
  value       = { for key, sub in azurerm_eventgrid_event_subscription.this : key => sub.id }
}
