# Implementation Evidence

## Dữ liệu AWS đã truy xuất

- Tài khoản: `[REDACTED_ACCOUNT_ID]`; truy vấn thực hiện ở chế độ read-only.
- Execution: `real-data-dr-20260930-214735`.
- Execution ARN: `[REDACTED_ARN]:execution:prod-dr-orchestrator:real-data-dr-20260930-214735`.
- Bắt đầu: `2026-09-30T14:49:42Z`.
- Runtime stack `prod-dr-runtime-production`: `CREATE_COMPLETE` lúc `14:58:46.717Z`.
- Restore job `1816ab82-edd5-4fcd-ad0e-013f29ece4bf`: `COMPLETED`, chạy `14:58:51.187Z` đến `15:07:18.723Z`.
- Ba ECS service được scale lên desired count 1 lúc `15:07:55Z`.
- ALB health gate thành công lúc `15:08:56.762Z`.
- Bước release lock ngay trước trạng thái thành công hoàn tất lúc `15:08:59.230Z`.
- RDS restore và runtime stack đã được cleanup sau lần chạy.

## Kết quả được phép sử dụng trong báo cáo

- DR runtime tại Singapore được tạo thành công.
- AWS Backup khôi phục RDS thành công.
- Ba ECS service được khởi chạy.
- Ba target group vượt health gate.
- Thời gian từ workflow start đến ALB healthy: `19 phút 14,762 giây`.
- Thời gian từ workflow start đến bước release lock hoàn tất: `19 phút 17,230 giây`.
- DNS cutover không được thực hiện trong safe test.

## Dữ liệu chưa đủ để kết luận

- Step Functions execution history không còn vì state machine đã bị xóa.
- Timestamp `ExecutionSucceeded` chính xác không còn truy xuất được.
- Không còn output của `test-real-data-dr.ps1`; không kết luận `DataRestoreValidation = PASS`.
- Không có probe liên tục từ client hoặc timestamp Route 53 `INSYNC`.
- Chưa có workflow failback.

## Safe test run 02

- Execution `safe-dr-20261122-051814` tại `ap-southeast-1` đạt `SUCCEEDED`.
- Bắt đầu `2026-11-22T12:18:14.621+07:00`; kết thúc `2026-11-22T12:45:00.592+07:00`.
- Safe-test elapsed/RTO proxy: `1605.971` giây, tương đương `26.766` phút.
- DR runtime `CREATE_COMPLETE`; AWS Backup restore `COMPLETED`; RDS `available`; ECS services scale lên desired count 1; health gate pass.
- Route 53 bị bỏ qua bằng `skip_route53_switch=true`, nên số đo chưa phải production RTO.
- Recovery point copy creation `2026-11-22T12:07:49.072+07:00`. RPO cần trừ từ thời điểm incident thật.
- Evidence đầy đủ nằm trong `report/evidence/run-02/`.

## Bổ sung run 04–07

- Run 04 `data-dr-20261122-061417`: RDS restore và record comparison PASS. Record `NT533-DR-TEST-20261122-060513` giữ nguyên id, name, price và `created_at` tại DR.
- Run 05 `restore-failure-064010`: controlled restore failure, execution kết thúc `FAILED`, failure notification/release lock path được thực thi.
- Run 06 `prod-dr-infra-failure-test`: invalid S3 bucket name, CloudFormation kết thúc `ROLLBACK_COMPLETE`.
- Run 07 `dns-rto-071010`: DNS cutover test có `skip_route53_switch=false`, nhưng dừng trước cutover khi runtime provisioning chưa hoàn tất.
- Run 08 `production-failover-cutover-084659`: custom health probe kích hoạt Composite Alarm, EventBridge và Step Functions. DR runtime đạt health gate, Route 53 tạo SECONDARY, controlled outage trả `region: ap-southeast-1`, sau failback trả `region: ap-southeast-2`. Runtime stack và RDS restored đã được cleanup sau diễn tập.
- Run 08 logs được trích tại `report/evidence/run-08/logs/`, gồm execution history, CloudFormation events, restore jobs, ECS services, alarm states, EventBridge targets và Route 53 records.

## Vấn đề kỹ thuật cần lưu ý

- EventBridge đặt `skip_route53_switch=true`; recovery tự động không đồng nghĩa DNS cutover tự động.
- Primary parameter đặt `EcsDesiredCount=0`; cần bước scale sau publish image.
- Single NAT và Single-AZ RDS là trade-off chi phí.
- Restore idempotency token được tạo ngẫu nhiên mỗi invocation.
- Ứng dụng trả exception database trong HTTP 500.
- Ba service dùng cùng image và database; auth/order là endpoint demo.
