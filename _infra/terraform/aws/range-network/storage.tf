# The one non-ephemeral piece of the range: the SIEM index survives session teardown.
# ops-tier attaches it by tag lookup. prevent_destroy is deliberate.
resource "aws_ebs_volume" "siem" {
  availability_zone = var.availability_zone
  size              = var.siem_volume_size
  type              = "gp3" # never gp2: gp2 is $0.10/GB-mo vs gp3 $0.08
  encrypted         = true

  tags = {
    Name      = "${var.project}-siem-index"
    Discovery = "range-siem-volume"
  }

  lifecycle {
    prevent_destroy = true
  }
}
