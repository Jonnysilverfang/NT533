# DR run 08 - automated failover and DNS validation

- Detection: Primary health probe -> CloudWatch alarm -> Composite Alarm -> EventBridge cross-Region -> Step Functions.
- Execution: `SUCCEEDED`.
- Runtime: Singapore infrastructure, database restore, ECS and ALB health gate passed.
- DNS failover: controlled outage served `region: ap-southeast-1`.
- DNS failback: Primary recovery served `region: ap-southeast-2`.
- Application data: test product returned during DR.
- Cleanup: runtime stack and restored database deleted after authorized test.
- Raw AWS logs remain local. This repository stores sanitized summaries only.
