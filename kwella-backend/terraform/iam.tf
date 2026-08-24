# ---------------------------------------------------------------------------
# kwella Lambda Execution Role — Shared IAM Identity
# ---------------------------------------------------------------------------
# All Lambda functions in this workspace assume this single execution role.
# Permissions are deliberately minimal (principle of least privilege):
#   • Native CloudWatch Logs write access via the AWS-managed execution policy.
#   • Scoped DynamoDB operations against the kwella core single-table only.
# ---------------------------------------------------------------------------

# ── Trust Policy ─────────────────────────────────────────────────────────────
# Allows the Lambda service to assume this role when invoking any function.

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

# ── Execution Role ────────────────────────────────────────────────────────────

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.project_name}-lambda-exec-${var.environment}"
  description        = "Shared execution role for all kwella Lambda functions. Grants CloudWatch logging and scoped DynamoDB access."
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# ── Managed Policy: CloudWatch Logs ──────────────────────────────────────────
# Provides CreateLogGroup, CreateLogStream, and PutLogEvents on the function's
# own log group — the standard baseline for Lambda observability.

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ── Inline Policy: Minimal Single-Table DynamoDB Access ──────────────────────
# Scoped exclusively to the kwella core DynamoDB table and its GSI1 index.
# Permits only the operations required by the identity and bidding microservices:
#   GetItem        — point lookups (profile reads, suspension checks)
#   PutItem        — new entity writes (profile creation)
#   UpdateItem     — partial attribute mutations (profile updates)
#   DeleteItem     — hard-delete operations (future purge flows)
#   Query          — PK/SK range scans and GSI1 fleet/vehicle lookups
#   BatchWriteItem — bulk seed operations used by integration test fixtures

data "aws_iam_policy_document" "dynamodb_single_table" {
  statement {
    sid    = "KwellaCoreTableAccess"
    effect = "Allow"

    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:BatchWriteItem",
    ]

    resources = [
      # Primary table
      aws_dynamodb_table.kwella_core.arn,
      # GSI1 — required for Query operations that target the index
      "${aws_dynamodb_table.kwella_core.arn}/index/GSI1",
    ]
  }

  # Grants the bidding engine Lambda the ability to push async messages back
  # to connected WebSocket clients via the API Gateway Management API, and to
  # publish SNS notifications. The execute-api actions are scoped to this
  # region's API Gateway pool (least-privilege); SNS actions are account-wide
  # because topic ARNs are resolved at runtime.
  statement {
    sid    = "KwellaBiddingEngineWebSocketPush"
    effect = "Allow"

    actions = [
      "execute-api:ManageConnections",
      "execute-api:Invoke",
    ]

    resources = ["arn:aws:execute-api:af-south-1:*:*/*"]
  }

  statement {
    sid    = "KwellaBiddingEngineSnsPublish"
    effect = "Allow"

    actions = [
      "sns:Publish",
      "sns:CreatePlatformEndpoint",
    ]

    resources = ["*"]
  }

  # Grants the identity service Lambda the ability to presign PUT URLs for
  # driver onboarding documents. Scoped to the driver-documents bucket only.
  statement {
    sid    = "KwellaIdentityServiceDocumentUpload"
    effect = "Allow"

    actions = [
      "s3:PutObject",
    ]

    resources = ["${aws_s3_bucket.driver_documents.arn}/*"]
  }
}

resource "aws_iam_role_policy" "dynamodb_access" {
  name   = "${var.project_name}-dynamodb-access-${var.environment}"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.dynamodb_single_table.json
}
