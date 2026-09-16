import hashlib
import json

import boto3


backup = boto3.client("backup")


def handler(event, _context):
    recovery_point_arn = event["recovery_point_arn"]
    metadata = backup.get_recovery_point_restore_metadata(
        BackupVaultName=event["backup_vault_name"],
        RecoveryPointArn=recovery_point_arn,
    )["RestoreMetadata"]

    metadata.update(
        {
            "DBInstanceIdentifier": event["db_instance_identifier"],
            "DBInstanceClass": event["db_instance_class"],
            "DBSubnetGroupName": event["db_subnet_group_name"],
            "VpcSecurityGroupIds": json.dumps([event["db_security_group_id"]]),
            "MultiAZ": "false",
            "PubliclyAccessible": "false",
            "DeletionProtection": "true",
            "CopyTagsToSnapshot": "true",
        }
    )

    token_source = f"{recovery_point_arn}|{event['db_instance_identifier']}"
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
