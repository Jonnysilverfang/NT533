import boto3


backup = boto3.client("backup")


def handler(event, _context):
    vault_name = event["backup_vault_name"]
    source_resource_arn = event["source_resource_arn"]
    candidates = []
    paginator = backup.get_paginator("list_recovery_points_by_backup_vault")
    # Query all completed RDS recovery points in the DR vault
    for page in paginator.paginate(
        BackupVaultName=vault_name,
        ByResourceType="RDS",
    ):
        for point in page.get("RecoveryPoints", []):
            if point.get("Status") != "COMPLETED" or not point.get("RecoveryPointArn"):
                continue
            res_arn = point.get("ResourceArn", "")
            # Match exact ARN or match resource identifier (e.g. prod-dr-primary-db)
            if not source_resource_arn or res_arn == source_resource_arn or (
                source_resource_arn.split(":")[-1] == res_arn.split(":")[-1]
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
