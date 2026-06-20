"""
kwella — pytest shared fixtures & path bootstrapping
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Configures the sys.path so that:

  1. The shared Lambda layer (kwella_shared) is importable as
     ``database.client`` and ``models.schemas`` — mirroring the runtime
     path structure that AWS Lambda resolves from the Layer ARN.

  2. The Lambda handler modules (identity_service, bidding_engine) are
     importable without installing them as packages.

This conftest.py is auto-loaded by pytest for every test module inside
``tests/`` and must remain free of test logic.

Governance compliance:
  - No hardcoded AWS secrets; moto intercepts all boto3 calls before
    they reach any live endpoint.
  - Python 3.12 native type hints throughout.
  - All path manipulation is scoped to the test session only.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Path constants
# ---------------------------------------------------------------------------

_REPO_ROOT: Path = Path(__file__).resolve().parent.parent.parent          # kwella/
_BACKEND: Path = _REPO_ROOT / "kwella-backend"
_LAYER_PYTHON: Path = _BACKEND / "src" / "layers" / "kwella_shared" / "python"
_LAMBDAS: Path = _BACKEND / "src" / "lambdas"

# ---------------------------------------------------------------------------
# Inject Layer and Lambda source directories into sys.path
# ---------------------------------------------------------------------------
# The order matters: the shared layer must appear BEFORE the lambda directories
# so that ``from database.client import get_table`` resolves to the layer copy
# in all test contexts.

for _path in (_LAYER_PYTHON, _LAMBDAS):
    _path_str = str(_path)
    if _path_str not in sys.path:
        sys.path.insert(0, _path_str)

# ---------------------------------------------------------------------------
# Default environment variables for moto-intercepted boto3 calls
# ---------------------------------------------------------------------------
# These are picked up by database.client at *import time*, so they must be
# set before any handler module is imported.  moto does not validate region
# or table-name formats, so these are safe placeholder values.

os.environ.setdefault("KWELLA_TABLE_NAME", "kwella-core-test")
os.environ.setdefault("AWS_REGION", "af-south-1")

# moto requires fake credentials to be present in the environment; it never
# contacts real AWS endpoints but boto3 will raise NoCredentialsError without
# at least a dummy value present.
os.environ.setdefault("AWS_ACCESS_KEY_ID", "testing")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "testing")
os.environ.setdefault("AWS_SECURITY_TOKEN", "testing")
os.environ.setdefault("AWS_SESSION_TOKEN", "testing")
os.environ.setdefault("AWS_DEFAULT_REGION", "af-south-1")
