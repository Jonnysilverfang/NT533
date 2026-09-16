import os
import time

import boto3
from botocore.exceptions import ClientError


table = boto3.resource("dynamodb").Table(os.environ["LOCK_TABLE_NAME"])
LOCK_NAME = "production-dr-orchestrator"


def handler(event, _context):
    action = event["action"]
    owner = event["owner"]

    if action == "acquire":
        now = int(time.time())
        expires_at = now + int(event.get("ttl_seconds", 86400))
        try:
            table.put_item(
                Item={
                    "lock_name": LOCK_NAME,
                    "owner": owner,
                    "acquired_at": now,
                    "expires_at": expires_at,
                },
                ConditionExpression=(
                    "attribute_not_exists(lock_name) OR expires_at < :now OR #owner = :owner"
                ),
                ExpressionAttributeNames={"#owner": "owner"},
                ExpressionAttributeValues={":now": now, ":owner": owner},
            )
            return {"acquired": True, "owner": owner, "expires_at": expires_at}
        except ClientError as error:
            if error.response["Error"]["Code"] != "ConditionalCheckFailedException":
                raise
            current = table.get_item(
                Key={"lock_name": LOCK_NAME}, ConsistentRead=True
            ).get("Item", {})
            return {
                "acquired": False,
                "owner": current.get("owner", "unknown"),
                "expires_at": int(current.get("expires_at", 0)),
            }

    if action == "release":
        try:
            table.delete_item(
                Key={"lock_name": LOCK_NAME},
                ConditionExpression="#owner = :owner",
                ExpressionAttributeNames={"#owner": "owner"},
                ExpressionAttributeValues={":owner": owner},
            )
            return {"released": True}
        except ClientError as error:
            if error.response["Error"]["Code"] != "ConditionalCheckFailedException":
                raise
            return {"released": False, "reason": "owner-mismatch-or-expired"}

    raise ValueError("action must be acquire or release")
