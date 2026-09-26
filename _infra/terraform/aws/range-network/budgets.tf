# A budget with notifications is mandatory (cost-guardrails.md rule 4). Thresholds are
# 50/80/100 percent of the ceiling. Do NOT make the notifications conditional: an empty
# subscriber list yields a budget that alerts nobody and looks correct in the console.
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
