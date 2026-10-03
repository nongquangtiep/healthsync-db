-- ========================================================
-- DỰ ÁN HEALTHSYNC - DATABASE SCHEMA & TEST SCENARIOS
-- File: healthsync_db.sql
-- ========================================================

DROP DATABASE IF EXISTS healthsync_db;
CREATE DATABASE healthsync_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE healthsync_db;

-- --------------------------------------------------------
-- 1. BẢNG DANH MỤC CƠ BẢN
-- --------------------------------------------------------
CREATE TABLE Patients (
    patient_id INT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    phone VARCHAR(15) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE Doctors (
    doctor_id INT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    specialty VARCHAR(50) NOT NULL
) ENGINE=InnoDB;

-- --------------------------------------------------------
-- 2. BẢNG APPOINTMENTS (ĐÃ TÁI CẤU TRÚC CHUẨN ACTIVITY DIAGRAM)
-- --------------------------------------------------------
-- - Bỏ cột is_active (Boolean Anti-pattern).
-- - Dùng ENUM thể hiện trọn vẹn 5 trạng thái vòng đời.
-- - Dùng DECIMAL(10, 2) bảo đảm độ chính xác tài chính tuyệt đối.
CREATE TABLE Appointments (
    appointment_id INT AUTO_INCREMENT PRIMARY KEY,
    patient_id INT NOT NULL,
    doctor_id INT NOT NULL,
    appointment_date DATETIME NOT NULL,
    status ENUM('PENDING', 'CONFIRMED', 'CHECKED_IN', 'COMPLETED', 'CANCELLED') 
        NOT NULL DEFAULT 'PENDING',
    deposit_amount DECIMAL(10, 2) NOT NULL DEFAULT 0.00 CHECK (deposit_amount >= 0),
    penalty_fee DECIMAL(10, 2) NOT NULL DEFAULT 0.00 CHECK (penalty_fee >= 0),
    cancel_reason VARCHAR(255) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES Patients(patient_id) ON DELETE RESTRICT,
    FOREIGN KEY (doctor_id) REFERENCES Doctors(doctor_id) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- --------------------------------------------------------
-- 3. BẢNG PRESCRIPTIONS (ĐƠN THUỐC)
-- --------------------------------------------------------
-- Mỗi lịch hẹn hoàn tất chỉ có duy nhất 1 đơn thuốc (Quan hệ 1 - 1 qua UNIQUE appointment_id)
CREATE TABLE Prescriptions (
    prescription_id INT AUTO_INCREMENT PRIMARY KEY,
    appointment_id INT NOT NULL UNIQUE, 
    medication_details TEXT NOT NULL,
    issued_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (appointment_id) REFERENCES Appointments(appointment_id) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- --------------------------------------------------------
-- 4. RÀNG BUỘC NGHIỆP VỤ BẰNG DATABASE TRIGGER
-- --------------------------------------------------------
-- Chặn hành vi chèn đơn thuốc khi lịch hẹn chưa đạt trạng thái COMPLETED
DELIMITER //

CREATE TRIGGER trg_before_insert_prescription
BEFORE INSERT ON Prescriptions
FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(20) DEFAULT NULL;
    
    -- Lấy trạng thái của lịch hẹn
    SELECT status INTO v_status 
    FROM Appointments 
    WHERE appointment_id = NEW.appointment_id;
    
    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Lỗi nghiệp vụ: Lịch hẹn không tồn tại.';
    ELSEIF v_status != 'COMPLETED' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Lỗi nghiệp vụ: Không thể kê đơn thuốc cho lịch hẹn chưa ở trạng thái COMPLETED.';
    END IF;
END;
//

DELIMITER ;

-- ========================================================
-- 5. CHÈP DỮ LIỆU MẪU & MÔ PHỎNG LUỒNG NGHIỆP VỤ (DML)
-- ========================================================

-- Dữ liệu ban đầu
INSERT INTO Patients (full_name, phone) VALUES 
('Nguyễn Văn An', '0901234567'),
('Trần Thị Bình', '0912345678');

INSERT INTO Doctors (full_name, specialty) VALUES 
('BS. Lê Hoàng Minh', 'Nội tổng quát'),
('BS. Phạm Thanh Thảo', 'Tai Mũi Họng');

-- --------------------------------------------------------
-- KỊCH BẢN 1: Luồng thành công (Happy Path)
-- --------------------------------------------------------
-- 1.1 Bệnh nhân An đặt lịch hẹn mới, cọc 500.000 VNĐ (PENDING)
INSERT INTO Appointments (patient_id, doctor_id, appointment_date, status, deposit_amount)
VALUES (1, 1, '2026-10-10 09:00:00', 'PENDING', 500000.00);

SET @app_success_id = LAST_INSERT_ID();

-- 1.2 Phòng khám xác nhận cọc -> Bệnh nhân đến nơi check-in
UPDATE Appointments SET status = 'CONFIRMED' WHERE appointment_id = @app_success_id;
UPDATE Appointments SET status = 'CHECKED_IN' WHERE appointment_id = @app_success_id;

-- 1.3 Bác sĩ khám xong -> Chuyển sang COMPLETED
UPDATE Appointments SET status = 'COMPLETED' WHERE appointment_id = @app_success_id;

-- 1.4 Bác sĩ kê đơn thuốc (Thành công vì status đã là COMPLETED)
INSERT INTO Prescriptions (appointment_id, medication_details)
VALUES (@app_success_id, '1. Paracetamol 500mg (20 viên) - Uống khi sốt\n2. Vitamin C 500mg (30 viên) - Uống sau ăn');

-- --------------------------------------------------------
-- KỊCH BẢN 2: Luồng hủy lịch và phạt cọc (Penalty Path)
-- --------------------------------------------------------
-- 2.1 Bệnh nhân Bình đặt lịch và đã xác nhận cọc 300.000 VNĐ
INSERT INTO Appointments (patient_id, doctor_id, appointment_date, status, deposit_amount)
VALUES (2, 2, '2026-10-11 14:00:00', 'CONFIRMED', 300000.00);

SET @app_cancel_id = LAST_INSERT_ID();

-- 2.2 Hủy lịch sau khi CONFIRMED: Ghi nhận lý do và phạt 50% tiền cọc (150.000 VNĐ)
UPDATE Appointments 
SET status = 'CANCELLED',
    cancel_reason = 'Bận việc đột xuất',
    penalty_fee = 150000.00
WHERE appointment_id = @app_cancel_id;

-- ========================================================
-- 6. TRUY VẤN KIỂM CHỨNG & BÁO CÁO TÀI CHÍNH
-- ========================================================

-- Kiểm tra danh sách bệnh nhân đã hoàn tất khám kèm đơn thuốc
SELECT 
    a.appointment_id,
    p.full_name AS patient_name,
    d.full_name AS doctor_name,
    a.appointment_date,
    a.status,
    pr.medication_details,
    pr.issued_date
FROM Appointments a
JOIN Patients p ON a.patient_id = p.patient_id
JOIN Doctors d ON a.doctor_id = d.doctor_id
JOIN Prescriptions pr ON a.appointment_id = pr.appointment_id
WHERE a.status = 'COMPLETED';

-- Báo cáo đối soát tổng tiền cọc và tiền phạt thu được theo trạng thái
SELECT 
    status,
    COUNT(appointment_id) AS total_appointments,
    SUM(deposit_amount) AS total_deposits,
    SUM(penalty_fee) AS total_penalty_collected
FROM Appointments
GROUP BY status;

-- ========================================================
-- 7. KỊCH BẢN KIỂM THỬ TRIGGER (TEST EXCEPTION)
-- (Bỏ comment để chạy thử nghiệm việc Trigger chặn kê đơn sai quy trình)
-- ========================================================

-- Tạo lịch hẹn đang PENDING:
INSERT INTO Appointments (patient_id, doctor_id, appointment_date, status, deposit_amount)
VALUES (1, 2, '2026-10-15 10:00:00', 'PENDING', 200000.00);

-- Cố tình kê đơn khi chưa COMPLETED (Kỳ vọng: Báo lỗi Error Code 1644)
INSERT INTO Prescriptions (appointment_id, medication_details)
VALUES (LAST_INSERT_ID(), 'Kháng sinh Amoxicillin 500mg');
