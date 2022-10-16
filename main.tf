module "awsvpc" {
  source = "/var/terraform/modules/vpc_module/"           #location of the module

  project_name = var.project_name
  project_env = var.project_env
  vpc_cidr = var.cidr_block
  region = var.region
}

resource "aws_security_group" "sg" {

  name_prefix = "freedom-"
  description = "allow http, https, ssh"
  vpc_id      = module.awsvpc.myvpc

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
    ipv6_cidr_blocks = [ "::/0" ]
  }

  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
    ipv6_cidr_blocks = [ "::/0" ]
  }

    ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
    ipv6_cidr_blocks = [ "::/0" ]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [ "0.0.0.0/0" ]
    ipv6_cidr_blocks = [ "::/0" ]
  }

  tags = {
    Name = "${var.project_name}-sg",
    project = var.project_name,
    env = var.project_env
  }
  lifecycle {
    create_before_destroy = true
  }
}

data "aws_ami" "zomato-prod" {

  owners       = ["self"]
  most_recent  = true

  filter {
    name   = "name"
    values = ["zomato-prod-v*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

output "zomato-prod-ami-latest" {

   value = data.aws_ami.zomato-prod.image_id
}

resource "aws_elb" "clb" {

  name_prefix        = "zomat-"
  subnets            = [ module.awsvpc.public1, module.awsvpc.public2]           #to select the subnets on which lb have to be created
  security_groups    = [ aws_security_group.sg.id ]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "arn:aws:acm:ap-south-1:270372200988:certificate/4bbb40f8-fa96-4113-8bad-7b34c0132202"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/index.php"
    interval            = 30
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 60
  connection_draining         = true
  connection_draining_timeout = 5

  tags   = {
    Name = "${var.project_name}-${var.project_env}"
    project = "${var.project_name}",
    env = "${var.project_env}"
  }
}

resource "aws_key_pair" "mykey" {
  key_name   = "${var.project_name}-${var.project_env}"
  public_key = file("key.pub")                                     #create a key pair with name "key" in project directory
  tags = {
    Name = "${var.project_name}-${var.project_env}",
    project = var.project_name
    env = var.project_env
  }
  }

resource "aws_launch_configuration" "lc" {

  name_prefix   = "${var.project_name}-${var.project_env}-"
  image_id      = data.aws_ami.zomato-prod.image_id
  instance_type = var.instance_type
  key_name      = aws_key_pair.mykey.id
  security_groups    = [ aws_security_group.sg.id ]
  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_autoscaling_group" "asg" {

  name_prefix = "${var.project_name}-${var.project_env}-"
  default_instance_warmup = 120
  vpc_zone_identifier = [ module.awsvpc.public1, module.awsvpc.public2 ]     #to select the subnet on which asg have to be created
  desired_capacity = 2
  max_size = 2
  min_size = 2
  force_delete = true
  health_check_type = "EC2"
  load_balancers = [ aws_elb.clb.name ]
  launch_configuration = aws_launch_configuration.lc.id
  tag {
    key = "Name"
    value = "${var.project_name}-${var.project_env}"
    propagate_at_launch = true
  }

  tag {
    key = "project"
    value = "${var.project_name}"
    propagate_at_launch = true
  }

  tag {
    key = "env"
    value = "${var.project_env}"
    propagate_at_launch = true
  }


  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "record" {                     #to point lb dns name to our sub domain
  zone_id = var.hosted_zone
  name    = "blog.hemanth.store"
  type    = "A"

  alias {
    name                   = aws_elb.clb.dns_name
    zone_id                = aws_elb.clb.zone_id
    evaluate_target_health = true
  }
}
