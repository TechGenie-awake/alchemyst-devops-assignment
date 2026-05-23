data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- Engine VM: public-facing gateway. Hosts the JSON API. ---
resource "aws_instance" "engine" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type_engine
  subnet_id                   = aws_subnet.public.id
  private_ip                  = var.engine_private_ip
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.engine.id]
  iam_instance_profile        = aws_iam_instance_profile.instance.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/startup-engine.sh", {
    repo_url    = var.repo_url
    repo_branch = var.repo_branch
  })

  tags = { Name = "${var.project_name}-engine" }
}

# --- Caller-worker VM: private, no public IP. ---
resource "aws_instance" "caller" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_caller
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.worker.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/startup-caller.sh", {
    repo_url    = var.repo_url
    repo_branch = var.repo_branch
    engine_ip   = var.engine_private_ip
  })

  # Don't launch until the private subnet's NAT route is in place,
  # otherwise the boot script's apt-get can fail before NAT is ready.
  depends_on = [aws_route_table_association.private]

  tags = { Name = "${var.project_name}-caller-worker" }
}

# --- Inference-worker VM: private, larger (model needs RAM). ---
resource "aws_instance" "inference" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_inference
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.worker.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/startup-inference.sh", {
    repo_url    = var.repo_url
    repo_branch = var.repo_branch
    engine_ip   = var.engine_private_ip
  })

  # Don't launch until the private subnet's NAT route is in place,
  # otherwise the boot script's apt-get can fail before NAT is ready.
  depends_on = [aws_route_table_association.private]

  tags = { Name = "${var.project_name}-inference-worker" }
}
