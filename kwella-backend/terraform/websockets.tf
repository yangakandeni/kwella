# ---------------------------------------------------------------------------
# kwella Bidding Engine WebSocket API Infrastructure
# ---------------------------------------------------------------------------

# ── Bidding Engine Lambda Function ──────────────────────────────────────────
resource "aws_lambda_function" "bidding_engine" {
  function_name    = "kwella-bidding-engine-${var.environment}"
  description      = "Bidding Engine: handles real-time WebSocket bidding plane routing."
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  role             = aws_iam_role.lambda_exec.arn
  filename         = "${path.module}/../../dist/bidding_engine.zip"
  source_code_hash = filebase64sha256("${path.module}/../../dist/bidding_engine.zip")

  layers = [aws_lambda_layer_version.kwella_shared.arn]

  environment {
    variables = {
      KWELLA_TABLE_NAME     = aws_dynamodb_table.kwella_core.name
      # Management API endpoint used by requestTrip to post rideOfferAvailable
      # back to connected driver WebSocket sessions.
      KWELLA_APIGW_ENDPOINT = "https://${aws_apigatewayv2_api.kwella_websocket_api.id}.execute-api.${var.aws_region}.amazonaws.com/${var.environment}"
      KWELLA_AWS_REGION     = var.aws_region
    }
  }
}

# ── API Gateway v2 WebSocket API ───────────────────────────────────────────
resource "aws_apigatewayv2_api" "kwella_websocket_api" {
  name                       = "kwella-websocket-api-${var.environment}"
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"
}

# ── Stage ──────────────────────────────────────────────────────────────────
resource "aws_apigatewayv2_stage" "kwella_websocket_stage" {
  api_id      = aws_apigatewayv2_api.kwella_websocket_api.id
  name        = var.environment
  auto_deploy = true
}

# ── Integrations ───────────────────────────────────────────────────────────
resource "aws_apigatewayv2_integration" "bidding_engine" {
  api_id           = aws_apigatewayv2_api.kwella_websocket_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.bidding_engine.invoke_arn
}

# ── Routes ─────────────────────────────────────────────────────────────────
resource "aws_apigatewayv2_route" "connect" {
  api_id    = aws_apigatewayv2_api.kwella_websocket_api.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.bidding_engine.id}"
}

resource "aws_apigatewayv2_route" "disconnect" {
  api_id    = aws_apigatewayv2_api.kwella_websocket_api.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.bidding_engine.id}"
}

resource "aws_apigatewayv2_route" "send_bid" {
  api_id                              = aws_apigatewayv2_api.kwella_websocket_api.id
  route_key                           = "sendBid"
  target                              = "integrations/${aws_apigatewayv2_integration.bidding_engine.id}"
  route_response_selection_expression = "$default"
}

resource "aws_apigatewayv2_route_response" "send_bid" {
  api_id             = aws_apigatewayv2_api.kwella_websocket_api.id
  route_id           = aws_apigatewayv2_route.send_bid.id
  route_response_key = "$default"
}

resource "aws_apigatewayv2_route" "update_location" {
  api_id                              = aws_apigatewayv2_api.kwella_websocket_api.id
  route_key                           = "updateLocation"
  target                              = "integrations/${aws_apigatewayv2_integration.bidding_engine.id}"
  route_response_selection_expression = "$default"
}

resource "aws_apigatewayv2_route_response" "update_location" {
  api_id             = aws_apigatewayv2_api.kwella_websocket_api.id
  route_id           = aws_apigatewayv2_route.update_location.id
  route_response_key = "$default"
}

resource "aws_apigatewayv2_route" "request_trip" {
  api_id                              = aws_apigatewayv2_api.kwella_websocket_api.id
  route_key                           = "requestTrip"
  target                              = "integrations/${aws_apigatewayv2_integration.bidding_engine.id}"
  route_response_selection_expression = "$default"
}

resource "aws_apigatewayv2_route_response" "request_trip" {
  api_id             = aws_apigatewayv2_api.kwella_websocket_api.id
  route_id           = aws_apigatewayv2_route.request_trip.id
  route_response_key = "$default"
}

# ── Lambda Permissions ─────────────────────────────────────────────────────
resource "aws_lambda_permission" "apigw_invoke_websocket_bidding" {
  statement_id  = "AllowAPIGatewayInvokeWebsocketBidding"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bidding_engine.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.kwella_websocket_api.execution_arn}/*/*"
}

# ── Variables & Outputs ────────────────────────────────────────────────────
variable "websocket_connection_gsi" {
  description = "The DynamoDB Global Secondary Index name or table reference rule to query active WebSocket connection mappings (PK=CONN#<connection_id>)."
  type        = string
  default     = "GSI1"
}

output "websocket_api_endpoint" {
  description = "The invoke URL for the kwella WebSocket API Gateway."
  value       = "${aws_apigatewayv2_api.kwella_websocket_api.api_endpoint}/${aws_apigatewayv2_stage.kwella_websocket_stage.name}"
}
