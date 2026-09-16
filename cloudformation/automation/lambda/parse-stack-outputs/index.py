def handler(event, _context):
    outputs = event.get("outputs", [])
    parsed = {item["OutputKey"]: item["OutputValue"] for item in outputs}
    required = {
        "DbSubnetGroupName",
        "DbSecurityGroupId",
        "LoadBalancerDnsName",
        "LoadBalancerCanonicalHostedZoneId",
        "AuthTargetGroupArn",
        "ProductTargetGroupArn",
        "OrderTargetGroupArn",
        "EcsClusterName",
        "AuthServiceName",
        "ProductServiceName",
        "OrderServiceName",
        "RuntimeSecretArn",
        "ProductionDesiredCount",
    }
    missing = sorted(required - parsed.keys())
    if missing:
        raise RuntimeError(f"DR stack is missing outputs: {', '.join(missing)}")
    parsed["ProductionDesiredCount"] = int(parsed["ProductionDesiredCount"])
    return parsed
