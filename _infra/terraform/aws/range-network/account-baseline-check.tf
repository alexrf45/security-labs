check "account_ebs_encryption_baseline" {
  data "aws_ebs_encryption_by_default" "current" {}

  assert {
    condition = data.aws_ebs_encryption_by_default.current.enabled
    error_message = join(" ", [
      "Account baseline drift: EBS encryption-by-default is DISABLED in this region.",
      "Re-enable with: aws ec2 enable-ebs-encryption-by-default",
    ])
  }
}
