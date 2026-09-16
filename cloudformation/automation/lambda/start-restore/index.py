import hashlib
import json
import uuid

import boto3


backup = boto3.client("backup")
rds = boto3.client("rds")


def handler(event, _context):
    recovery_point_arn = event["recovery_point_arn"]
    db_identifier = event["db_instance_identifier"]
    try:
        existing = rds.describe_db_instances(DBInstanceIdentifier=db_identifier)[
            "DBInstances"
        ][0]
    except rds.exceptions.DBInstanceNotFoundFault:
        existing = None
    if existing:
        if existing["DBInstanceStatus"] == "available":
            jobs = backup.list_restore_jobs(ByResourceType="RDS").get("RestoreJobs", [])
            for j in jobs:
                if (
                    j.get("CreatedResourceArn") == existing.get("DBInstanceArn")
                    and j.get("Status") == "COMPLETED"
                ):
                    return {"restore_job_id": j["RestoreJobId"]}
        raise RuntimeError(
            f"DR database {db_identifier} already exists with status "
            f"{existing['DBInstanceStatus']}; run guarded cleanup before a new restore"
        )

    metadata = backup.get_recovery_point_restore_metadata(
        BackupVaultName=event["backup_vault_name"],
        RecoveryPointArn=recovery_point_arn,
    )["RestoreMetadata"]

    for key in [
        "DBSnapshotIdentifier",
        "AvailabilityZone",
        "DBParameterGroupName",
        "DBName",
        "aws:backup:request-id",
    ]:
        metadata.pop(key, None)

    for key in list(metadata.keys()):
        if key.startswith("InformationalOnly:"):
            metadata.pop(key, None)

    if metadata.get("Port") == "0" or not metadata.get("Port"):
        metadata["Port"] = "5432"

    metadata.update(
        {
            "DBInstanceIdentifier": db_identifier,
            "DBInstanceClass": event["db_instance_class"],
            "DBSubnetGroupName": event["db_subnet_group_name"],
            "VpcSecurityGroupIds": json.dumps([event["db_security_group_id"]]),
            "MultiAZ": "false",
            "PubliclyAccessible": "false",
            "DeletionProtection": "false" if event.get("test_mode", False) else "true",
            "CopyTagsToSnapshot": "true",
        }
    )

    token = uuid.uuid4().hex[:32]
    response = backup.start_restore_job(
        RecoveryPointArn=recovery_point_arn,
        IamRoleArn=event["restore_role_arn"],
        Metadata=metadata,
        IdempotencyToken=token,
        ResourceType="RDS",
        CopySourceTagsToRestoredResource=True,
    )
    return {"restore_job_id": response["RestoreJobId"]}
