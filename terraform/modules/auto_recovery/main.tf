# =============================================================================
# AUTO-RECOVERY MODULE
#
# Closed-loop zonal recovery for the public ALB in the active region.
#
# Flow:
#   CloudWatch Alarm per AZ -> Lambda -> ARC Zonal Shift
#
# The module packages the Lambda handler with archive_file, creates the Lambda
# execution role, grants the minimum ARC Zonal Shift permissions, and wires each
# per-AZ 5XX alarm directly to the Lambda function.
# =============================================================================

# -----------------------------------------------------------------------------
# Lambda deployment package
# -----------------------------------------------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/zonal_shift_handler.py"
  output_path = "${path.root}/${var.project_prefix}-auto-recovery.zip"
}

# -----------------------------------------------------------------------------
# Lambda execution role
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    sid     = "AllowLambdaAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.project_prefix}-auto-recovery-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = merge(var.tags, {
    Name = "${var.project_prefix}-auto-recovery-lambda-role"
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "arc_zonal_shift" {
  statement {
    sid    = "AllowARCZonalShiftOnALB"
    effect = "Allow"

    actions = [
      "arc-zonal-shift:StartZonalShift",
      "arc-zonal-shift:CancelZonalShift",
    ]

    resources = [var.alb_arn]
  }
}

resource "aws_iam_role_policy" "arc_zonal_shift" {
  name   = "arc-zonal-shift-policy"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.arc_zonal_shift.json
}

# -----------------------------------------------------------------------------
# CloudWatch logs
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_prefix}-auto-recovery"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(var.tags, {
    Name = "${var.project_prefix}-auto-recovery-logs"
  })
}

# -----------------------------------------------------------------------------
# Lambda function
# -----------------------------------------------------------------------------
data "aws_availability_zones" "current_azs" {}

resource "aws_lambda_function" "zonal_shift" {
  function_name = "${var.project_prefix}-auto-recovery"
  description   = "Closed-loop ARC Zonal Shift auto-recovery for ALB 5XX spikes."

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  handler     = "zonal_shift_handler.lambda_handler"
  runtime     = "python3.12"
  role        = aws_iam_role.lambda_exec.arn
  timeout     = 30
  memory_size = 128

  environment {
    variables = {
      ALB_ARN        = var.alb_arn
      EXPIRY_MINUTES = tostring(var.zonal_shift_expiry_minutes)
      AZ_MAPPING     = jsonencode(zipmap(data.aws_availability_zones.current_azs.names, data.aws_availability_zones.current_azs.zone_ids))
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution,
  ]

  tags = merge(var.tags, {
    Name = "${var.project_prefix}-auto-recovery"
  })
}

# -----------------------------------------------------------------------------
# Allow CloudWatch alarms to invoke the Lambda directly
# -----------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

resource "aws_lambda_permission" "allow_cloudwatch_alarms" {
  statement_id  = "AllowCloudWatchAlarmsInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.zonal_shift.function_name
  principal     = "lambda.alarms.cloudwatch.amazonaws.com"

  source_account = data.aws_caller_identity.current.account_id
}

# -----------------------------------------------------------------------------
# Per-AZ ALB 5XX alarms
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "alb_5xx_per_az" {
  for_each = toset(var.availability_zones)

  alarm_name        = "${var.project_prefix}-5xx-alarm-${each.key}"
  alarm_description = "5XX error spike in AZ ${each.key} on ALB triggers ARC Zonal Shift auto-recovery."
  namespace         = "AWS/ApplicationELB"
  metric_name       = "HTTPCode_Target_5XX_Count"
  statistic         = "Sum"

  period              = var.alarm_period_seconds
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = var.alarm_5xx_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer     = var.alb_arn_suffix
    AvailabilityZone = each.key
  }

  alarm_actions = [aws_lambda_function.zonal_shift.arn]

  tags = merge(var.tags, {
    Name             = "${var.project_prefix}-5xx-alarm-${each.key}"
    AvailabilityZone = each.key
  })
}
