# Source Code Mapping

Tài liệu truy vết nội bộ cho báo cáo NT533. Trạng thái:

- `Implemented`: xác minh trực tiếp từ source.
- `Configured`: có parameter môi trường cụ thể, chưa chứng minh trạng thái AWS hiện tại.
- `Tested by user`: người dùng xác nhận đã chạy; thiếu log gốc trong repository.
- `Script-supported`: có script kiểm thử, chưa có bằng chứng output được lưu.
- `Not evidenced`: chưa có bằng chứng.

| Thành phần hệ thống | Source file | Chức năng xác minh được | Chương báo cáo | Trạng thái bằng chứng |
|---|---|---|---|---|
| Kiến trúc tổng thể | `NT533.drawio`, `NT533.jpg` | Primary Sydney, DR Singapore, replication, control plane | Chương 3 | Implemented diagram; đã đối chiếu code |
| Ứng dụng demo | `app/demo/app.py` | Health kiểm tra PostgreSQL; CRUD product; endpoint auth/order tối giản | Chương 3–4 | Implemented |
| Container image | `app/demo/Dockerfile`, `requirements.txt` | Python 3.12 slim, non-root, psycopg2, port 8080 | Chương 3–4 | Implemented |
| Primary root stack | `cloudformation/primary/root-primary.yaml` | Ghép network, security, ALB, RDS, ECR, ECS, backup, DNS, monitoring | Chương 3 | Implemented |
| Primary Network | `cloudformation/primary/network.yaml` | VPC 2 AZ; public, private app, isolated DB; single NAT | Chương 3 | Implemented |
| Primary Security | `cloudformation/primary/security.yaml` | ALB→ECS:8080; ECS→RDS:5432; HTTPS egress | Chương 3 | Implemented |
| Primary ALB | `cloudformation/primary/alb.yaml` | Path routing cho auth/product/order; `/health`; optional HTTPS | Chương 3 | Implemented |
| Primary ECS | `cloudformation/primary/ecs.yaml` | 3 Fargate services; secret injection; circuit breaker; health checks | Chương 3 | Implemented |
| Primary desired count | `cloudformation/parameters/prod-primary.json` | Giá trị commit là 0, cần scale sau deploy | Chương 3–4 | Configured |
| Primary RDS | `cloudformation/primary/rds.yaml` | PostgreSQL 16, gp3, encrypted, TLS, private, secret replica | Chương 3 | Implemented |
| ECR replication | `cloudformation/primary/ecr.yaml`, `bootstrap/dr-ecr.yaml` | 3 immutable repositories; scan; Sydney→Singapore replication | Chương 2–3 | Implemented |
| AWS Backup | `cloudformation/primary/backup.yaml` | Backup mỗi 6 giờ, retention 7 ngày, copy Singapore | Chương 3–4 | Implemented; tested by user indirectly |
| Route 53 Primary | `cloudformation/primary/route53.yaml` | Failover PRIMARY alias; independent endpoint health check | Chương 3 | Implemented |
| Primary alarms | `cloudformation/primary/monitoring.yaml` | 3-of-5 minute metric alarms; composite OR | Chương 3 | Implemented |
| DR baseline | `cloudformation/bootstrap/regional-baseline.yaml` | S3 artifacts, KMS, backup vault retained | Chương 3 | Implemented/configured |
| DR runtime root | `cloudformation/dr/root-dr.yaml` | Runtime VPC/ALB/ECS/dashboard; RDS restored separately | Chương 3 | Implemented; tested by user |
| DR Network | `cloudformation/dr/network.yaml` | VPC `10.20.0.0/16`, 2 AZ, single NAT, isolated DB | Chương 3 | Implemented |
| DR ECS | `cloudformation/dr/ecs.yaml` | Service desired count 0; runtime secret; scale by workflow | Chương 3 | Implemented; tested by user |
| DR ALB | `cloudformation/dr/alb.yaml` | Path routing và target health tương tự Primary | Chương 3–4 | Implemented; tested by user |
| DR monitoring | `cloudformation/dr/monitoring.yaml` | Dashboard running task và p99 target response time | Chương 3 | Implemented |
| Automation root | `cloudformation/automation/root-automation.yaml` | Ghép SNS, lock, IAM, Lambda, Step Functions, EventBridge | Chương 3 | Implemented |
| State machine | `cloudformation/automation/stepfunctions.yaml` | 57 states; confirmation, restore, health, optional DNS, failure path | Chương 3–4 | Implemented; tested by user once |
| Primary check | `automation/lambda/check-primary/index.py` | Đọc metric/composite alarm; simulation mode | Chương 3 | Implemented |
| Recovery point selection | `automation/lambda/find-recovery-point/index.py` | Chọn recovery point RDS COMPLETED mới nhất đúng nguồn | Chương 3 | Implemented |
| Restore start | `automation/lambda/start-restore/index.py` | Chuẩn hóa metadata và gọi AWS Backup restore | Chương 3 | Implemented; tested by user |
| Runtime secret | `automation/lambda/update-secret/index.py` | Ghép credentials replica với endpoint RDS restore | Chương 3 | Implemented; tested by user |
| ALB gate | `automation/lambda/check-alb/index.py` | Đếm target healthy của 3 target group | Chương 3–4 | Implemented; tested by user |
| Stack output validation | `automation/lambda/parse-stack-outputs/index.py` | Bắt buộc 13 output phục vụ restore/scale | Chương 3 | Implemented |
| Singleton lock | `automation/lambda/manage-lock/index.py`, `lock.yaml` | Conditional write, owner check, TTL | Chương 2–3 | Implemented; test riêng chưa evidenced |
| Event forwarding | `eventbridge-primary.yaml`, `eventbridge-dr.yaml` | Forward exact alarm sang custom bus, DLQ, start execution | Chương 3 | Implemented |
| DNS safety default | `eventbridge-dr.yaml`, `invoke-dr-test.ps1`, `test-real-data-dr.ps1` | `skip_route53_switch=true` mặc định | Chương 3–5 | Implemented; DNS cutover not evidenced |
| Validation | `cloudformation/scripts/validate.ps1` | cfn-lint và Python compile | Chương 4 | Script-supported |
| Packaging | `cloudformation/scripts/package.ps1` | Nested stack package; immutable DR release path | Chương 4 | Implemented |
| Deploy | `deploy-primary.ps1`, `deploy-automation.ps1` | Parameter override và CloudFormation deploy | Chương 4 | Script-supported/configured |
| Image publish | `publish-images.ps1` | Build một image, push ba repository, nhắc verify Singapore | Chương 4 | Script-supported |
| Real-data DR test | `test-real-data-dr.ps1` | Ghi record, chọn recovery point mới, restore, kiểm tra record | Chương 4 | Script-supported; tested by user once |
| Cleanup | `cleanup-dr-test.ps1` | Chặn phá hủy, kiểm tra DNS, scale zero, snapshot/xóa RDS, xóa stack | Chương 2, 4 | Implemented; execution not evidenced |
| Parameter môi trường | `cloudformation/parameters/*.json` | Region, CIDR, sizes, schedule, domain, ARN | Chương 3–4 | Configured; không chứng minh live state |
| Kết quả 21 phút | Yêu cầu người dùng cung cấp | Một lần phục hồi quan sát khoảng 21 phút | Chương 4–5 | Tested by user; no repository log |

## Khác biệt README/code cần giữ trong báo cáo

1. Composite alarm dùng `OR`: một target group mất healthy host có thể kích hoạt, không cần cả ba dịch vụ cùng lỗi.
2. EventBridge alarm input đặt `skip_route53_switch=true`; DNS cutover không tự chạy theo cấu hình hiện tại.
3. `prod-primary.json` đặt `EcsDesiredCount=0`; workload Primary cần được scale riêng sau deploy.
4. Singapore vẫn có chi phí lưu trữ/control-plane; không phải chi phí standby bằng 0 tuyệt đối.
5. Giá trị 21 phút không có timestamp trong repository; không gọi là RTO chính thức.
