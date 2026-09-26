resource "aws_ebs_volume" "siem" {
  availability_zone = var.availability_zone
  size              = var.siem_volume_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name      = "${var.project}-siem-index"
    Discovery = "range-siem-volume"
  }

  lifecycle {
    prevent_destroy = true
  }
}
