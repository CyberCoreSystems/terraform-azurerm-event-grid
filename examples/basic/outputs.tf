output "topic_id" {
  description = "Resource ID of the Event Grid topic created by the module."
  value       = module.event_grid.topic_id
}

output "topic_endpoint" {
  description = "Publishing endpoint of the Event Grid topic."
  value       = module.event_grid.topic_endpoint
}

output "queue_name" {
  description = "Name of the module-created Storage Queue delivery target."
  value       = module.event_grid.queue_name
}

output "event_subscription_ids" {
  description = "Map of subscription name => ID."
  value       = module.event_grid.event_subscription_ids
}
