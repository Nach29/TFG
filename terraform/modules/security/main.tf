# Create the Security Group container.
resource "aws_security_group" "this" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id
  tags        = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# Split rules depending on whether they use cidr_blocks or security_groups.
locals {
  ingress_with_cidr   = { for idx, r in var.ingress_rules : idx => r if r.cidr_blocks != null && length(r.cidr_blocks) > 0 }
  ingress_with_sg_raw = { for idx, r in var.ingress_rules : idx => r if r.security_groups != null && length(r.security_groups) > 0 }

  ingress_sg_pairs = {
    for pair in flatten([for idx, r in local.ingress_with_sg_raw : [for sg_index, sg in r.security_groups : { id = "${idx}-${sg_index}", idx = idx, sg_index = sg_index, sg = sg, rule = r }]]) : pair.id => pair
  }

  egress_with_cidr   = { for idx, r in var.egress_rules : idx => r if r.cidr_blocks != null && length(r.cidr_blocks) > 0 }
  egress_with_sg_raw = { for idx, r in var.egress_rules : idx => r if r.security_groups != null && length(r.security_groups) > 0 }

  egress_sg_pairs = {
    for pair in flatten([for idx, r in local.egress_with_sg_raw : [for sg_index, sg in r.security_groups : { id = "${idx}-${sg_index}", idx = idx, sg_index = sg_index, sg = sg, rule = r }]]) : pair.id => pair
  }
}

# Ingress rules based on CIDR lists.
resource "aws_security_group_rule" "ingress_cidr" {
  for_each = local.ingress_with_cidr

  type              = "ingress"
  security_group_id = aws_security_group.this.id

  description = each.value.description
  from_port   = each.value.from_port
  to_port     = each.value.to_port
  protocol    = each.value.protocol
  cidr_blocks = each.value.cidr_blocks
}

# Ingress rules where the source is another Security Group.
resource "aws_security_group_rule" "ingress_sg" {
  for_each = local.ingress_sg_pairs

  type                     = "ingress"
  security_group_id        = aws_security_group.this.id
  description              = each.value.rule.description
  from_port                = each.value.rule.from_port
  to_port                  = each.value.rule.to_port
  protocol                 = each.value.rule.protocol
  source_security_group_id = each.value.sg
}

# Egress rules based on CIDR lists.
resource "aws_security_group_rule" "egress_cidr" {
  for_each = local.egress_with_cidr

  type              = "egress"
  security_group_id = aws_security_group.this.id

  description = each.value.description
  from_port   = each.value.from_port
  to_port     = each.value.to_port
  protocol    = each.value.protocol
  cidr_blocks = each.value.cidr_blocks
}

# Egress rules where the destination is another Security Group.
resource "aws_security_group_rule" "egress_sg" {
  for_each = local.egress_sg_pairs

  type                     = "egress"
  security_group_id        = aws_security_group.this.id
  description              = each.value.rule.description
  from_port                = each.value.rule.from_port
  to_port                  = each.value.rule.to_port
  protocol                 = each.value.rule.protocol
  source_security_group_id = each.value.sg
}

# =============================================================================
# Required providers: allows the root module to pass provider aliases.
# Ref: https://developer.hashicorp.com/terraform/language/modules/develop/providers
# =============================================================================
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.31, < 7.0"
    }
  }
}
