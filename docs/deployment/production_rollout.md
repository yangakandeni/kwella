# kwella Backend — Production Rollout Checklist

> **Phase 9 · Step 5 · Platform Infrastructure Production Sign-off**
> Region: `af-south-1` · Environment: `production` · Terraform ≥ 1.6.0 · AWS Provider `~> 5.0`

---

## Pre-flight Requirements

Before executing any step below, confirm every prerequisite is satisfied. Any
unchecked item **blocks** the rollout.

| # | Prerequisite | Check |
|---|---|---|
| 1 | AWS credentials exported (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` if role-based) | `[ ]` |
| 2 | Terraform ≥ 1.6.0 installed locally (`terraform version`) | `[ ]` |
| 3 | CI/CD pipeline green on `main` (pytest suite + `terraform validate` gate both passed) | `[ ]` |
| 4 | All four Lambda deployment ZIPs present in `kwella-backend/dist/`: `auth_authorizer.zip`, `identity_service.zip`, `ledger_service.zip`, `bidding_engine.zip` | `[ ]` |
| 5 | No un-committed changes in the working tree (`git status` clean) | `[ ]` |
| 6 | Peer sign-off obtained on the latest `dry_run_manifest.md` | `[ ]` |

---

## Phase 1 — Stack Initialization

All commands are executed from the Terraform root:

```bash
cd kwella-backend/terraform
```

### Step 1 · `terraform init`

Initialises the backend, downloads the AWS provider (`~> 5.0`), and writes the
provider lock file.

```bash
terraform init
```

**Expected output (key lines):**

```
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installed hashicorp/aws v5.x.x (signed by HashiCorp)

Terraform has been successfully initialized!
```

**Abort condition:** Any `Error:` line in the output. Do not proceed until the
provider is installed cleanly.

---

### Step 2 · `terraform plan` — Structural Review

Generate a full execution plan and **review it before applying anything.**

```bash
terraform plan -out=kwella_production.tfplan
```

**What to verify in the plan diff:**

| Resource type | Expected action | Key attribute to confirm |
|---|---|---|
| `aws_dynamodb_table.kwella_core` | `create` | `billing_mode = PAY_PER_REQUEST`, PITR enabled, SSE enabled |
| `aws_cognito_user_pool.kwella_user_pool` | `create` | `username_attributes = ["phone_number"]` |
| `aws_cognito_user_pool_client.mobile_app` | `create` | `generate_secret = false` |
| `aws_cognito_user_pool_client.fleet_owner_dashboard` | `create` | `ALLOW_ADMIN_USER_PASSWORD_AUTH` flow present |
| `aws_iam_role.lambda_exec` | `create` | Shared execution role |
| `aws_lambda_layer_version.kwella_shared` | `create` | `compatible_runtimes = ["python3.12"]` |
| `aws_lambda_function.auth_authorizer` | `create` | `runtime = python3.12`, env vars `KWELLA_TABLE_NAME` + `COGNITO_USER_POOL_ID` |
| `aws_lambda_function.identity_service` | `create` | `runtime = python3.12`, env var `KWELLA_TABLE_NAME` |
| `aws_lambda_function.ledger_service` | `create` | `runtime = python3.12`, env var `KWELLA_TABLE_NAME` |
| `aws_apigatewayv2_api.kwella_http_api` | `create` | `protocol_type = HTTP` |
| `aws_apigatewayv2_stage.production` | `create` | `name = $default`, `auto_deploy = true` |
| `aws_apigatewayv2_authorizer.kwella_lambda_authorizer` | `create` | `authorizer_type = REQUEST`, TTL 300 s, `identity_sources = ["$request.header.Authorization"]` |
| `aws_apigatewayv2_route.identity_upsert` | `create` | `route_key = POST /identity/upsert`, `authorization_type = CUSTOM` |
| `aws_apigatewayv2_route.identity_vehicle` | `create` | `route_key = POST /identity/vehicle`, `authorization_type = CUSTOM` |
| `aws_apigatewayv2_route.ledger_cancellation` | `create` | `route_key = POST /ledger/cancellation`, `authorization_type = CUSTOM` |
| `aws_apigatewayv2_route.ledger_trip_fee` | `create` | `route_key = POST /ledger/trip-fee`, `authorization_type = CUSTOM` |

**Abort condition:** Any `destroy` or unexpected `update-in-place` actions on
pre-existing shared resources. Escalate before applying.

---

### Step 3 · `terraform apply` — Targeted Resource Loop

Apply the saved plan in a controlled, layered sequence to isolate failures by
dependency tier.

#### Tier A — Data & Identity Foundation

```bash
# DynamoDB single-table
terraform apply -target=aws_dynamodb_table.kwella_core kwella_production.tfplan

# Cognito User Pool + app clients
terraform apply \
  -target=aws_cognito_user_pool.kwella_user_pool \
  -target=aws_cognito_user_pool_client.mobile_app \
  -target=aws_cognito_user_pool_client.fleet_owner_dashboard \
  kwella_production.tfplan
```

**Gate:** Both resource groups must report `Apply complete! Resources: N added,
0 changed, 0 destroyed.` before advancing.

#### Tier B — IAM & Lambda Layer

```bash
terraform apply \
  -target=aws_iam_role.lambda_exec \
  -target=aws_iam_role_policy_attachment.lambda_basic_execution \
  -target=aws_iam_role_policy.dynamodb_access \
  -target=aws_lambda_layer_version.kwella_shared \
  kwella_production.tfplan
```

#### Tier C — Lambda Compute Functions

```bash
terraform apply \
  -target=aws_lambda_function.auth_authorizer \
  -target=aws_lambda_function.identity_service \
  -target=aws_lambda_function.ledger_service \
  kwella_production.tfplan
```

#### Tier D — API Gateway Edge Layer (final)

```bash
terraform apply \
  -target=aws_apigatewayv2_api.kwella_http_api \
  -target=aws_apigatewayv2_stage.production \
  -target=aws_apigatewayv2_authorizer.kwella_lambda_authorizer \
  -target=aws_lambda_permission.apigw_invoke_authorizer \
  -target=aws_apigatewayv2_integration.identity_service \
  -target=aws_lambda_permission.apigw_invoke_identity_service \
  -target=aws_apigatewayv2_route.identity_upsert \
  -target=aws_apigatewayv2_route.identity_vehicle \
  -target=aws_apigatewayv2_integration.ledger_service \
  -target=aws_lambda_permission.apigw_invoke_ledger_service \
  -target=aws_apigatewayv2_route.ledger_cancellation \
  -target=aws_apigatewayv2_route.ledger_trip_fee \
  kwella_production.tfplan
```

#### Full Remaining Apply (sweep-up)

After all targeted tiers succeed, apply any remaining planned changes:

```bash
terraform apply kwella_production.tfplan
```

---

### Step 4 · Capture Terraform Outputs

Record the live infrastructure identifiers for the smoke-test phase.

```bash
terraform output -json | tee ../../docs/deployment/terraform_outputs_production.json
```

Expected keys:

| Output key | Description |
|---|---|
| `dynamodb_table_name` | e.g. `kwella-core-production` |
| `dynamodb_table_stream_arn` | Full DynamoDB Streams ARN |
| `cognito_user_pool_id` | e.g. `af-south-1_XXXXXXXXX` |
| `cognito_app_client_id_mobile` | Flutter mobile client ID |
| `http_api_endpoint` | Live invoke URL for all smoke tests |

---

## Phase 2 — Live Verification Smoke Tests

Replace `<API_ENDPOINT>` with the `http_api_endpoint` value from Step 4.

### Smoke Test 1 · Edge Authorizer — Unauthenticated Rejection (Critical)

**Purpose:** Confirm the custom Lambda authorizer is wired correctly and denies
all requests that carry no valid bearer token.

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -X POST "<API_ENDPOINT>/identity/upsert" \
  -H "Content-Type: application/json" \
  -d '{"action":"UPSERT_PROFILE","role":"RIDER","user_id":"smoke-test-001"}'
```

**Expected:** `401`

A `401 Unauthorized` response proves:
1. The `$default` stage is live and routing correctly.
2. The `aws_apigatewayv2_authorizer` is attached to the route.
3. The `Authorization` header is absent → authorizer denies → clean `401`.

**Failure condition:** Any response other than `401` (e.g. `200`, `403`, `500`)
indicates a misconfigured authorizer or broken Lambda permission. **Do not
proceed to authenticated tests. Roll back.**

---

### Smoke Test 2 · Edge Authorizer — Unauthenticated Rejection on Vehicle Route

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -X POST "<API_ENDPOINT>/identity/vehicle" \
  -H "Content-Type: application/json" \
  -d '{}'
```

**Expected:** `401`

---

### Smoke Test 3 · Edge Authorizer — Ledger Routes Protected

```bash
# POST /ledger/cancellation
curl -s -o /dev/null -w "%{http_code}" \
  -X POST "<API_ENDPOINT>/ledger/cancellation"
# Expected: 401

# POST /ledger/trip-fee
curl -s -o /dev/null -w "%{http_code}" \
  -X POST "<API_ENDPOINT>/ledger/trip-fee"
# Expected: 401
```

---

### Smoke Test 4 · DynamoDB Table Existence Confirmation

```bash
aws dynamodb describe-table \
  --table-name "$(terraform output -raw dynamodb_table_name)" \
  --region af-south-1 \
  --query "Table.TableStatus" \
  --output text
```

**Expected:** `ACTIVE`

---

### Smoke Test 5 · Lambda Function State Check

```bash
for fn in kwella-auth-authorizer-production \
           kwella-identity-service-production \
           kwella-ledger-service-production; do
  echo -n "$fn → "
  aws lambda get-function \
    --function-name "$fn" \
    --region af-south-1 \
    --query "Configuration.State" \
    --output text
done
```

**Expected:** All three return `Active`.

---

### Smoke Test Gate

| Test | Route / Resource | Expected | Pass |
|---|---|---|---|
| ST-1 | `POST /identity/upsert` (no auth) | `401` | `[ ]` |
| ST-2 | `POST /identity/vehicle` (no auth) | `401` | `[ ]` |
| ST-3a | `POST /ledger/cancellation` (no auth) | `401` | `[ ]` |
| ST-3b | `POST /ledger/trip-fee` (no auth) | `401` | `[ ]` |
| ST-4 | DynamoDB table status | `ACTIVE` | `[ ]` |
| ST-5 | Lambda function states (×3) | `Active` | `[ ]` |

All six must be checked before declaring the rollout **successful**.

---

## Phase 3 — Rollback Procedures

Rollback is **targeted** wherever possible to minimize blast radius. Execute only
the tier that corresponds to the defect location identified in post-apply
verification.

### Rollback Level 1 — API Gateway Stage Only

Use when: smoke tests fail at the routing or authorizer layer but underlying
Lambda and DynamoDB resources are healthy.

```bash
# Tear down only the $default stage, leaving all integrations and routes intact.
# The stage will be re-created on the next terraform apply.
terraform destroy \
  -target=aws_apigatewayv2_stage.production \
  -auto-approve
```

Investigate CloudWatch Logs for `kwella-auth-authorizer-production` before
re-applying.

---

### Rollback Level 2 — Full API Gateway Edge Layer

Use when: the API Gateway API itself is structurally misconfigured (e.g. wrong
`protocol_type`, broken invoke URL).

```bash
terraform destroy \
  -target=aws_apigatewayv2_route.ledger_trip_fee \
  -target=aws_apigatewayv2_route.ledger_cancellation \
  -target=aws_apigatewayv2_route.identity_vehicle \
  -target=aws_apigatewayv2_route.identity_upsert \
  -target=aws_lambda_permission.apigw_invoke_ledger_service \
  -target=aws_lambda_permission.apigw_invoke_identity_service \
  -target=aws_lambda_permission.apigw_invoke_authorizer \
  -target=aws_apigatewayv2_integration.ledger_service \
  -target=aws_apigatewayv2_integration.identity_service \
  -target=aws_apigatewayv2_authorizer.kwella_lambda_authorizer \
  -target=aws_apigatewayv2_stage.production \
  -target=aws_apigatewayv2_api.kwella_http_api \
  -auto-approve
```

**Note:** Lambda functions, IAM, the shared layer, DynamoDB, and Cognito remain
untouched at this level.

---

### Rollback Level 3 — Lambda Compute Functions

Use when: a Lambda function deployment ZIP was corrupt or the handler entrypoint
is broken (confirmed via CloudWatch Logs).

```bash
# Example: roll back a single Lambda (identity service)
terraform destroy \
  -target=aws_lambda_function.identity_service \
  -auto-approve

# Re-deploy the corrected ZIP, then re-apply:
# 1. Fix and repackage: ci/build_lambda.sh identity_service
# 2. terraform apply -target=aws_lambda_function.identity_service
```

---

### Rollback Level 4 — Full Stack Destroy (Last Resort)

Use only when a structural defect is unrecoverable without a clean slate (e.g.
naming collision, irreconcilable state drift).

> ⚠️ **This is destructive and irreversible for stateful resources (DynamoDB
> PITR snapshots, Cognito user records). Obtain two-person approval before
> executing.**

```bash
terraform destroy -auto-approve
```

After a full destroy, the stack must be re-initialized from Step 1 of Phase 1.

---

### Post-Rollback State Recovery

After any rollback, perform the following before re-applying:

```bash
# 1. Refresh Terraform state to reconcile with AWS reality
terraform refresh

# 2. Generate a new plan to confirm the diff is correct
terraform plan -out=kwella_recovery.tfplan

# 3. Peer-review the recovery plan diff before applying
```

---

## Appendix A — Version Control & Cache Integrity

### `.gitignore` Audit Results (Phase 9 · Step 5)

All local test and tool cache directories produced by the pytest/moto suite, type
checker, and linter are confirmed covered by the root `.gitignore`. No cache
artefact can accidentally enter version control.

| Local directory | `.gitignore` rule | Line | Status |
|---|---|---|---|
| `kwella-backend/.pytest_cache/` | `.pytest_cache/` | 51 | ✅ Ignored |
| `kwella-backend/.mypy_cache/` | `.mypy_cache/` | 46 | ✅ Ignored |
| `kwella-backend/.ruff_cache/` | `.ruff_cache/` | 47 | ✅ Ignored |
| `kwella-backend/build/` | `build/` | 66 | ✅ Ignored |
| `kwella-backend/dist/` | `dist/` | 41 | ✅ Ignored |
| `.pytest_cache/` (root) | `.pytest_cache/` | 51 | ✅ Ignored |
| `.venv/` (root) | `.venv/` | 37 | ✅ Ignored |
| `dist/` (root) | `dist/` | 41 | ✅ Ignored |
| `kwella-backend/src/lambdas/*/__pycache__/` | `__pycache__/` | 33 | ✅ Ignored |
| `kwella-backend/tests/__pycache__/` | `__pycache__/` | 33 | ✅ Ignored |

**Result: 10/10 local cache paths are correctly mapped to `.gitignore` rules.
Version control is clean.**

---

## Appendix B — Infrastructure Resource Map

```
AWS Account (af-south-1 / production)
│
├── DynamoDB
│   └── kwella-core-production          (PAY_PER_REQUEST · PITR · SSE · Streams)
│       └── GSI1                        (GSI1_PK / GSI1_SK · ALL projection)
│
├── Cognito
│   └── kwella-user-pool-production
│       ├── kwella-mobile-client-production       (no secret · SRP + refresh)
│       └── kwella-fleet-web-client-production    (no secret · admin + SRP + refresh)
│
├── IAM
│   └── kwella-lambda-exec-production   (CloudWatch Logs + scoped DynamoDB)
│
├── Lambda Layer
│   └── kwella_shared                   (python3.12 · shared models + DB client)
│
├── Lambda Functions
│   ├── kwella-auth-authorizer-production
│   ├── kwella-identity-service-production
│   └── kwella-ledger-service-production
│
└── API Gateway (HTTP · APIGatewayV2)
    └── kwella-http-api-production
        ├── Stage: $default             (auto_deploy · burst 500 · rate 1000)
        ├── Authorizer: kwella-lambda-authorizer-production  (REQUEST · TTL 300s)
        ├── POST /identity/upsert       → identity_service  [CUSTOM auth]
        ├── POST /identity/vehicle      → identity_service  [CUSTOM auth]
        ├── POST /ledger/cancellation   → ledger_service    [CUSTOM auth]
        └── POST /ledger/trip-fee       → ledger_service    [CUSTOM auth]
```

---

*Document generated: Phase 9 · Step 5 · kwella Platform Infrastructure Production Sign-off*
