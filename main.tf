provider "aws" {
	access_key = "${var.aws_access_key}"
	secret_key = "${var.aws_secret_key}"
	region = "us-west-2"
}

resource "aws_vpc" "myvpc" {
	cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "default" {
	vpc_id = "${aws_vpc.myvpc.id}"
}

# NAT

resource "aws_security_group" "nat" {
	name = "nat"
	description = "Allow services from the private subnet through NAT"

	ingress {
		from_port = 0
		to_port = 65535
		protocol = "tcp"
		cidr_blocks = ["${aws_subnet.us-west-2b-private.cidr_block}"]
	}
	ingress {
		from_port = 0
		to_port = 65535
		protocol = "tcp"
		cidr_blocks = ["${aws_subnet.us-west-2c-private.cidr_block}"]
	}

	vpc_id = "${aws_vpc.myvpc.id}"
}

resource "aws_instance" "nat" {
	ami = "${var.aws_nat_ami}"
	availability_zone = "us-west-2b"
	instance_type = "t2.micro"
	key_name = "${var.aws_key_name}"
	security_groups = ["${aws_security_group.nat.id}"]
	subnet_id = "${aws_subnet.us-west-2b-public.id}"
	associate_public_ip_address = true
	source_dest_check = false
}

resource "aws_eip" "nat" {
	instance = "${aws_instance.nat.id}"
	vpc = true
}

# Public subnets

resource "aws_subnet" "us-west-2b-public" {
	vpc_id = "${aws_vpc.myvpc.id}"

	cidr_block = "10.0.0.0/24"
	availability_zone = "us-west-2b"
}

resource "aws_subnet" "us-west-2c-public" {
	vpc_id = "${aws_vpc.myvpc.id}"

	cidr_block = "10.0.2.0/24"
	availability_zone = "us-west-2c"
}

# Routing table for public subnets

resource "aws_route_table" "us-west-2-public" {
	vpc_id = "${aws_vpc.myvpc.id}"

	route {
		cidr_block = "0.0.0.0/0"
		gateway_id = "${aws_internet_gateway.default.id}"
	}
}

resource "aws_route_table_association" "us-west-2b-public" {
	subnet_id = "${aws_subnet.us-west-2b-public.id}"
	route_table_id = "${aws_route_table.us-west-2-public.id}"
}

resource "aws_route_table_association" "us-west-2c-public" {
	subnet_id = "${aws_subnet.us-west-2c-public.id}"
	route_table_id = "${aws_route_table.us-west-2-public.id}"
}

# Private subsets

resource "aws_subnet" "us-west-2b-private" {
	vpc_id = "${aws_vpc.myvpc.id}"

	cidr_block = "10.0.1.0/24"
	availability_zone = "us-west-2b"
}

resource "aws_subnet" "us-west-2c-private" {
	vpc_id = "${aws_vpc.myvpc.id}"

	cidr_block = "10.0.3.0/24"
	availability_zone = "us-west-2c"
}

# Routing table for private subnets

resource "aws_route_table" "us-west-2-private" {
	vpc_id = "${aws_vpc.myvpc.id}"

	route {
		cidr_block = "0.0.0.0/0"
		instance_id = "${aws_instance.nat.id}"
	}
}

resource "aws_route_table_association" "us-west-2b-private" {
	subnet_id = "${aws_subnet.us-west-2b-private.id}"
	route_table_id = "${aws_route_table.us-west-2-private.id}"
}

resource "aws_route_table_association" "us-west-2c-private" {
	subnet_id = "${aws_subnet.us-west-2c-private.id}"
	route_table_id = "${aws_route_table.us-west-2-private.id}"
}

# Bastion

resource "aws_security_group" "bastion" {
	name = "bastion"
	description = "Allow SSH traffic from the internet"

	ingress {
		from_port = 22
		to_port = 22
		protocol = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
	}

	vpc_id = "${aws_vpc.myvpc.id}"
}

resource "aws_instance" "bastion" {
	ami = "${var.aws_ubuntu_ami}"
	availability_zone = "us-west-2b"
	instance_type = "t2.micro"
	key_name = "${var.aws_key_name}"
	security_groups = ["${aws_security_group.bastion.id}"]
	subnet_id = "${aws_subnet.us-west-2b-public.id}"
}

resource "aws_eip" "bastion" {
	instance = "${aws_instance.bastion.id}"
	vpc = true
}

resource "aws_ebs_volume" "myebs_vol" {
  availability_zone = "us-west-2a"
  size = 50
  type = "gp2"
}

resource "aws_security_group" "elb" {
  name        = "elb_sg"

  vpc_id = "${aws_vpc.myvpc.id}"

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elb" "bastion" {
  name = "bastion-elb"

  subnets = ["${aws_subnet.us-west-2b-public.id}"]

  security_groups = ["${aws_security_group.elb.id}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 30
  }

  instances                   = ["${aws_instance.bastion.id}"]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400
}

#resource "aws_db_instance" "mydb" {
#  allocated_storage    = 10
#  engine               = "mysql"
#  engine_version       = "5.6.17"
#  instance_class       = "db.t2.micro"
#  name                 = "mydb"
#  username             = "foo"
#  password             = "bar"
#  db_subnet_group_name = "my_database_subnet_group"
#  parameter_group_name = "default.mysql5.6"
}
