# =============================================================================
# ARC VALIDATION LAMBDA MODULE — main.tf
#
# Despliega la Lambda Python que el ARC Region Switch Plan invoca en el Paso 2
# del workflow para validar que la replicación DynamoDB es aceptable (<2000ms)
# antes de permitir el desvío de tráfico a Irlanda.
#
# Componentes:
#   1. Paquete zip (archive_file)
#   2. IAM Role + permisos mínimos (CloudWatch GetMetricStatistics)
#   3. CloudWatch Log Group con retención controlada
#   4. aws_lambda_function
#   5. Permiso para que el ARC service principal pueda invocarla
# =============================================================================

# ---------------------------------------------------------------------------
# 1. PAQUETE ZIP — empaqueta el handler Python sin herramientas externas
# ---------------------------------------------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/validate_replication.py"
  output_path = "${path.module}/lambda_src/validate_replication.zip"
}

# ---------------------------------------------------------------------------
# 2. IAM ROLE
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
  name               = "${var.name_prefix}-arc-validation-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = { Name = "${var.name_prefix}-arc-validation-role" }
}

# ── Managed: CloudWatch Logs básicos (put events, create streams) ─────────────
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ── Inline: solo CloudWatch GetMetricStatistics (least privilege) ─────────────
data "aws_iam_policy_document" "cloudwatch_read" {
  statement {
    sid    = "AllowCWGetMetricStats"
    effect = "Allow"

    actions = [
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:GetMetricData",
    ]

    # Scoped al namespace de DynamoDB — no se concede acceso a otras métricas
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["AWS/DynamoDB"]
    }
  }
}

resource "aws_iam_role_policy" "cloudwatch_read" {
  name   = "cloudwatch-dynamodb-read"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.cloudwatch_read.json
}

# ---------------------------------------------------------------------------
# 3. CLOUDWATCH LOG GROUP — retención controlada por variable
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.name_prefix}-arc-validation"
  retention_in_days = var.log_retention_days

  tags = { Name = "${var.name_prefix}-arc-validation-logs" }
}

# ---------------------------------------------------------------------------
# 4. LAMBDA FUNCTION
#    Python 3.12 — boto3 está disponible en el runtime sin capas adicionales
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "validate_replication" {
  function_name = "${var.name_prefix}-arc-validation"
  description   = "ARC Region Switch Paso 2: valida ReplicationLatency DynamoDB < ${var.max_latency_ms}ms antes de failover."

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  handler     = "validate_replication.lambda_handler"
  runtime     = "python3.12"
  role        = aws_iam_role.lambda_exec.arn
  timeout     = 60   # segundos — CloudWatch puede tardar en responder
  memory_size = 128  # MB — operación puramente de red/API, sin cómputo intensivo

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = var.dynamodb_table_name
      TARGET_REGION       = var.target_region
      MAX_LATENCY_MS      = tostring(var.max_latency_ms)
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution,
  ]

  tags = { Name = "${var.name_prefix}-arc-validation" }
}

# ---------------------------------------------------------------------------
# 5. LAMBDA RESOURCE POLICY — permite al ARC service invocar la función
#    El principal correcto para ARC Region Switch Plans es el servicio ARC.
# ---------------------------------------------------------------------------
resource "aws_lambda_permission" "allow_arc_invoke" {
  statement_id  = "AllowARCRegionSwitchInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.validate_replication.function_name
  principal     = "region-switch.arc.amazonaws.com"

  # Scoped a la cuenta actual para prevenir invocaciones cross-account
  source_account = var.account_id
}

# =============================================================================
# Required providers
# =============================================================================
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.31, < 7.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }
}
