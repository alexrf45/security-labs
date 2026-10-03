---
description: Lint the Terraform under _infra/ — fmt, validate and tflint. Read-only.
---

Lint the Infrastructure as Code: `terraform fmt`/`validate` + `tflint` across `_infra/`.

Read-only — never runs plan/apply or touches state. Uses the raw terraform binary
(bypasses the 1Password wrapper, which is only needed for plan/apply).

```bash
bash _hack/scripts/iac-lint.sh
```

Report the result. On a `fmt` failure, give the exact `terraform fmt -recursive
_infra/terraform` command to fix it. On a `validate`/`tflint` failure, surface the
offending directory and error. Directories whose `init` failed offline (no
provider network) are skipped, not failed — note them if any.

> Packer linting is out of scope for now (image builds are deferred in the cloud
> pivot; `packer` isn't installed locally). Re-add the Packer pass to
> `iac-lint.sh` when golden-image builds return.
