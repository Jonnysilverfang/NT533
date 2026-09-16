import boto3


backup = boto3.client("backup")


def handler(event, _context):
    vault_name = event["backup_vault_name"]
    source_resource_arn = event["source_resource_arn"]
    paginator = backup.get_paginator("list_recovery_points_by_backup_vault")
    candidates = []
    for page in paginator.paginate(
        BackupVaultName=vault_name,
        ByResourceType="RDS",
        ByResourceArn=source_resource_arn,
    ):
        for point in page.get("RecoveryPoints", []):
            if (
                point.get("Status") == "COMPLETED"
                and point.get("RecoveryPointArn")
                and point.get("ResourceArn") == source_resource_arn
            ):
                candidates.append(point)

    if not candidates:
        raise RuntimeError(
            f"No COMPLETED recovery point for {source_resource_arn} found in {vault_name}"
        )

    latest = max(candidates, key=lambda point: point["CreationDate"])
    return {
        "recovery_point_arn": latest["RecoveryPointArn"],
        "creation_date": latest["CreationDate"].isoformat(),
        "resource_arn": latest.get("ResourceArn", ""),
    }
