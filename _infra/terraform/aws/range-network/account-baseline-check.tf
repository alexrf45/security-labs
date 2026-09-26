# Account baseline: VERIFIED here, never OWNED here.
#
# Three account+region EC2/EBS settings belong to the AWS account's permanent security
# baseline, not to the range: default EBS encryption, block-public-access for snapshots,
# and the regional IMDSv2 instance-metadata defaults. They are set once out of band and
# listed as Phase 0 prerequisites in the deployment runbook.
#
# They are deliberately NOT Terraform resources. The provider documents that removing
# aws_ebs_encryption_by_default *disables* default encryption and that removing
# aws_ebs_snapshot_block_public_access *unblocks* public sharing — so owning them from
# any root means `terraform destroy` on that root loosens the account. A security lab
# must not weaken its own account baseline as a side effect of tearing down a scenario,
# so the range verifies the baseline and has no power to revert it.
#
# Only default EBS encryption is checkable: it is the one of the three with a data
# source (there is none for snapshot block-public-access or instance metadata defaults,
# and the latter cannot even be imported). The other two stay runbook checklist items.
#
# This is a `check` block, so a failure is a plan/apply WARNING, not an error: the range
# is still safe to stand up without it (every volume sets `encrypted = true` explicitly
# and every instance sets its own metadata_options), and the data source is scoped inside
# the check so a failed read degrades to a warning instead of breaking the plan.
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
