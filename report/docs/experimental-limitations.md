# Experimental Limitations

## Phạm vi kết quả

Timeline được dựng từ một execution ngày 30/09/2026. Kết quả cho thấy đường phục hồi kỹ thuật đã tạo runtime, restore RDS, scale ECS và vượt ALB health gate. Một mẫu chưa đủ để đánh giá biến thiên hoặc tỷ lệ thành công dài hạn.

## Giới hạn dữ liệu

- State machine và automation stack đã bị xóa; `DescribeExecution` trả `ExecutionDoesNotExist`.
- Timestamp cuối dựa trên Lambda release lock ngay trước trạng thái `DrSucceeded`, không phải bản ghi `ExecutionSucceeded` gốc.
- Payload trả về của Lambda `check-alb` không còn; health gate được xác định từ thứ tự invocation và transition của state machine.
- Không có output đối chiếu record của script real-data.
- Không có probe bên ngoài AWS hoặc DNS cutover.

## Phương pháp cho lần tiếp theo

1. Export Step Functions history ngay sau execution.
2. Lưu CloudFormation events, restore job và target health theo execution ID.
3. Chạy probe ngoài AWS mỗi 5-10 giây.
4. Lưu ID record trước backup và kết quả truy vấn sau restore.
5. Lưu Route 53 change ID nếu kịch bản được phê duyệt cutover.
6. Lặp nhiều lần trong cùng điều kiện trước khi tính thống kê.

## Ranh giới an toàn

Không chạy DR mới trong đợt thu thập này. Dữ liệu lịch sử đủ để dựng timeline có ý nghĩa; chạy lại sẽ tạo NAT Gateway, ALB, ECS và RDS tại Singapore, phát sinh chi phí không cần thiết.
