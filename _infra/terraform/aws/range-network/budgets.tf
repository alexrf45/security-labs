# A budget + alarm is mandatory in every environment (cost-guardrails.md rule 4),
# provisioned alongside the first resource, not later. AWS Budgets is free for the
# first two budgets. Thresholds are 50/80/100 percent of the $30 ceiling = $15/$24/$30
# (ADR-0011 §2). Notifications are created only when budget_alert_emails is set, so no
# address is baked into the repo; set it in your SOPS-encrypted terraform.tfvars.
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
    for_each = length(var.budget_alert_emails) > 0 ? local.budget_notifications : []
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value.threshold
      threshold_type             = "PERCENTAGE"
      notification_type          = notification.value.notification_type
      subscriber_email_addresses = var.budget_alert_emails
    }
  }
}
