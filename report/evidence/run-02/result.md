# DR run 02 - safe recovery

- Result: `SUCCEEDED`.
- Runtime infrastructure: `CREATE_COMPLETE`.
- Database restore: `COMPLETED`, database became `available`.
- ECS and ALB health gate: PASS.
- Elapsed workflow time: `1605.971` seconds (`26.766` minutes).
- DNS switch: skipped intentionally by `skip_route53_switch=true`.
