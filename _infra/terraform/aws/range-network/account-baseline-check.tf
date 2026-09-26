# Account baseline: VERIFIED here, never OWNED here. Do not convert these to resources —
# destroying them would loosen the account baseline. Set out of band in Phase 0.
check "account_ebs_encryption_baseline" {
  data "aws_ebs_encryption_by_default" "current" {}

  assert {
    condition = data.aws_ebs_encryption_by_default.current.enabled
    error_message = join(" ", [
      "Account baseline drift: EBS encryption-by-default is DISABLED in this region.",
      "The range still encrypts every volume it creates explicitly, so this is not a",
      "range defect, but anything created outside these roots would be unencrypted.",
      "Re-enable with: aws ec2 enable-ebs-encryption-by-default",
    ])
  }
}
