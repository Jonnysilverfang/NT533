# DR run 01 - kết quả truy vết

## Execution được chọn

- Execution: `real-data-dr-20260930-214735`.
- Bắt đầu: `2026-09-30T14:49:42Z`.
- Primary Region: Sydney (`ap-southeast-2`).
- DR Region: Singapore (`ap-southeast-1`).
- Nguồn định danh: AWS CloudTrail `StartExecution`.

State machine và automation stack đã bị xóa trong ngày 30/09/2026. Vì vậy `DescribeExecution` trả `ExecutionDoesNotExist`, execution history gốc không còn truy xuất được và file `execution-history.json` không được tạo.

## Timeline xác minh được

| Giai đoạn | Bắt đầu UTC | Kết thúc UTC | Thời lượng |
|---|---|---|---:|
| Chờ xác nhận trước khi tạo runtime | 14:49:42.000 | 14:51:15.738 | 1 phút 33,738 giây |
| Tạo DR runtime stack | 14:51:15.738 | 14:58:46.717 | 7 phút 30,979 giây |
| AWS Backup restore RDS | 14:58:51.187 | 15:07:18.723 | 8 phút 27,536 giây |
| Restore hoàn tất đến ALB healthy | 15:07:18.723 | 15:08:56.762 | 1 phút 38,039 giây |
| Workflow bắt đầu đến ALB healthy | 14:49:42.000 | 15:08:56.762 | 19 phút 14,762 giây |
| Workflow bắt đầu đến bước release lock hoàn tất | 14:49:42.000 | 15:08:59.230 | 19 phút 17,230 giây |

Mốc `ExecutionSucceeded` chính xác không còn truy xuất được. Bước release lock ngay trước trạng thái `DrSucceeded` hoàn tất tại `15:08:59.230Z`, nên báo cáo dùng cụm “đường phục hồi quan sát được hoàn tất trong khoảng 19 phút 17 giây”, không gọi đây là timestamp `ExecutionSucceeded` tuyệt đối.

## Kết quả

- CloudFormation runtime: `CREATE_COMPLETE`.
- AWS Backup restore job: `COMPLETED`.
- RDS `available`: được workflow quan sát trước khi Lambda cập nhật runtime secret.
- Ba ECS service được scale lên desired count 1.
- Ba target group vượt health gate trước bước kiểm tra Primary lần cuối.
- Route 53: không cutover trong safe test.
- Cleanup: RDS và runtime stack của lần chạy đã được xóa sau khi test; trạng thái hiện tại tại Singapore không còn RDS/runtime NT533.
- DataRestoreValidation: không kết luận PASS vì không tìm thấy output của `test-real-data-dr.ps1` hoặc record đối chiếu.

## Dữ liệu không còn truy xuất được

- Step Functions `DescribeExecution` và execution history.
- Payload trả về của Lambda `check-alb`.
- Output local của script kiểm tra dữ liệu.
- Probe liên tục từ góc nhìn người dùng.

Không chạy DR mới. Dữ liệu lịch sử hiện có đủ để dựng timeline kỹ thuật có ý nghĩa, tránh tạo thêm NAT Gateway, ALB, ECS và RDS tại Singapore.
