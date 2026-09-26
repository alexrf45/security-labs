# A budget + alarm is mandatory in every environment (cost-guardrails.md rule 4),
# provisioned alongside the first resource, not later. AWS Budgets is free for the
# first two budgets. Thresholds are 50/80/100 percent of the $30 ceiling = $15/$24/$30
# (ADR-0011 §2).
#
# These notifications are unconditional on purpose. They used to be wrapped in a
# `length(var.budget_alert_emails) > 0` guard, which meant the default empty list
# produced a budget with NO notifications — an alarm-less budget that looks correctly
# configured in the console. budget_alert_emails is now a required variable with a
# non-empty validation, so the guard is gone and the failure is impossible.
locals {
  budget_notifications = [
    { threshold = 50, notification_type = "ACTUAL" },
    { threshold = 80, notification_type = "ACTUAL" },
    { threshold = 100, notification_type = "ACTUAL" },
    { threshold = 100, notification_type = "FORECASTED" },
  ]
}

resource "aws_budgets_budget" "range" {
  name         = "${var.project}-monthly"
  budget_type  = "COST"
  limit_amount = format("%g", var.budget_limit)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = local.budget_notifications
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value.threshold
      threshold_type             = "PERCENTAGE"
      notification_type          = notification.value.notification_type
      subscriber_email_addresses = var.budget_alert_emails
    }
  }
}
