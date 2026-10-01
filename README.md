# DevOps - Session 03 - Bài 1: Thay đổi cổng kết nối SSH (SSH Port Hardening)

Đổi cổng SSH mặc định từ 22 sang 2222 trên máy chủ Ubuntu 24.04 (`halo`) để giảm quét cổng và brute-force tự động. Cấu hình UFW mở cổng 2222 trước khi khởi động lại dịch vụ SSH nhằm tránh lockout; chỉ thao tác bằng user thường `devops` có sudo.

## Mục lục

- Báo cáo chi tiết: [homework/session_03/ex1/README.md](homework/session_03/ex1/README.md)

## Danh sách file

| File | Mô tả |
|---|---|
| [homework/session_03/ex1/README.md](homework/session_03/ex1/README.md) | Báo cáo các bước cấu hình kèm đoạn trích log terminal |
| [homework/session_03/ex1/terminal_log.txt](homework/session_03/ex1/terminal_log.txt) | Toàn bộ log phiên làm việc theo thứ tự thời gian |
| [homework/session_03/ex1/harden_ssh_port.sh](homework/session_03/ex1/harden_ssh_port.sh) | Script bash idempotent đổi cổng SSH (không tự xóa rule cổng 22) |
| [homework/session_03/ex1/sshd_config.snippet](homework/session_03/ex1/sshd_config.snippet) | Đoạn cấu hình `sshd_config` sau khi sửa |
| [homework/session_03/ex1/ssh_config.sample](homework/session_03/ex1/ssh_config.sample) | Mẫu `~/.ssh/config` trên máy cá nhân |
