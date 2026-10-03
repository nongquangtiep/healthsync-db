# NHẬT KÝ SỬ DỤNG AI TRONG DỰ ÁN HEALTHSYNC (AI PROMPT LOG)
**Học viên:** [Điền họ và tên của bạn]  
**Vai trò:** System Analyst & Database Administrator  
**Mục đích:** Sử dụng Trợ lý AI để phản biện logic, lựa chọn kiểu dữ liệu tối ưu và thiết kế ràng buộc bảo vệ toàn vẹn hệ thống CSDL phòng khám HealthSync.

---

### Phiên làm việc 1: Phân tích Anti-Pattern trạng thái vòng đời
* **Người dùng (Prompt):**  
  > *"Trong thiết kế cơ sở dữ liệu quan hệ MySQL, tại sao việc dùng một cột `is_active` (kiểu TINYINT/BOOLEAN) để theo dõi vòng đời của một Đơn hàng/Lịch hẹn lại là một thiết kế tồi (Anti-pattern)? Tôi nên thay thế bằng cấu trúc nào để khớp với một Activity Diagram có 5 trạng thái?"*
* **Tóm tắt phản hồi của AI:**  
  * Cột boolean chỉ có thể thể hiện 2 trạng thái bật/tắt (nhị phân), làm mất dấu hoàn toàn các giai đoạn trung gian như `PENDING`, `CONFIRMED`, `CHECKED_IN`.
  * Khuyến nghị: Sử dụng kiểu dữ liệu `ENUM` trong MySQL cho các tập trạng thái cố định hoặc tạo một bảng danh mục trạng thái riêng biệt (`Lookup Table`) nếu trạng thái cần mở rộng linh hoạt theo thời gian.

---

### Phiên làm việc 2: Xử lý rủi ro kiểu dữ liệu tài chính (Floating-point error)
* **Người dùng (Prompt):**  
  > *"Khi thiết kế cột `deposit_amount` và `penalty_fee` trong MySQL phục vụ tính toán tài chính và đối soát kế toán, tôi nên dùng kiểu dữ liệu FLOAT, DOUBLE hay DECIMAL? Tại sao?"*
* **Tóm tắt phản hồi của AI:**  
  * Tuyệt đối không dùng `FLOAT` hoặc `DOUBLE` cho dữ liệu tài chính vì chúng lưu trữ số thực dấu phẩy động nhị phân theo chuẩn IEEE 754, sẽ dẫn tới sai số làm tròn số học (Round-off / Precision errors) khi cộng trừ tiền cọc và tiền phạt.
  * Bắt buộc dùng `DECIMAL(M, D)` (ví dụ `DECIMAL(10, 2)`) vì đây là kiểu số có độ chính xác cố định (Fixed-point), đảm bảo khớp tuyệt đối với sổ sách kế toán.

---

### Phiên làm việc 3: Ràng buộc nghiệp vụ ở tầng CSDL (Database Trigger)
* **Người dùng (Prompt):**  
  > *"Làm thế nào để chặn hoàn toàn việc chèn một đơn thuốc vào bảng `Prescriptions` nếu lịch hẹn tương ứng chưa ở trạng thái `COMPLETED`? Khóa ngoại thông thường có làm được việc này không hay phải dùng Trigger?"*
* **Tóm tắt phản hồi của AI:**  
  * Ràng buộc Foreign Key tiêu chuẩn chỉ kiểm tra tính tồn tại của dòng cha, không kiểm tra được giá trị của một cột cụ thể (`status = 'COMPLETED'`).
  * Giải pháp ở tầng CSDL là sử dụng `BEFORE INSERT TRIGGER` trên bảng `Prescriptions`. Trigger sẽ truy vấn bảng `Appointments`, nếu trạng thái khác `COMPLETED` thì chủ động phát sinh lỗi bằng lệnh `SIGNAL SQLSTATE '45000'` để hủy transaction.

---

### Phiên làm việc 4: Kiểm thử kịch bản ngoại lệ
* **Người dùng (Prompt):**  
  > *"Hãy gợi ý cho tôi cú pháp kịch bản SQL chèn thử đơn thuốc cho một lịch hẹn đang ở trạng thái `PENDING` để kiểm chứng Trigger hoạt động chính xác."*
* **Tóm tắt phản hồi của AI:**  
  * Cung cấp khối lệnh tạo bản ghi `PENDING`, sau đó cố tình chạy `INSERT INTO Prescriptions` để quan sát lỗi trả về `Error Code: 1644` trên bảng Action Output của MySQL Workbench.
