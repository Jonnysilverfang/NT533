import boto3


elbv2 = boto3.client("elbv2")


def handler(event, _context):
    expected = int(event.get("expected_healthy_per_group", 1))
    results = {}
    all_healthy = True
    for target_group_arn in event["target_group_arns"]:
        descriptions = elbv2.describe_target_health(
            TargetGroupArn=target_group_arn
        ).get("TargetHealthDescriptions", [])
        healthy = sum(
            1
            for description in descriptions
            if description.get("TargetHealth", {}).get("State") == "healthy"
        )
        results[target_group_arn] = healthy
        all_healthy = all_healthy and healthy >= expected

    return {"all_healthy": all_healthy, "healthy_counts": results}
