terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# ---------------------------------------------------------------------------
# kwella Core DynamoDB Single-Table
# ---------------------------------------------------------------------------
# Entity key patterns (from KWELLA_SYSTEM_CONTEXT.md §3):
#
#   Rider Profile  → PK: USR#<RiderId>          SK: PROFILE
#   Driver Profile → PK: USR#<DriverId>         SK: PROFILE
#                    GSI1_PK: VEH#<AssignedCataSticker>  GSI1_SK: DRIVER
#   Owner Profile  → PK: USR#<OwnerId>          SK: PROFILE
#   Vehicle Asset  → PK: VEH#<CataSticker>      SK: METADATA
#                    GSI1_PK: USR#<OwnerId>      GSI1_SK: VEH#<CataSticker>
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "kwella_core" {
  name         = "${var.project_name}-core-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # ── Primary key attributes ──────────────────────────────────────────────
  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  # ── GSI1 attributes ─────────────────────────────────────────────
  attribute {
    name = "GSI1_PK"
    type = "S"
  }

  attribute {
    name = "GSI1_SK"
    type = "S"
  }

  # ── Global Secondary Index ───────────────────────────────────────────────
  # GSI1 supports:
  #   • Vehicle → Driver reverse lookup  (GSI1_PK = VEH#<Sticker>, GSI1_SK = DRIVER)
  #   • Owner   → Fleet lookup           (GSI1_PK = USR#<OwnerId>, GSI1_SK = VEH#<Sticker>)
  global_secondary_index {
    name            = "GSI1"
    hash_key        = "GSI1_PK"
    range_key       = "GSI1_SK"
    projection_type = "ALL"
  }

  # ── Durability: Point-in-Time Recovery ──────────────────────────────────
  point_in_time_recovery {
    enabled = true
  }

  # ── Security: AWS-Managed Server-Side Encryption ─────────────────────────
  server_side_encryption {
    enabled = true
  }

  # ── DynamoDB Streams (required for stream ARN output) ───────────────────
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
}

# ---------------------------------------------------------------------------
# kwella Cognito Identity Infrastructure
# ---------------------------------------------------------------------------

resource "aws_cognito_user_pool" "kwella_user_pool" {
  name = "kwella-user-pool-${var.environment}"

  username_attributes      = ["phone_number"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "mobile_app" {
  name         = "kwella-mobile-client-${var.environment}"
  user_pool_id = aws_cognito_user_pool.kwella_user_pool.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]
}

resource "aws_cognito_user_pool_client" "fleet_owner_dashboard" {
  name         = "kwella-fleet-web-client-${var.environment}"
  user_pool_id = aws_cognito_user_pool.kwella_user_pool.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_ADMIN_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}

# ---------------------------------------------------------------------------
# kwella Lambda Function Declarations
# ---------------------------------------------------------------------------
# These resources represent the deployed Lambda compute units. The `filename`
# attribute points to the deployment ZIP produced by the CI/CD pipeline.
# `source_code_hash` forces re-deployment whenever the package changes.
# ---------------------------------------------------------------------------

resource "aws_lambda_function" "auth_authorizer" {
  function_name    = "kwella-auth-authorizer-${var.environment}"
  description      = "Custom REQUEST Lambda authorizer: validates Cognito JWT and enforces DynamoDB suspension state."
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  role             = aws_iam_role.lambda_exec.arn
  filename         = "${path.module}/../../dist/auth_authorizer.zip"
  source_code_hash = filebase64sha256("${path.module}/../../dist/auth_authorizer.zip")

  layers = [aws_lambda_layer_version.kwella_shared.arn]

  environment {
    variables = {
      KWELLA_TABLE_NAME    = aws_dynamodb_table.kwella_core.name
      COGNITO_USER_POOL_ID = aws_cognito_user_pool.kwella_user_pool.id
    }
  }
}

resource "aws_lambda_function" "identity_service" {
  function_name    = "kwella-identity-service-${var.environment}"
  description      = "Identity Service: handles UPSERT_PROFILE and REGISTER_VEHICLE operations against the kwella core DynamoDB table."
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  role             = aws_iam_role.lambda_exec.arn
  filename         = "${path.module}/../../dist/identity_service.zip"
  source_code_hash = filebase64sha256("${path.module}/../../dist/identity_service.zip")

  layers = [aws_lambda_layer_version.kwella_shared.arn]

  environment {
    variables = {
      KWELLA_TABLE_NAME = aws_dynamodb_table.kwella_core.name
    }
  }
}

resource "aws_lambda_function" "ledger_service" {
  function_name    = "kwella-ledger-service-${var.environment}"
  description      = "Ledger Service: handles PROCESS_CANCELLATION and APPLY_TRIP_FEE operations."
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  role             = aws_iam_role.lambda_exec.arn
  filename         = "${path.module}/../../dist/ledger_service.zip"
  source_code_hash = filebase64sha256("${path.module}/../../dist/ledger_service.zip")

  layers = [aws_lambda_layer_version.kwella_shared.arn]

  environment {
    variables = {
      KWELLA_TABLE_NAME = aws_dynamodb_table.kwella_core.name
    }
  }
}

# ---------------------------------------------------------------------------
# kwella HTTP API Gateway — Edge Delivery Layer
# ---------------------------------------------------------------------------
# Protocol: HTTP (APIGatewayV2)
# Auth model: Custom REQUEST Lambda authorizer backed by Cognito JWT validation
# Routes: POST /identity/upsert, POST /identity/vehicle → Identity Service Lambda
# ---------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "kwella_http_api" {
  name          = "kwella-http-api-${var.environment}"
  protocol_type = "HTTP"
  description   = "kwella edge HTTP delivery gateway for identity and bidding service operations."
}

resource "aws_apigatewayv2_stage" "production" {
  api_id      = aws_apigatewayv2_api.kwella_http_api.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    detailed_metrics_enabled = true
    throttling_burst_limit   = 500
    throttling_rate_limit    = 1000
  }
}

# ── Custom Lambda REQUEST Authorizer ────────────────────────────────────────
# Validates Cognito-vended JWT bearer tokens and enforces the DynamoDB
# suspension check before allowing edge execution of any protected route.

resource "aws_apigatewayv2_authorizer" "kwella_lambda_authorizer" {
  api_id                            = aws_apigatewayv2_api.kwella_http_api.id
  authorizer_type                   = "REQUEST"
  name                              = "kwella-lambda-authorizer-${var.environment}"
  authorizer_uri                    = aws_lambda_function.auth_authorizer.invoke_arn
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true

  # Cache authorizer results for 300 seconds to reduce cold-path Lambda
  # invocations on high-frequency identity routes.
  authorizer_result_ttl_in_seconds = 300

  identity_sources = ["$request.header.Authorization"]
}

# Grant API Gateway permission to invoke the authorizer Lambda.
resource "aws_lambda_permission" "apigw_invoke_authorizer" {
  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth_authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.kwella_http_api.execution_arn}/*/*"
}

# ── Identity Service Lambda Integration ─────────────────────────────────────

resource "aws_apigatewayv2_integration" "identity_service" {
  api_id                 = aws_apigatewayv2_api.kwella_http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.identity_service.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# Grant API Gateway permission to invoke the Identity Service Lambda.
resource "aws_lambda_permission" "apigw_invoke_identity_service" {
  statement_id  = "AllowAPIGatewayInvokeIdentityService"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.identity_service.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.kwella_http_api.execution_arn}/*/*"
}

# ── Identity Routes — Protected by Custom Lambda Authorizer ─────────────────

resource "aws_apigatewayv2_route" "identity_upsert" {
  api_id             = aws_apigatewayv2_api.kwella_http_api.id
  route_key          = "POST /identity/upsert"
  target             = "integrations/${aws_apigatewayv2_integration.identity_service.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.kwella_lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "identity_vehicle" {
  api_id             = aws_apigatewayv2_api.kwella_http_api.id
  route_key          = "POST /identity/vehicle"
  target             = "integrations/${aws_apigatewayv2_integration.identity_service.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.kwella_lambda_authorizer.id
}

# ── Ledger Service Lambda Integration ───────────────────────────────────────

resource "aws_apigatewayv2_integration" "ledger_service" {
  api_id                 = aws_apigatewayv2_api.kwella_http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.ledger_service.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# Grant API Gateway permission to invoke the Ledger Service Lambda.
resource "aws_lambda_permission" "apigw_invoke_ledger_service" {
  statement_id  = "AllowAPIGatewayInvokeLedgerService"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ledger_service.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.kwella_http_api.execution_arn}/*/*"
}

# ── Ledger Routes — Protected by Custom Lambda Authorizer ───────────────────

resource "aws_apigatewayv2_route" "ledger_cancellation" {
  api_id             = aws_apigatewayv2_api.kwella_http_api.id
  route_key          = "POST /ledger/cancellation"
  target             = "integrations/${aws_apigatewayv2_integration.ledger_service.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.kwella_lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "ledger_trip_fee" {
  api_id             = aws_apigatewayv2_api.kwella_http_api.id
  route_key          = "POST /ledger/trip-fee"
  target             = "integrations/${aws_apigatewayv2_integration.ledger_service.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.kwella_lambda_authorizer.id
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "dynamodb_table_name" {
  description = "The name of the kwella core DynamoDB table."
  value       = aws_dynamodb_table.kwella_core.name
}

output "dynamodb_table_stream_arn" {
  description = "The ARN of the DynamoDB Streams stream on the kwella core table."
  value       = aws_dynamodb_table.kwella_core.stream_arn
}

output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool."
  value       = aws_cognito_user_pool.kwella_user_pool.id
}

output "cognito_app_client_id_mobile" {
  description = "The Client ID for the Flutter Mobile App client."
  value       = aws_cognito_user_pool_client.mobile_app.id
}

output "http_api_endpoint" {
  description = "The invoke URL for the kwella HTTP API Gateway ($default stage)."
  value       = aws_apigatewayv2_stage.production.invoke_url
}
