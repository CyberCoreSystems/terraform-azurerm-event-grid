provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# Minimal, runnable example: a custom topic plus a module-created Storage Queue
# target, with one subscription wiring events into that queue. Consumes an
# existing resource group (create it first, e.g. `az group create`).
module "event_grid" {
  source = "../../"

  name                = "egt-app-prod"
  resource_group_name = "rg-eventgrid-example"
  location            = "eastus2"

  # Create the in-module Storage Queue delivery target.
  create_queue_target        = true
  queue_storage_account_name = "stegexampleprod001"
  queue_name                 = "orders-events"

  event_subscriptions = {
    to-queue = {
      use_created_queue    = true
      included_event_types = ["Orders.Created", "Orders.Updated"]
      subject_begins_with  = "orders/"
    }
  }

  tags = {
    environment = "example"
    managed_by  = "iac-bazaar"
  }
}
