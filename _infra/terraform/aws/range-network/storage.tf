# The one deliberately non-ephemeral piece of the range (ADR-0011 §2). The
# defensive index and detection content are a *storage* need, not a compute need;
# at 30 GB gp3 this is ~$2.40/mo and survives every session teardown. The ops-tier
# collector attaches this volume (by tag lookup) at session start and detaches at
# teardown. prevent_destroy guards the accumulated detection baseline against an
# accidental `terraform destroy` of the shared root.
resource "aws_ebs_volume" "siem" {
  availability_zone = var.availability_zone
  size              = var.siem_volume_size
  type              = "gp3" # never gp2: gp2 is $0.10/GB-mo vs gp3 $0.08 (ADR-0011 §2)
  encrypted         = true

  tags = {
    Name      = "${var.project}-siem-index"
    Discovery = "range-siem-volume"
  }

  lifecycle {
    prevent_destroy = true
  }
}
