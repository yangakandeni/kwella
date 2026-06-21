# ---------------------------------------------------------------------------
# kwella Shared Lambda Layer
# ---------------------------------------------------------------------------
# This layer packages all Python dependencies shared across Lambda functions:
#   • pydantic v2      — runtime schema validation and serialisation
#   • boto3 / botocore — AWS SDK (connection-pooled, governs cold-start cost)
#
# Build contract:
#   The CI/CD pipeline produces the zip at '../build/kwella_shared_layer.zip'
#   relative to this module root before 'terraform apply' is invoked.
#   The path resolves to: <repo-root>/kwella-backend/build/kwella_shared_layer.zip
#
# Layer directory structure expected inside the zip (per AWS convention):
#   python/
#   └── <installed packages>
# ---------------------------------------------------------------------------

resource "aws_lambda_layer_version" "kwella_shared" {
  layer_name          = "${var.project_name}-shared-${var.environment}"
  description         = "Shared Python 3.12 runtime dependencies (pydantic v2, boto3) for all kwella Lambda functions."
  compatible_runtimes = ["python3.12"]

  # Points to the build artifact produced by the CI/CD pipeline.
  # This placeholder path satisfies Terraform schema validation; the file is
  # materialised by the 'build-layer' step in .github/workflows/ci-cd.yml
  # before any infrastructure apply is executed.
  filename         = "${path.module}/../build/kwella_shared_layer.zip"
  source_code_hash = filebase64sha256("${path.module}/../build/kwella_shared_layer.zip")
}
