# Shared tflint config for every Terraform root under _infra/terraform/.
#
# Passed explicitly with --config by _hack/scripts/iac-lint.sh: tflint only reads
# .tflint.hcl from its working directory, and the script lints each root from inside it,
# so a repo-root config would otherwise be ignored.
#
# Run `tflint --init --config .tflint.hcl` once to fetch the AWS plugin (needs network).

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# The AWS ruleset catches provider-specific mistakes the bundled terraform rules cannot:
# invalid instance types, malformed ARNs, deprecated or invalid arguments.
#
# deep_check stays OFF. It calls the AWS API to validate against real resources, and
# everything in this repo's lint path is offline and read-only (terraform.md).
plugin "aws" {
  enabled    = true
  version    = "0.49.0"
  source     = "github.com/terraform-linters/tflint-ruleset-aws"
  deep_check = false
}
