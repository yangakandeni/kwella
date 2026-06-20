"""
kwella_shared.database.client
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Provides a module-scoped, connection-pooled DynamoDB resource client and a
thread-safe helper to retrieve the table reference.

Governance compliance:
  - boto3 resource is initialised at module level (outside any function scope)
    to enable connection reuse across Lambda warm invocations.
  - All DynamoDB operations must catch botocore.exceptions.ClientError at the
    call site; this module only exposes the resource — not raw responses.
  - KWELLA_TABLE_NAME is sourced exclusively from the process environment.
    No hardcoded names are permitted beyond the documented fallback default.
"""

from __future__ import annotations

import logging
import os

import boto3
import botocore.exceptions

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Module-level DynamoDB resource — initialised once per Lambda execution
# environment (warm context reuse). Do NOT move inside any function scope.
# ---------------------------------------------------------------------------
_TABLE_NAME: str = os.environ.get("KWELLA_TABLE_NAME", "kwella-core-production")

_dynamodb = boto3.resource(
    "dynamodb",
    region_name=os.environ.get("AWS_REGION", "af-south-1"),
)

_table = _dynamodb.Table(_TABLE_NAME)


def get_table():
    """Return the module-level DynamoDB Table resource reference.

    Returns the same Table object for every call within a single Lambda
    execution environment, enabling connection-pool reuse without any
    additional locking overhead (boto3 Table objects are thread-safe for
    read access and concurrent PutItem / UpdateItem operations).

    Returns:
        boto3.resources.factory.dynamodb.Table: The DynamoDB table resource.

    Example::

        from database.client import get_table

        table = get_table()
        try:
            response = table.get_item(Key={"PK": "USR#123", "SK": "PROFILE"})
        except botocore.exceptions.ClientError as exc:
            error_code = exc.response["Error"]["Code"]
            logger.error("DynamoDB ClientError [%s]: %s", error_code, exc)
            raise
    """
    return _table
