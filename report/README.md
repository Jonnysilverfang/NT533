# Báo cáo đồ án NT533

Báo cáo LaTeX dùng UIT Course Report Template, được viết từ source code thực tế của repository NT533.

## Nội dung

- `main.tex`: entry point.
- `chapters/`: năm chương báo cáo.
- `misc/`: bìa, lời cảm ơn, tóm tắt, abstract, từ viết tắt.
- `appendix/`: cấu hình, workflow, phương pháp đo, phân công và bằng chứng.
- `references/references.bib`: tài liệu AWS chính thức.
- `docs/source-code-mapping.md`: truy vết báo cáo đến source.
- `docs/implementation-evidence.md`: phân loại implemented/deployed/tested.
- `docs/experimental-limitations.md`: giới hạn một lần thực nghiệm.
- `evidence/run-01/`: dữ liệu lịch sử AWS và timeline của lần DR ngày 30/09/2026.
- `main-evidence.pdf`: bản PDF mới nhất, đã nhúng trực tiếp bảng mốc sự kiện, bảng thời lượng và biểu đồ phục hồi.

## Compile

Host hiện không có TeX Live/MiKTeX. Nếu Docker hoạt động:

```powershell
docker run --rm -v "${PWD}:/work" -w /work texlive/texlive:latest `
  latexmk -pdf -interaction=nonstopmode -halt-on-error main.tex
```

Hoặc upload toàn bộ thư mục `report/` lên Overleaf và compile bằng pdfLaTeX. Bibliography dùng `biblatex` với Biber.

## Thông tin cần bổ sung trước khi nộp

- Tên môn học đầy đủ.
- Mã lớp học phần.
- Giảng viên hướng dẫn.
- Họ tên, MSSV, vai trò và phân công thành viên.

## Kết quả thực nghiệm

Execution `real-data-dr-20260930-214735` được truy vết bằng CloudTrail, CloudFormation, AWS Backup và CloudWatch Logs. ALB health gate thành công sau khoảng 19 phút 15 giây; bước cuối của workflow hoàn tất sau khoảng 19 phút 17 giây. Safe test không chuyển Route 53. Không chạy thêm DR mới.

Chương 4 trình bày trực tiếp năm bước thành công từ khởi tạo workflow đến ALB healthy, bảng timestamp, thời lượng từng giai đoạn và biểu đồ phục hồi. Phụ lục C.2 chứa các trường evidence chính đã rút gọn; JSON/CSV gốc vẫn nằm trong `evidence/run-01/` để truy vết. Không kết luận record-level data validation PASS vì output đối chiếu record của lần chạy cũ không còn.
