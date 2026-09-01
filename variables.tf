variable "name" {
  description = "Name of the Event Grid custom topic (3-50 chars, letters, digits and hyphens). Also used to derive child resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{3,50}$", var.name))
    error_message = "name must be 3-50 characters of letters, digits and hyphens only."
  }
}

variable "resource_group_name" {
  description = "Name of an existing resource group to create the topic (and optional queue target) in."
  type        = string
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
}

variable "input_schema" {
  description = "Schema the topic accepts from publishers. CustomEventSchema is intentionally not supported (it requires input mapping); use EventGridSchema or CloudEventSchemaV1_0. Changing this forces a new topic."
  type        = string
  default     = "EventGridSchema"

  validation {
    condition     = contains(["EventGridSchema", "CloudEventSchemaV1_0"], var.input_schema)
    error_message = "input_schema must be EventGridSchema or CloudEventSchemaV1_0."
  }
}

variable "local_auth_enabled" {
  description = "Allow access-key (SAS) authentication for publishing to the topic. Off by default (Entra ID / managed-identity publishing only). Set true only if your publishers use the topic access keys."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Allow publishing over the public endpoint. Keep true for most topics (optionally narrowed by allowed_inbound_ip_masks); set false for private-endpoint-only topics."
  type        = bool
  default     = true
}

variable "allowed_inbound_ip_masks" {
  description = "Optional list of CIDRs/IPs allowed to publish over the public endpoint (action is always Allow). Empty means no IP restriction. Requires public_network_access_enabled = true."
  type        = list(string)
  default     = []
}

variable "identity_ids" {
  description = "User-assigned managed identity IDs to attach to the topic. A system-assigned identity is always created; supplying IDs additionally enables user-assigned identities for managed delivery/dead-lettering."
  type        = list(string)
  default     = []
}

variable "create_queue_target" {
  description = "Create a dedicated Storage Account + Storage Queue inside the module to receive events. Subscriptions can then target it with use_created_queue = true. Cheapest reliable delivery target (no public webhook to stand up)."
  type        = bool
  default     = false
}

variable "queue_storage_account_name" {
  description = "Globally-unique Storage Account name (3-24 lowercase letters/digits) for the created queue target. Required when create_queue_target = true."
  type        = string
  default     = null

  validation {
    condition     = var.queue_storage_account_name == null || can(regex("^[a-z0-9]{3,24}$", coalesce(var.queue_storage_account_name, "x")))
    error_message = "queue_storage_account_name must be 3-24 characters of lowercase letters and digits only."
  }
}

variable "queue_account_replication_type" {
  description = "Replication for the created queue Storage Account. Defaults to LRS (single-region, cheapest); the queue is a transient delivery buffer."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], var.queue_account_replication_type)
    error_message = "queue_account_replication_type must be one of LRS, ZRS, GRS, GZRS, RAGRS, RAGZRS."
  }
}

variable "queue_name" {
  description = "Name of the Storage Queue created when create_queue_target = true (3-63 lowercase letters, digits and hyphens; cannot start/end with a hyphen)."
  type        = string
  default     = "eventgrid-events"

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])$", var.queue_name))
    error_message = "queue_name must be 3-63 chars of lowercase letters, digits and hyphens and may not start or end with a hyphen."
  }
}

variable "queue_message_ttl_seconds" {
  description = "Time-to-live (seconds) for events delivered into the created queue. null keeps Event Grid's default (7 days)."
  type        = number
  default     = null

  validation {
    condition     = var.queue_message_ttl_seconds == null ? true : var.queue_message_ttl_seconds > 0
    error_message = "queue_message_ttl_seconds must be a positive number of seconds, or null."
  }
}

variable "event_subscriptions" {
  description = <<-DESC
    Event subscriptions on the topic, keyed by subscription name. Each must
    target EXACTLY ONE endpoint:
      - use_created_queue = true            -> the module-created queue (requires create_queue_target)
      - storage_queue = { ... }             -> an existing storage queue
      - webhook = { url = "https://..." }   -> an HTTPS webhook (must answer the Event Grid validation handshake)
    Optional filters (included_event_types, subject_*), delivery schema, retry
    policy and a blob dead-letter destination are supported per subscription.
  DESC
  type = map(object({
    use_created_queue = optional(bool, false)

    storage_queue = optional(object({
      storage_account_id  = string
      queue_name          = string
      message_ttl_seconds = optional(number)
    }))

    webhook = optional(object({
      url                               = string
      max_events_per_batch              = optional(number)
      preferred_batch_size_in_kilobytes = optional(number)
      active_directory_tenant_id        = optional(string)
      active_directory_app_id_or_uri    = optional(string)
    }))

    # Filtering
    included_event_types                 = optional(list(string))
    subject_begins_with                  = optional(string)
    subject_ends_with                    = optional(string)
    subject_case_sensitive               = optional(bool, false)
    advanced_filtering_on_arrays_enabled = optional(bool, false)
    labels                               = optional(list(string), [])

    # Delivery reliability
    event_delivery_schema = optional(string, "EventGridSchema")
    max_delivery_attempts = optional(number, 30)
    event_ttl_minutes     = optional(number, 1440)

    # Optional blob dead-letter destination (undeliverable events)
    dead_letter_storage_account_id = optional(string)
    dead_letter_container_name     = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for s in values(var.event_subscriptions) :
      length([for present in [s.use_created_queue, s.storage_queue != null, s.webhook != null] : present if present]) == 1
    ])
    error_message = "Each event subscription must target exactly one of: use_created_queue, storage_queue, or webhook."
  }

  validation {
    condition = alltrue([
      for s in values(var.event_subscriptions) :
      s.max_delivery_attempts >= 1 && s.max_delivery_attempts <= 30 && s.event_ttl_minutes >= 1 && s.event_ttl_minutes <= 1440
    ])
    error_message = "Per subscription: max_delivery_attempts must be 1-30 and event_ttl_minutes must be 1-1440."
  }

  validation {
    condition = alltrue([
      for s in values(var.event_subscriptions) :
      contains(["EventGridSchema", "CloudEventSchemaV1_0", "CustomInputSchema"], s.event_delivery_schema)
    ])
    error_message = "event_delivery_schema must be EventGridSchema, CloudEventSchemaV1_0 or CustomInputSchema."
  }

  validation {
    condition = alltrue([
      for s in values(var.event_subscriptions) :
      (s.dead_letter_storage_account_id == null) == (s.dead_letter_container_name == null)
    ])
    error_message = "dead_letter_storage_account_id and dead_letter_container_name must be set together (or both omitted)."
  }
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
