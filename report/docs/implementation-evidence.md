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

## Vấn đề kỹ thuật cần lưu ý

- EventBridge đặt `skip_route53_switch=true`; recovery tự động không đồng nghĩa DNS cutover tự động.
- Primary parameter đặt `EcsDesiredCount=0`; cần bước scale sau publish image.
- Single NAT và Single-AZ RDS là trade-off chi phí.
- Restore idempotency token được tạo ngẫu nhiên mỗi invocation.
- Ứng dụng trả exception database trong HTTP 500.
- Ba service dùng cùng image và database; auth/order là endpoint demo.
