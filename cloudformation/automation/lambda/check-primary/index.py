import boto3


def handler(event, _context):
    if event.get("simulate_failure", False) or event.get("test_mode", False):
        return {
            "still_failed": True,
            "alarm_state": "SIMULATED",
            "reason": "simulation explicitly requested",
        }

    region = event["primary_region"]
    alarm_name = event["alarm_name"]
    response = boto3.client("cloudwatch", region_name=region).describe_alarms(
        AlarmNames=[alarm_name],
        AlarmTypes=["CompositeAlarm", "MetricAlarm"],
    )
    alarms = response.get("MetricAlarms", []) + response.get("CompositeAlarms", [])
    if len(alarms) != 1:
        raise RuntimeError(f"Expected one alarm named {alarm_name}, found {len(alarms)}")

    state = alarms[0]["StateValue"]
    return {"still_failed": state == "ALARM", "alarm_state": state}
