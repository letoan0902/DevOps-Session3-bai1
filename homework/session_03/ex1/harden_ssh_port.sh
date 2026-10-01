#!/usr/bin/env bash
# =============================================================================
# harden_ssh_port.sh - Đổi cổng SSH sang cổng mới (mặc định 2222) trên Ubuntu 24.04
#
# Thứ tự thao tác (chống lockout):
#   1. Mở cổng mới trên UFW TRƯỚC
#   2. Sao lưu /etc/ssh/sshd_config
#   3. Sửa chỉ thị Port
#   4. Kiểm tra cú pháp bằng sshd -t (lỗi thì khôi phục bản sao lưu và dừng)
#   5. daemon-reload, restart ssh.socket (nếu có) rồi restart ssh
#   6. Kiểm tra tiến trình đang nghe cổng mới
#
# Script KHÔNG tự xóa rule cổng 22 trên UFW. Sau khi mở Terminal MỚI và đăng
# nhập thành công qua cổng mới, tự chạy lệnh được in ở cuối script.
#
# Cách dùng (chạy bằng user thường có sudo, KHÔNG chạy bằng root):
#   bash harden_ssh_port.sh          # dùng cổng 2222
#   bash harden_ssh_port.sh 2200     # dùng cổng khác
#
# Script idempotent: chạy lại nhiều lần không tạo rule/dòng cấu hình trùng lặp.
# =============================================================================
set -euo pipefail

readonly NEW_PORT="${1:-2222}"
readonly SSHD_CONFIG="/etc/ssh/sshd_config"
readonly SSHD_DROPIN_DIR="/etc/ssh/sshd_config.d"
readonly BACKUP="${SSHD_CONFIG}.bak-$(date +%Y%m%d)"

log()  { printf '[INFO] %s\n' "$*"; }
warn() { printf '[CẢNH BÁO] %s\n' "$*" >&2; }
die()  { printf '[LỖI] %s\n' "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Bước 0: kiểm tra điều kiện đầu vào
# -----------------------------------------------------------------------------
if [[ "${EUID}" -eq 0 ]]; then
    die "Không chạy bằng root. Hãy dùng user thường có sudo (ví dụ: devops)."
fi

if ! [[ "${NEW_PORT}" =~ ^[0-9]+$ ]] || (( NEW_PORT < 1024 || NEW_PORT > 65535 )); then
    die "Cổng '${NEW_PORT}' không hợp lệ. Chọn số trong khoảng 1024 - 65535."
fi

for cmd in sudo ufw sshd systemctl ss; do
    command -v "${cmd}" >/dev/null 2>&1 || die "Thiếu lệnh '${cmd}' trên máy chủ."
done

sudo -v || die "Không lấy được quyền sudo."

# -----------------------------------------------------------------------------
# Bước 1: mở cổng mới trên UFW TRƯỚC khi đụng tới cấu hình SSH
# -----------------------------------------------------------------------------
if sudo ufw status | grep -q '^Status: active'; then
    if sudo ufw status | grep -Eq "^${NEW_PORT}/tcp[[:space:]]+ALLOW"; then
        log "UFW đã có rule ${NEW_PORT}/tcp, bỏ qua."
    else
        log "Mở cổng ${NEW_PORT}/tcp trên UFW."
        sudo ufw allow "${NEW_PORT}/tcp"
    fi
else
    warn "UFW chưa bật. Script không tự bật UFW; hãy kiểm tra firewall của nhà cung cấp."
fi

# -----------------------------------------------------------------------------
# Bước 2: sao lưu cấu hình (chỉ tạo một lần trong ngày để không ghi đè bản gốc)
# -----------------------------------------------------------------------------
if [[ -e "${BACKUP}" ]]; then
    log "Bản sao lưu ${BACKUP} đã tồn tại, giữ nguyên."
else
    log "Sao lưu ${SSHD_CONFIG} -> ${BACKUP}"
    sudo cp "${SSHD_CONFIG}" "${BACKUP}"
fi

# -----------------------------------------------------------------------------
# Bước 3: sửa chỉ thị Port
# -----------------------------------------------------------------------------
# sshd_config có dòng "Include /etc/ssh/sshd_config.d/*.conf" ở đầu file, giá trị
# nào được đọc trước sẽ thắng. Nếu drop-in có Port thì sửa file chính là vô ích.
if sudo grep -rEqs '^[[:space:]]*Port[[:space:]]+' "${SSHD_DROPIN_DIR}"; then
    die "Có chỉ thị Port trong ${SSHD_DROPIN_DIR}; hãy sửa tại đó để tránh xung đột."
fi

current_ports="$(grep -E '^[[:space:]]*Port[[:space:]]+' "${SSHD_CONFIG}" || true)"

if [[ "${current_ports}" == "Port ${NEW_PORT}" ]]; then
    log "${SSHD_CONFIG} đã có 'Port ${NEW_PORT}', bỏ qua bước sửa."
else
    log "Đặt 'Port ${NEW_PORT}' trong ${SSHD_CONFIG}."
    # Chuyển mọi dòng Port đang hoạt động thành comment để không bị trùng cổng.
    sudo sed -i -E 's/^[[:space:]]*(Port[[:space:]]+[0-9]+.*)$/#\1/' "${SSHD_CONFIG}"
    if grep -Eq '^#Port[[:space:]]+[0-9]+' "${SSHD_CONFIG}"; then
        # Thay dòng "#Port ..." đầu tiên bằng "Port <cổng mới>".
        sudo sed -i -E "0,/^#Port[[:space:]]+[0-9]+.*/s//Port ${NEW_PORT}/" "${SSHD_CONFIG}"
    else
        echo "Port ${NEW_PORT}" | sudo tee -a "${SSHD_CONFIG}" >/dev/null
    fi
fi

# -----------------------------------------------------------------------------
# Bước 4: kiểm tra cú pháp; nếu lỗi thì khôi phục bản sao lưu và dừng
# -----------------------------------------------------------------------------
if sudo sshd -t; then
    log "sshd -t: cấu hình hợp lệ."
else
    warn "sshd -t báo lỗi. Khôi phục ${BACKUP} và dừng, chưa restart dịch vụ."
    sudo cp "${BACKUP}" "${SSHD_CONFIG}"
    exit 1
fi

# -----------------------------------------------------------------------------
# Bước 5: áp dụng cấu hình
# Ubuntu 22.10 trở lên (kể cả 24.04) dùng socket activation: ssh.socket giữ cổng
# nghe. Nếu chỉ restart ssh.service thì socket vẫn nghe cổng cũ.
# -----------------------------------------------------------------------------
log "systemctl daemon-reload"
sudo systemctl daemon-reload

if systemctl is-enabled --quiet ssh.socket 2>/dev/null || systemctl is-active --quiet ssh.socket 2>/dev/null; then
    log "Phát hiện ssh.socket, restart ssh.socket."
    sudo systemctl restart ssh.socket
fi

log "systemctl restart ssh"
sudo systemctl restart ssh

# -----------------------------------------------------------------------------
# Bước 6: xác nhận tiến trình đang nghe cổng mới
# (lưu kết quả vào biến để tránh SIGPIPE khi dùng grep -q cùng pipefail)
# -----------------------------------------------------------------------------
listening="$(sudo ss -tlnp)"
if grep -Eq ":${NEW_PORT}[[:space:]]" <<<"${listening}"; then
    log "Đã nghe trên cổng ${NEW_PORT}:"
    grep -E ":${NEW_PORT}[[:space:]]" <<<"${listening}"
else
    die "Không thấy tiến trình nào nghe cổng ${NEW_PORT}. Giữ phiên SSH hiện tại và kiểm tra: systemctl status ssh.socket ssh"
fi

# -----------------------------------------------------------------------------
# Hướng dẫn bước tiếp theo (script không tự thực hiện)
# -----------------------------------------------------------------------------
cat <<EOF

=============================================================================
HOÀN TẤT PHẦN CẤU HÌNH. CHƯA ĐÓNG CỔNG 22.

Việc cần làm tiếp theo:
  1. GIỮ NGUYÊN Terminal hiện tại. Mở một Terminal MỚI trên máy cá nhân:
       ssh -p ${NEW_PORT} -i <đường_dẫn_private_key> devops@<IP_máy_chủ>
  2. Chỉ khi đăng nhập thành công ở Terminal mới, đóng cổng cũ:
       sudo ufw delete allow 22/tcp
       sudo ufw status verbose
  3. Kiểm tra cổng 22 đã bị chặn (kỳ vọng: Connection timed out):
       ssh -p 22 devops@<IP_máy_chủ>

Nếu bị lockout: dùng console của nhà cung cấp, chạy
  sudo cp ${BACKUP} ${SSHD_CONFIG}
  sudo systemctl daemon-reload && sudo systemctl restart ssh.socket ssh
=============================================================================
EOF
