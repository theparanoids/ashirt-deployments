# VPC Resources

resource "aws_vpc" "ashirt" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = var.app_name
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.ashirt.id
  tags = {
    Name = var.app_name
  }
}

resource "aws_eip" "ngw" {
  count = var.az_count
  vpc   = true
}

resource "aws_nat_gateway" "ngw" {
  count         = var.az_count
  subnet_id     = aws_subnet.public[count.index].id
  allocation_id = aws_eip.ngw[count.index].id
}

# Routes

resource "aws_route_table" "private" {
  count  = var.az_count
  vpc_id = aws_vpc.ashirt.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw[count.index].id
  }
}

resource "aws_subnet" "public" {
  count             = var.az_count
  availability_zone = data.aws_availability_zones.az.names[count.index]
  vpc_id            = aws_vpc.ashirt.id
  cidr_block        = cidrsubnet(aws_vpc.ashirt.cidr_block, 8, count.index)
  tags = {
    Name = "${var.app_name}-public"
  }
}

resource "aws_subnet" "private" {
  count             = var.az_count
  availability_zone = data.aws_availability_zones.az.names[count.index]
  vpc_id            = aws_vpc.ashirt.id
  cidr_block        = cidrsubnet(aws_vpc.ashirt.cidr_block, 8, var.az_count + count.index)
  tags = {
    Name = "${var.app_name}-private"
  }
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_vpc.ashirt.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "private_subnet" {
  count          = var.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

#Load Balancers

resource "aws_lb" "web" {
  name            = "${var.app_name}-web"
  internal        = true
  subnets         = aws_subnet.private.*.id
  security_groups = [aws_security_group.web-lb.id]
  tags = {
    Name = var.app_name
  }
}

resource "aws_lb" "api" {
  name            = "${var.app_name}-api"
  internal        = false
  subnets         = aws_subnet.public.*.id
  security_groups = [aws_security_group.api-lb.id]
  tags = {
    Name = var.app_name
  }
}

resource "aws_lb" "frontend" {
  name            = "${var.app_name}-frontend"
  internal        = false
  subnets         = aws_subnet.public.*.id
  security_groups = [aws_security_group.frontend-lb.id]
  tags = {
    Name = var.app_name
  }
}

resource "aws_lb_target_group" "web" {
  name        = "${var.app_name}-web-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.ashirt.id
  target_type = "ip"
  health_check {
    matcher = "200,401,404"
  }
}

resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.web.id
  port              = var.app_port
  protocol          = "HTTP"
  default_action {
    target_group_arn = aws_lb_target_group.web.id
    type             = "forward"
  }
}

resource "aws_lb_target_group" "api" {
  name        = "${var.app_name}-api-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.ashirt.id
  target_type = "ip"
  health_check {
    matcher = "200,401,404"
  }
}

resource "aws_lb_listener" "api" {
  load_balancer_arn = aws_lb.api.id
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.ashirt.arn
  default_action {
    target_group_arn = aws_lb_target_group.api.id
    type             = "forward"
  }
}

resource "aws_lb_target_group" "frontend" {
  name        = "${var.app_name}-frontend-tg"
  port        = var.nginx_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.ashirt.id
  target_type = "ip"
  health_check {
    interval            = 30
    unhealthy_threshold = 5
  }
}

resource "aws_lb_listener" "frontend" {
  load_balancer_arn = aws_lb.frontend.id
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.ashirt.arn
  default_action {
    target_group_arn = aws_lb_target_group.frontend.id
    type             = "forward"
  }
}

# Security Groups

resource "aws_security_group" "web-lb" {
  name        = "ashirt-web-lb"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.ashirt.id
  tags = {
    Name = "ashirt-web-sg"
  }
}

resource "aws_security_group" "api-lb" {
  name        = "ashirt-api-lb"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.ashirt.id
  tags = {
    Name = "ashirt-api-sg"
  }
}

resource "aws_security_group" "frontend-lb" {
  name        = "ashirt-frontend-lb"
  description = "Allow TLS inbound traffic to frontend"
  vpc_id      = aws_vpc.ashirt.id
  tags = {
    Name = "ashirt-frontend-sg"
  }
}

resource "aws_security_group_rule" "allow-egress-web-lb" {
  type              = "egress"
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  security_group_id = aws_security_group.web-lb.id
}

resource "aws_security_group_rule" "allow-egress-api-lb" {
  type              = "egress"
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  security_group_id = aws_security_group.api-lb.id
}

resource "aws_security_group_rule" "allow-egress-frontend-lb" {
  type              = "egress"
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  security_group_id = aws_security_group.frontend-lb.id
}

resource "aws_security_group_rule" "allow-ingress-api-lb" {
  type              = "ingress"
  to_port           = 443
  protocol          = "TCP"
  cidr_blocks       = var.allow_api_cidrs
  from_port         = 443
  security_group_id = aws_security_group.api-lb.id
}

resource "aws_security_group_rule" "allow-ingress-web-lb" {
  type                     = "ingress"
  to_port                  = var.app_port
  protocol                 = "TCP"
  from_port                = var.app_port
  source_security_group_id = aws_security_group.frontend-ecs.id
  security_group_id        = aws_security_group.web-lb.id
}

resource "aws_security_group_rule" "allow-ingress-frontend-lb" {
  type              = "ingress"
  to_port           = 443
  protocol          = "TCP"
  cidr_blocks       = var.allow_frontend_cidrs
  from_port         = 443
  security_group_id = aws_security_group.frontend-lb.id
}

resource "aws_security_group" "rds" {
  name        = "${var.app_name}-ashirt-rds"
  description = "allow traffic to rds"
  vpc_id      = aws_vpc.ashirt.id
}

resource "aws_security_group_rule" "allow-web-rds" {
  type                     = "ingress"
  to_port                  = 3306
  protocol                 = "TCP"
  from_port                = 3306
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = aws_security_group.web-ecs.id
}

resource "aws_security_group_rule" "allow-api-rds" {
  type                     = "ingress"
  to_port                  = 3306
  protocol                 = "TCP"
  from_port                = 3306
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = aws_security_group.api-ecs.id
}

resource "aws_security_group" "web-ecs" {
  name        = "${var.app_name}-web-ecs"
  description = "allow traffic to ecs"
  vpc_id      = aws_vpc.ashirt.id
}

resource "aws_security_group_rule" "allow-ingress-web-ecs" {
  type                     = "ingress"
  to_port                  = var.app_port
  protocol                 = "TCP"
  from_port                = var.app_port
  source_security_group_id = aws_security_group.web-lb.id
  security_group_id        = aws_security_group.web-ecs.id
}

resource "aws_security_group_rule" "allow-egress-web-ecs" {
  type              = "egress"
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  security_group_id = aws_security_group.web-ecs.id
}

resource "aws_security_group" "api-ecs" {
  name        = "${var.app_name}-api-ecs"
  description = "allow traffic to ecs"
  vpc_id      = aws_vpc.ashirt.id
}

resource "aws_security_group_rule" "allow-ingress-api-ecs" {
  type                     = "ingress"
  to_port                  = var.app_port
  protocol                 = "TCP"
  from_port                = var.app_port
  source_security_group_id = aws_security_group.api-lb.id
  security_group_id        = aws_security_group.api-ecs.id
}

resource "aws_security_group_rule" "allow-egress-api-ecs" {
  type              = "egress"
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  security_group_id = aws_security_group.api-ecs.id
}

resource "aws_security_group" "frontend-ecs" {
  name        = "${var.app_name}-frontend-ecs"
  description = "allow traffic to ecs"
  vpc_id      = aws_vpc.ashirt.id
}

resource "aws_security_group_rule" "allow-ingress-frontend-ecs" {
  type                     = "ingress"
  to_port                  = var.nginx_port
  protocol                 = "TCP"
  from_port                = var.nginx_port
  source_security_group_id = aws_security_group.frontend-lb.id
  security_group_id        = aws_security_group.frontend-ecs.id
}

resource "aws_security_group_rule" "allow-egress-frontend-ecs" {
  type              = "egress"
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  security_group_id = aws_security_group.frontend-ecs.id
}