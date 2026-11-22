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
- `evidence/run-02/`: execution history và số liệu safe DR run ngày 22/11/2026.
- `evidence/run-03/`: failure-path test với trigger không hợp lệ.
- `evidence/run-04/`: real-data recovery và record comparison PASS.
- `evidence/run-05/`: controlled restore failure.
- `evidence/run-06/`: CloudFormation rollback failure test.
- `evidence/run-07/`: DNS RTO test window stopped before cutover.
- `evidence/run-08/`: automated failover, DNS Singapore validation and failback Primary.
- `evidence/run-02/` through `evidence/run-08/`: sanitized run summaries. Raw AWS logs remain local and are not published to GitHub.
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

Execution lịch sử `real-data-dr-20260930-214735` được truy vết bằng CloudTrail, CloudFormation, AWS Backup và CloudWatch Logs. Safe DR run mới `safe-dr-20261122-051814` đạt `SUCCEEDED` sau `1605.971` giây, tương đương `26.766` phút. Failure-path run `failure-path-20261122-054852` bị từ chối đúng với `InvalidTrigger` trước khi tạo runtime. Safe test không chuyển Route 53.

Chương 4 trình bày các bước thành công từ khởi tạo workflow đến ALB healthy, bảng timestamp, thời lượng từng giai đoạn và biểu đồ phục hồi. Run 04 đã đối chiếu record ứng dụng và đạt `DataRestoreValidation: PASS`. Run 05 chứng minh restore failure path; run 06 chứng minh CloudFormation `ROLLBACK_COMPLETE`; run 07 dừng trước DNS cutover; Run 08 sau đó chứng minh DNS failover sang Singapore và failback về Sydney.
