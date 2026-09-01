# Event Grid custom topic + event subscriptions, with an optional in-module
# Storage Queue delivery target so you get a complete, working pub/sub pipeline
# from a single apply. Consumes an EXISTING resource group.
#
# Secure defaults:
# - Local (access-key/SAS) auth on the topic is DISABLED — publish with Entra ID
#   / managed identity. Flip local_auth_enabled = true only if you must use keys.
# - A system-assigned managed identity is always created on the topic (use it for
#   managed delivery/dead-lettering with least privilege).
# - Public network access stays on by default (Event Grid's normal posture) but
#   can be narrowed to specific source IPs, or turned off for private endpoints.
# - The created queue Storage Account is HTTPS-only, TLS 1.2+, no anonymous blob
#   access, no cross-tenant replication, with infrastructure (double) encryption,
#   queue-service request logging (7-day retention), blob soft-delete (7 days)
#   and a SAS expiration policy that flags tokens living longer than 7 days.

locals {
  # A system-assigned identity is always present; attach user-assigned ones too
  # when identity_ids are supplied.
  identity_type = length(var.identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"

  create_queue = var.create_queue_target
}

resource "azurerm_eventgrid_topic" "this" {
  # checkov:skip=CKV_AZURE_193: public endpoint is Event Grid's normal publish posture and a deliberate buyer knob (public_network_access_enabled, narrowable via allowed_inbound_ip_masks or disabled for private endpoints); key/SAS auth is OFF by default so publishing is Entra-only
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  input_schema                  = var.input_schema
  local_auth_enabled            = var.local_auth_enabled
  public_network_access_enabled = var.public_network_access_enabled

  # inbound_ip_rule is a list attribute in azurerm v4 (assigned, not a block).
  inbound_ip_rule = length(var.allowed_inbound_ip_masks) > 0 ? [
    for mask in var.allowed_inbound_ip_masks : {
      ip_mask = mask
      action  = "Allow"
    }
  ] : null

  identity {
    type         = local.identity_type
    identity_ids = var.identity_ids
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = length(var.allowed_inbound_ip_masks) == 0 || var.public_network_access_enabled
      error_message = "allowed_inbound_ip_masks requires public_network_access_enabled = true."
    }
  }
}

# ---------------------------------------------------------------------------
# Optional in-module delivery target: a Storage Account + Queue. Shared keys
# stay enabled here because Event Grid delivers to a Storage Queue with the
# account key (no managed-identity delivery configured), and the provider needs
# data-plane access to create the queue.
# ---------------------------------------------------------------------------

resource "azurerm_storage_account" "queue" {
  # checkov:skip=CKV_AZURE_59: the applying client and Event Grid delivery reach the queue over the public endpoint by design for this optional convenience target; HTTPS-only + TLS1.2 + no anonymous blob access are enforced — bring your own account via event_subscriptions.storage_queue for private topologies
  # checkov:skip=CKV2_AZURE_40: shared key auth stays enabled by design — Event Grid storage-queue delivery and the provider's data-plane queue management authenticate with the account key (documented above)
  # checkov:skip=CKV2_AZURE_33: private-endpoint plumbing is out of scope for this optional in-module delivery target; use event_subscriptions.storage_queue to deliver to your own privately-networked storage account
  # checkov:skip=CKV2_AZURE_1: this transient event-delivery buffer uses Microsoft-managed keys plus infrastructure (double) encryption; for CMK, deliver to your own account via event_subscriptions.storage_queue
  # checkov:skip=CKV_AZURE_206: replication is a deliberate buyer knob (queue_account_replication_type); default LRS suits a transient delivery buffer
  count = local.create_queue ? 1 : 0

  name                = var.queue_storage_account_name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.queue_account_replication_type

  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  shared_access_key_enabled         = true
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  public_network_access_enabled     = true
  infrastructure_encryption_enabled = true

  # Log every queue data-plane operation (classic Storage Analytics logging for
  # the Queue service) and keep the logs for 7 days.
  queue_properties {
    logging {
      delete                = true
      read                  = true
      write                 = true
      version               = "1.0"
      retention_policy_days = 7
    }
  }

  # Soft-delete for blobs (the account is queue-focused, but any blob written to
  # it — e.g. a future dead-letter container — gets a 7-day recovery window).
  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

  # Flag (via the activity log) any SAS token minted with a lifetime over 7 days.
  sas_policy {
    expiration_period = "07.00:00:00"
    expiration_action = "Log"
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = !local.create_queue || var.queue_storage_account_name != null
      error_message = "create_queue_target = true requires queue_storage_account_name (a globally-unique 3-24 lowercase alphanumeric name)."
    }
  }
}

resource "azurerm_storage_queue" "this" {
  count = local.create_queue ? 1 : 0

  name               = var.queue_name
  storage_account_id = azurerm_storage_account.queue[0].id
}

# ---------------------------------------------------------------------------
# Event subscriptions
# ---------------------------------------------------------------------------

resource "azurerm_eventgrid_event_subscription" "this" {
  for_each = var.event_subscriptions

  name  = each.key
  scope = azurerm_eventgrid_topic.this.id

  event_delivery_schema                = each.value.event_delivery_schema
  included_event_types                 = each.value.included_event_types
  labels                               = each.value.labels
  advanced_filtering_on_arrays_enabled = each.value.advanced_filtering_on_arrays_enabled

  dynamic "storage_queue_endpoint" {
    for_each = each.value.use_created_queue || each.value.storage_queue != null ? [1] : []
    content {
      storage_account_id                    = each.value.use_created_queue ? one(azurerm_storage_account.queue[*].id) : each.value.storage_queue.storage_account_id
      queue_name                            = each.value.use_created_queue ? one(azurerm_storage_queue.this[*].name) : each.value.storage_queue.queue_name
      queue_message_time_to_live_in_seconds = each.value.use_created_queue ? var.queue_message_ttl_seconds : each.value.storage_queue.message_ttl_seconds
    }
  }

  dynamic "webhook_endpoint" {
    for_each = each.value.webhook != null ? [each.value.webhook] : []
    content {
      url                               = webhook_endpoint.value.url
      max_events_per_batch              = webhook_endpoint.value.max_events_per_batch
      preferred_batch_size_in_kilobytes = webhook_endpoint.value.preferred_batch_size_in_kilobytes
      active_directory_tenant_id        = webhook_endpoint.value.active_directory_tenant_id
      active_directory_app_id_or_uri    = webhook_endpoint.value.active_directory_app_id_or_uri
    }
  }

  dynamic "subject_filter" {
    for_each = (each.value.subject_begins_with != null || each.value.subject_ends_with != null) ? [1] : []
    content {
      subject_begins_with = each.value.subject_begins_with
      subject_ends_with   = each.value.subject_ends_with
      case_sensitive      = each.value.subject_case_sensitive
    }
  }

  retry_policy {
    max_delivery_attempts = each.value.max_delivery_attempts
    event_time_to_live    = each.value.event_ttl_minutes
  }

  dynamic "storage_blob_dead_letter_destination" {
    for_each = each.value.dead_letter_storage_account_id != null ? [1] : []
    content {
      storage_account_id          = each.value.dead_letter_storage_account_id
      storage_blob_container_name = each.value.dead_letter_container_name
    }
  }

  lifecycle {
    precondition {
      condition     = !each.value.use_created_queue || var.create_queue_target
      error_message = "A subscription sets use_created_queue = true but create_queue_target is false. Enable create_queue_target or supply an explicit storage_queue/webhook endpoint."
    }
  }
}
