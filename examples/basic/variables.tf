variable "subscription_id" {
  description = "Target Azure subscription GUID. Leave null to use ARM_SUBSCRIPTION_ID from the environment."
  type        = string
  default     = null
}
