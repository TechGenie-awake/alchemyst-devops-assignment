# Engine SG: public API on 3111 plus all intra-VPC traffic (so workers
# can reach the engine on the RPC port 49134).
resource "aws_security_group" "engine" {
  name        = "${var.project_name}-engine-sg"
  description = "Public API + intra-VPC worker RPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Public JSON API"
    from_port   = 3111
    to_port     = 3111
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "All TCP from inside the VPC (carries worker RPC on 49134)"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-engine-sg" }
}

# Worker SG: internal traffic only. No public ingress.
resource "aws_security_group" "worker" {
  name        = "${var.project_name}-worker-sg"
  description = "Internal-only ingress for workers"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "All TCP from inside the VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-worker-sg" }
}
