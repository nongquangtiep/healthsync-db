# BÁO CÁO PHÂN TÍCH ĐỐI CHIẾU (GAP ANALYSIS & CONSISTENCY REPORT)
**Dự án:** Số hóa Quy trình Khám chữa bệnh - Phòng khám Đa khoa HealthSync  
**Vai trò:** System Analyst & Database Administrator  
**Mục tiêu:** Rà soát và đối chiếu giữa Lưu đồ hoạt động (UML Activity Diagram) của BA và CSDL thực tế (Legacy Database) để giải quyết khủng hoảng vận hành.

---

## 1. Tóm tắt vấn đề
Hệ thống phòng khám HealthSync gặp lỗi nghiêm trọng khi triển khai thực tế ở hai nghiệp vụ chính: **"Tính phí phạt hủy lịch"** và **"Kê đơn thuốc"**. Nguyên nhân cốt lõi bắt nguồn từ việc lập trình viên Backend thiết kế cơ sở dữ liệu quá sơ sài, không đồng bộ với các trạng thái và yêu cầu dữ liệu mà Business Analyst (BA) đã mô hình hóa trên Activity Diagram.

---

## 2. Ba điểm "vênh" (Data Gaps) nghiêm trọng nhất giữa Nghiệp vụ và CSDL cũ

### 2.1. Anti-Pattern: Dùng cờ Boolean (`is_active`) cho quy trình nghiệp vụ đa trạng thái
* **Nghiệp vụ thực tế (Activity Diagram):** Vòng đời của một lịch hẹn là một chuỗi biến chuyển trạng thái tuần tự và có điều kiện rẽ nhánh: `PENDING` (Chờ duyệt) $\rightarrow$ `CONFIRMED` (Đã cọc) $\rightarrow$ `CHECKED_IN` (Đã đến) $\rightarrow$ `COMPLETED` (Khám xong) hoặc `CANCELLED` (Đã hủy).
* **CSDL cũ:** Chỉ sử dụng duy nhất một cột `is_active BOOLEAN DEFAULT TRUE`.
* **Hậu quả:** Kiểu dữ liệu nhị phân (True/False) làm mất hoàn toàn dấu vết tiến trình. Hệ thống không thể biết bệnh nhân đang ở bước nào (mới tạo lịch, đã đến phòng khám hay đã khám xong), dẫn đến việc không thể kích hoạt các logic nghiệp vụ theo từng nấc trạng thái.

### 2.2. Thiếu hụt hoàn toàn các trường dữ liệu Tài chính và Quản lý Hủy lịch
* **Nghiệp vụ thực tế:** Bệnh nhân bắt buộc phải đặt cọc (Deposit) khi đặt lịch. Nếu hủy sau khi lịch đã được xác nhận (`CONFIRMED`), hệ thống phải ghi nhận lý do hủy và áp dụng phí phạt (Penalty Fee) trừ vào tiền cọc.
* **CSDL cũ:** Bảng `Appointments` hoàn toàn không có các cột `deposit_amount`, `penalty_fee` và `cancel_reason`.
* **Hậu quả:** 
  * Ứng dụng Backend không có nơi lưu vết dòng tiền cọc và phạt.
  * Không thể đối soát doanh thu cuối tháng của phòng khám, vi phạm nguyên tắc toàn vẹn kế toán và làm thất thoát ngân sách.

### 2.3. Vắng mặt thực thể `Prescriptions` (Đơn thuốc)
* **Nghiệp vụ thực tế:** Khi lịch hẹn hoàn tất (`COMPLETED`), Bác sĩ phải kê một Đơn thuốc đi kèm để bệnh nhân mua thuốc/điều trị.
* **CSDL cũ:** Bác sĩ khám xong không có bảng nào để lưu trữ thông tin đơn thuốc.
* **Hậu quả:** Luồng nghiệp vụ bị đứt gãy tại điểm kết thúc của Activity Diagram. Tính năng kê đơn liên tục báo lỗi do thiếu bảng và khóa ngoại trỏ về lịch hẹn.

---

## 3. Giải pháp Khắc phục & Tái cấu trúc (Proposed Solution)

1. **Chuẩn hóa bảng `Appointments`:**
   * Loại bỏ cột `is_active`.
   * Thêm cột `status` kiểu `ENUM('PENDING', 'CONFIRMED', 'CHECKED_IN', 'COMPLETED', 'CANCELLED')` để phản ánh đúng vòng đời.
   * Bổ sung các cột tài chính dùng kiểu dữ liệu `DECIMAL(10, 2)` (tránh lỗi làm tròn của Float/Double): `deposit_amount`, `penalty_fee`, cùng cột `cancel_reason VARCHAR(255)`.
   * Thêm ràng buộc `CHECK (deposit_amount >= 0)` và `CHECK (penalty_fee >= 0)`.

2. **Bổ sung bảng `Prescriptions`:**
   * Thiết lập quan hệ 1 - 1 với `Appointments` thông qua khóa ngoại có ràng buộc `UNIQUE (appointment_id)` để đảm bảo mỗi lịch hẹn hoàn tất chỉ có đúng 1 đơn thuốc.

3. **Thiết lập Database Trigger bảo vệ nghiệp vụ:**
   * Xây dựng Trigger `BEFORE INSERT ON Prescriptions` để chặn ở tầng cơ sở dữ liệu nếu có ai cố tình kê đơn khi lịch hẹn chưa đạt trạng thái `COMPLETED`.
