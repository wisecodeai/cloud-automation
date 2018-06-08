# this module would create a new ebs volume and attach it to a particular instance


data "aws_instance" "worker" {
  filter {
    name   = "network-interface.addresses.private-ip-address"
    values = ["${var.instance_ip}"]
}


resource "aws_ebs_volume" "worker_extra_drive" {
    availability_zone = "${aws_instance.worker.availability_zone}"
    encrypted = true
    size = "${var.volume_size}"
    tags {
        Name = "${aws_instance.worker.tag:Name}_extravolume_${length(aws_instance.worker.ebs_block_device) + 1}"
    }
}


resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdz"
  volume_id   = "${aws_ebs_volume.worker_extra_drive.id}"
  instance_id = "${aws_instance.worker.id}"
}

