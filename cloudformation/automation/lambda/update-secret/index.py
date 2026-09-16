import json

import boto3


rds = boto3.client("rds")
secrets = boto3.client("secretsmanager")


def handler(event, _context):
    instances = rds.describe_db_instances(
        DBInstanceIdentifier=event["db_instance_identifier"]
    )["DBInstances"]
    if len(instances) != 1 or instances[0]["DBInstanceStatus"] != "available":
        raise RuntimeError("Restored DB instance is not available")

    source = secrets.get_secret_value(SecretId=event["source_secret_id"])
    credentials = json.loads(source["SecretString"])
    db = instances[0]
    runtime = {
        "username": credentials["username"],
        "password": credentials["password"],
        "host": db["Endpoint"]["Address"],
        "port": db["Endpoint"]["Port"],
        "dbname": event.get("database_name", "appdb"),
    }
    secrets.put_secret_value(
        SecretId=event["runtime_secret_arn"], SecretString=json.dumps(runtime)
    )
    return {"endpoint": runtime["host"], "port": runtime["port"]}
