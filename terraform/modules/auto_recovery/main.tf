# =============================================================================
# AUTO-RECOVERY MODULE — main.tf
#
# Implements a Closed-Loop Auto-Recovery system using AWS ARC Zonal Shift.
#
# Architecture:
#   CloudWatch Alarm (per AZ, 5XX spike) → Lambda (direct invocation)
#                                         → ARC Zonal Shift (shift ALB traffic)
#
# Key design decisions:
#   - Direct CloudWatch → Lambda integration (no SNS/EventBridge middleman)
#   - One alarm per AZ so the Lambda knows exactly WHICH AZ is impaired
#   - The Lambda Python script is packaged inline via archive_file
#   - Zonal shift expires automatically after var.zonal_shift_expiry_minutes
# =============================================================================

# ---------------------------------------------------------------------------
# 1. LAMBDA DEPLOYMENT PACKAGE
#    Package the Python handler file into a zip archive inline, using
#    archive_file so no external tooling (pip, zip CLI) is required.
# ---------------------------------------------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/zonal_shift_handler.py"
  output_path = "${path.module}/lambda_src/zonal_shift_handler.zip"
}

# ---------------------------------------------------------------------------
# 2. IAM ROLE FOR LAMBDA
#    Trust policy: only lambda.amazonaws.com may assume this role.
#    Permissions:
#      a) AWS managed policy  → basic Lambda execution + CloudWatch Logs
#      b) Inline policy       → least-privilege ARC Zonal Shift actions
# ---------------------------------------------------------------------------
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

# ── a) Managed Policy — CloudWatch Logs (create log groups, streams, put events)
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ── b) Inline Policy — ARC Zonal Shift (start & cancel, scoped to this ALB ARN)
data "aws_iam_policy_document" "arc_zonal_shift" {
  statement {
    sid    = "AllowARCZonalShiftOnALB"
    effect = "Allow"

    actions = [
      "arc-zonal-shift:StartZonalShift",
      "arc-zonal-shift:CancelZonalShift",
    ]

    # Scope to the specific ALB ARN — principle of least privilege.
    # ARC Zonal Shift uses the "arc-zonal-shift" API namespace; the
    # resource ARN is the ARN of the Load Balancer being shifted.
    resources = [var.alb_arn]
  }
}

resource "aws_iam_role_policy" "arc_zonal_shift" {
  name   = "arc-zonal-shift-policy"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.arc_zonal_shift.json
}

# ---------------------------------------------------------------------------
# 3. CLOUDWATCH LOG GROUP
#    Explicit log group so we control retention and tagging.
#    Lambda creates its own group (/aws/lambda/<name>) automatically but
#    declaring it here allows Terraform to manage lifecycle + retention.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_prefix}-auto-recovery"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(var.tags, {
    Name = "${var.project_prefix}-auto-recovery-logs"
  })
}

# ---------------------------------------------------------------------------
# 4. LAMBDA FUNCTION
#    Python 3.12 runtime. boto3 is included in the Lambda execution
#    environment by default — no Lambda Layer needed for SDK access.
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "zonal_shift" {
  function_name = "${var.project_prefix}-auto-recovery"
  description   = "Closed-Loop Auto-Recovery: invoked by CW Alarms to trigger ARC Zonal Shift on ALB 5XX spikes."

  # Inline deployment package (archive_file above)
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  handler     = "zonal_shift_handler.lambda_handler"
  runtime     = "python3.12"
  role        = aws_iam_role.lambda_exec.arn
  timeout     = 30  # seconds — ARC API calls are fast; 30s is generous
  memory_size = 128 # MB — minimal footprint for a pure SDK call

  environment {
    variables = {
      # Passed as env vars so the Lambda handler has no hardcoded values
      ALB_ARN        = var.alb_arn
      EXPIRY_MINUTES = tostring(var.zonal_shift_expiry_minutes)
    }
  }

  # Ensure the log group exists before the function (avoids a race where
  # Lambda auto-creates it without the desired retention setting)
  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution,
  ]

  tags = merge(var.tags, {
    Name = "${var.project_prefix}-auto-recovery"
  })
}

# ---------------------------------------------------------------------------
# 5. LAMBDA RESOURCE POLICY (Permissions)
#    Allow CloudWatch Alarms to invoke this Lambda directly.
#
#    principal:  lambda.alarms.cloudwatch.amazonaws.com
#    source_arn: wildcard for ALL alarms in this account/region so each
#                per-AZ alarm can invoke the function without adding N
#                separate aws_lambda_permission resources.
#
#    Note: Using source_account (not source_arn) here is the recommended
#    practice for CloudWatch → Lambda direct integrations because individual
#    alarm ARNs are unknown at plan time (they contain the alarm name hash).
# ---------------------------------------------------------------------------
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_lambda_permission" "allow_cloudwatch_alarms" {
  statement_id  = "AllowCloudWatchAlarmsInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.zonal_shift.function_name
  principal     = "lambda.alarms.cloudwatch.amazonaws.com"

  # Scope the permission to this AWS account so no cross-account alarm
  # can invoke the function.
  source_account = data.aws_caller_identity.current.account_id
}

# ---------------------------------------------------------------------------
# 6. CLOUDWATCH ALARMS — One per Availability Zone
#
#    Metric:    HTTPCode_Target_5XX_Count
#    Namespace: AWS/ApplicationELB
#    Dimensions: LoadBalancer (ALB suffix) + AvailabilityZone
#
#    When SUM > var.alarm_5xx_threshold in 1 period the alarm fires and
#    directly invokes the Lambda function (alarm_actions = [lambda ARN]).
#
#    The AvailabilityZone dimension is what the Lambda reads from the alarm
#    payload to know which AZ is impaired.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "alb_5xx_per_az" {
  # One alarm resource per AZ; for_each iterates over the AZ list converted
  # to a set so each alarm has a stable, unique key.
  for_each = toset(var.availability_zones)

  alarm_name        = "${var.project_prefix}-5xx-alarm-${each.key}"
  alarm_description = "5XX error spike in AZ ${each.key} on ALB — triggers ARC Zonal Shift auto-recovery."

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_Target_5XX_Count"
  statistic   = "Sum"

  # Period & evaluation: ALARM if sum > threshold in a single 1-minute window.
  period              = var.alarm_period_seconds
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = var.alarm_5xx_threshold
  comparison_operator = "GreaterThanThreshold"

  # treat_missing_data = "notBreaching" prevents the alarm from firing when
  # there is simply no traffic (absence of data ≠ errors).
  treat_missing_data = "notBreaching"

  dimensions = {
    # LoadBalancer value must be the ARN *suffix* (e.g. "app/my-alb/1234abc")
    # not the full ARN — this is the format CloudWatch uses internally.
    LoadBalancer     = var.alb_arn_suffix
    AvailabilityZone = each.key
  }

  # Direct CloudWatch → Lambda integration: set alarm_actions to the Lambda ARN.
  # No SNS topic or EventBridge rule required.
  alarm_actions = [aws_lambda_function.zonal_shift.arn]

  # Do NOT set ok_actions — we intentionally let the zonal shift expire on its
  # own schedule (EXPIRY_MINUTES) rather than cancelling it when the alarm
  # clears, to avoid flapping.

  tags = merge(var.tags, {
    Name             = "${var.project_prefix}-5xx-alarm-${each.key}"
    AvailabilityZone = each.key
  })
}
