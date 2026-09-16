import hashlib
import json

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
        raise RuntimeError(
            f"DR database {db_identifier} already exists with status "
            f"{existing['DBInstanceStatus']}; run guarded cleanup before a new restore"
        )

    metadata = backup.get_recovery_point_restore_metadata(
        BackupVaultName=event["backup_vault_name"],
        RecoveryPointArn=recovery_point_arn,
    )["RestoreMetadata"]

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

    token_source = f"{recovery_point_arn}|{db_identifier}"
    token = hashlib.sha256(token_source.encode("utf-8")).hexdigest()[:48]
    response = backup.start_restore_job(
        RecoveryPointArn=recovery_point_arn,
        IamRoleArn=event["restore_role_arn"],
        Metadata=metadata,
        IdempotencyToken=token,
        ResourceType="RDS",
        CopySourceTagsToRestoredResource=True,
    )
    return {"restore_job_id": response["RestoreJobId"]}
