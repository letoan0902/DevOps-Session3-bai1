# Bài 1 - Thay đổi cổng kết nối SSH (SSH Port Hardening)

Môn DevOps - Session 03 - Thực hiện ngày 2026-10-02 (thứ Sáu), khoảng 09:00 đến 09:40 (múi giờ +0700).

## 1. Thông tin môi trường

| Hạng mục | Giá trị |
|---|---|
| Máy chủ ảo | `halo` - Ubuntu 24.04.3 LTS, kernel 6.8.0-87-generic |
| Địa chỉ IP máy chủ | `103.116.104.228` |
| Phiên bản SSH server | OpenSSH 9.6p1 Ubuntu-3ubuntu13.14 |
| User thao tác | `devops` (uid 1001, thuộc nhóm `sudo`, sudo có hỏi mật khẩu) |
| Máy cá nhân | Windows, dùng Git Bash, IP công cộng `113.161.72.19` |
| Khóa đăng nhập | `~/.ssh/id_ed25519_ptit_s02` (Ed25519, đã nạp vào ssh-agent) |
| Firewall | UFW, mặc định `deny incoming` / `allow outgoing`; đầu bài cho phép `22/tcp` và `80/tcp` |

Toàn bộ thao tác trên máy chủ được thực hiện bằng user `devops` qua `sudo`, không đăng nhập hay chuyển sang root.
Log đầy đủ theo thứ tự thời gian nằm trong [terminal_log.txt](terminal_log.txt); các đoạn trích bên dưới lấy từ file đó.

## 2. Mục tiêu và ràng buộc

Mục tiêu: chuyển cổng SSH từ 22 sang 2222 để giảm lượng quét cổng và brute-force tự động, đồng thời không bị khóa khỏi máy chủ (lockout).

Ràng buộc đã tuân thủ:

1. Đặt `Port 2222` trong `/etc/ssh/sshd_config` (có nêu thêm phương án drop-in).
2. Dùng UFW mở `2222/tcp` TRƯỚC khi khởi động lại SSH daemon.
3. Chỉ thao tác bằng user `devops` có sudo.

Tiêu chí kiểm tra:

- `ssh -p 2222 devops@<IP>` thành công bằng SSH key.
- `ssh -p 22 devops@<IP>` bị chặn hoàn toàn.

## 3. Sơ đồ quy trình chống lockout

Nguyên tắc: luôn mở đường mới trước, kiểm chứng đường mới hoạt động, rồi mới đóng đường cũ.

```text
 [0] Giữ nguyên Terminal 1 (phiên SSH cũ qua cổng 22) trong suốt quá trình
        |
 [1] Sao lưu /etc/ssh/sshd_config
        |
 [2] sudo ufw allow 2222/tcp          <-- mở tường lửa TRƯỚC
        |
 [3] Sửa "Port 2222" trong sshd_config
        |
 [4] sudo sshd -t                     (lỗi cú pháp -> dừng, KHÔNG restart)
        |
 [5] daemon-reload -> restart ssh.socket -> restart ssh
        |
 [6] Mở Terminal 2 MỚI: ssh -p 2222 ...
        |
        +-- thất bại -> sửa lỗi bằng Terminal 1 (vẫn còn sống), quay lại [3]
        |
        +-- thành công
        |
 [7] sudo ufw delete allow 22/tcp     <-- đóng cổng cũ SAU CÙNG
        |
 [8] Kiểm tra: cổng 22 timeout, cổng 2222 vào được
```

## 4. Các bước thực hiện

### Bước 0. Kết nối phiên SSH đầu tiên (Terminal 1) và giữ nguyên

Lúc 09:02 tôi đăng nhập vào máy chủ qua cổng 22 bằng key. Phiên này (pts/0) được giữ mở đến hết bài, làm đường lui nếu cấu hình mới có sự cố.

```text
$ ssh -i ~/.ssh/id_ed25519_ptit_s02 devops@103.116.104.228
Welcome to Ubuntu 24.04.3 LTS (GNU/Linux 6.8.0-87-generic x86_64)
...
Last login: Thu Oct  1 20:47:33 2026 from 113.161.72.19
devops@halo:~$ echo $SSH_CONNECTION
113.161.72.19 51406 103.116.104.228 22
```

Biến `SSH_CONNECTION` có dạng `<IP client> <port client> <IP server> <port server>`; giá trị cuối là `22` xác nhận phiên này đi qua cổng 22.

### Bước 1. Lý do đổi cổng: brute-force trên cổng 22

Ngay khi máy chủ có IP công cộng, cổng 22 bị dò mật khẩu liên tục. Tôi kiểm tra `/var/log/auth.log`:

```text
devops@halo:~$ sudo grep "Failed password\|Invalid user" /var/log/auth.log | tail
2026-10-02T09:03:58.114920+07:00 halo sshd[2611]: Invalid user admin from 185.224.128.17 port 40218
2026-10-02T09:03:59.882047+07:00 halo sshd[2611]: Failed password for invalid user admin from 185.224.128.17 port 40218 ssh2
2026-10-02T09:04:07.360518+07:00 halo sshd[2618]: Failed password for root from 45.141.84.213 port 33876 ssh2
2026-10-02T09:04:12.771203+07:00 halo sshd[2623]: Invalid user ubuntu from 91.92.241.66 port 51320
2026-10-02T09:04:14.205689+07:00 halo sshd[2623]: Failed password for invalid user ubuntu from 91.92.241.66 port 51320 ssh2
2026-10-02T09:04:19.640371+07:00 halo sshd[2629]: Invalid user oracle from 178.128.90.14 port 47102
2026-10-02T09:04:21.018934+07:00 halo sshd[2629]: Failed password for invalid user oracle from 178.128.90.14 port 47102 ssh2
2026-10-02T09:04:25.493160+07:00 halo sshd[2634]: Failed password for root from 103.145.12.88 port 59644 ssh2
2026-10-02T09:04:30.927745+07:00 halo sshd[2640]: Invalid user test from 185.224.128.17 port 40390
2026-10-02T09:04:32.349018+07:00 halo sshd[2640]: Failed password for invalid user test from 185.224.128.17 port 40390 ssh2
```

Thống kê trong `auth.log` hiện tại:

```text
devops@halo:~$ sudo grep -c "Failed password" /var/log/auth.log
6218
devops@halo:~$ sudo grep -c "Invalid user" /var/log/auth.log
3187
devops@halo:~$ sudo grep "Failed password" /var/log/auth.log | grep -oE "from [0-9]{1,3}(\.[0-9]{1,3}){3}" | sort -u | wc -l
97
devops@halo:~$ sudo grep "Failed password" /var/log/auth.log | grep -oE "from [0-9]{1,3}(\.[0-9]{1,3}){3}" | sort | uniq -c | sort -rn | head -5
   1344 from 185.224.128.17
    987 from 45.141.84.213
    802 from 91.92.241.66
    655 from 178.128.90.14
    419 from 103.145.12.88
```

Nhận xét:

- Có 6218 lần `Failed password` và 3187 lần `Invalid user` từ 97 địa chỉ IP khác nhau.
- Các tên tài khoản bị thử là loại phổ biến: `root`, `admin`, `ubuntu`, `oracle`, `test`. Đây là dấu hiệu của botnet quét tự động.
- Cứ vài giây lại có một lần thử mới, nên log bị nhiễu và tài nguyên bị tiêu tốn vô ích.

Về bản chất, đổi cổng là biện pháp giảm nhiễu (security through obscurity): bot chỉ quét cổng 22 mặc định sẽ không thấy dịch vụ. Một kẻ tấn công chủ động vẫn có thể quét toàn bộ dải cổng bằng `nmap -p-` và tìm ra 2222. Vì vậy đổi cổng KHÔNG thay thế các lớp bảo vệ thật sự:

- Xác thực bằng SSH key và tắt xác thực mật khẩu (`PasswordAuthentication no`) - khuyến nghị triển khai tiếp ở bước hardening riêng, không thuộc phạm vi bài này. Log `Failed password` ở trên cho thấy máy chủ hiện vẫn chấp nhận mật khẩu.
- `fail2ban` (hoặc cơ chế tương đương) để tự động chặn IP thử sai nhiều lần.
- Tường lửa chỉ cho phép các nguồn cần thiết.

### Bước 2. Kiểm tra hiện trạng và sao lưu

```text
devops@halo:~$ sudo ss -tlnp | grep sshd
LISTEN 0      4096         0.0.0.0:22         0.0.0.0:*    users:(("sshd",pid=1184,fd=3),("systemd",pid=1,fd=71))
LISTEN 0      4096            [::]:22            [::]:*    users:(("sshd",pid=1184,fd=4),("systemd",pid=1,fd=72))
devops@halo:~$ sudo sshd -T | grep -i "^port"
port 22
devops@halo:~$ sudo grep -rn "Port" /etc/ssh/sshd_config.d/ || echo "(không có chỉ thị Port nào trong drop-in)"
(không có chỉ thị Port nào trong drop-in)
devops@halo:~$ sudo ufw status verbose
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), disabled (routed)
New profiles: skip

To                         Action      From
--                         ------      ----
22/tcp                     ALLOW IN    Anywhere
80/tcp                     ALLOW IN    Anywhere
22/tcp (v6)                ALLOW IN    Anywhere (v6)
80/tcp (v6)                ALLOW IN    Anywhere (v6)
```

Giải thích:

- `sshd` đang nghe `0.0.0.0:22` (IPv4) và `[::]:22` (IPv6). Cột `users` có cả `sshd` và `systemd` (pid 1) vì socket được chia sẻ giữa hai tiến trình - dấu hiệu của socket activation, sẽ nói ở Bước 3d.
- `sshd -T` in cấu hình hiệu lực mà sshd thực sự dùng (đã gộp cả các tệp `Include`), nên đáng tin hơn là chỉ đọc file bằng mắt.
- Thư mục drop-in `/etc/ssh/sshd_config.d/` không có chỉ thị `Port`, nên không có xung đột.
- UFW đang `active`, chỉ cho `22/tcp` và `80/tcp`. Do mặc định `deny incoming`, mọi cổng khác (kể cả 2222) đang bị chặn.

Sao lưu cấu hình trước khi sửa:

```text
devops@halo:~$ sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak-20261002
devops@halo:~$ ls -l /etc/ssh/sshd_config*
-rw-r--r-- 1 root root 3266 Sep 25 10:41 /etc/ssh/sshd_config
-rw-r--r-- 1 root root 3266 Oct  2 09:08 /etc/ssh/sshd_config.bak-20261002
```

### Bước 3. Thực hiện đổi cổng (theo đúng thứ tự chống lockout)

#### 3a. Mở cổng 2222 trên UFW TRƯỚC

Nếu đổi cổng và restart trước khi mở UFW, gói tin tới cổng 2222 sẽ bị `deny incoming` loại bỏ; cổng 22 thì sshd không còn nghe. Kết quả là không còn đường nào vào máy chủ. Vì vậy phải mở UFW trước:

```text
devops@halo:~$ sudo ufw allow 2222/tcp
Rule added
Rule added (v6)
devops@halo:~$ sudo ufw status numbered
Status: active

     To                         Action      From
     --                         ------      ----
[ 1] 22/tcp                     ALLOW IN    Anywhere
[ 2] 80/tcp                     ALLOW IN    Anywhere
[ 3] 2222/tcp                   ALLOW IN    Anywhere
[ 4] 22/tcp (v6)                ALLOW IN    Anywhere (v6)
[ 5] 80/tcp (v6)                ALLOW IN    Anywhere (v6)
[ 6] 2222/tcp (v6)              ALLOW IN    Anywhere (v6)
```

Lúc này cả 22 và 2222 cùng được phép, nên chưa có rủi ro nào cho phiên hiện tại.

#### 3b. Sửa `Port 2222` trong `/etc/ssh/sshd_config`

Xem trạng thái trước khi sửa:

```text
devops@halo:~$ grep -n "^Port\|^#Port" /etc/ssh/sshd_config
15:#Port 22
```

Cách 1 - dùng nano (cách tôi đã làm):

```bash
sudo nano /etc/ssh/sshd_config
# Ctrl+W tìm "#Port 22" -> xóa dấu "#" và đổi 22 thành 2222
# Ctrl+O, Enter để lưu; Ctrl+X để thoát
```

Cách 2 - lệnh `sed` tương đương, tiện cho script hoặc khi không muốn mở trình soạn thảo:

```bash
sudo sed -i 's/^#Port 22$/Port 2222/' /etc/ssh/sshd_config
```

Kiểm tra sau khi sửa và đối chiếu với bản sao lưu:

```text
devops@halo:~$ grep -n "^Port\|^#Port" /etc/ssh/sshd_config
15:Port 2222
devops@halo:~$ diff /etc/ssh/sshd_config.bak-20261002 /etc/ssh/sshd_config
15c15
< #Port 22
---
> Port 2222
devops@halo:~$ ls -l /etc/ssh/sshd_config
-rw-r--r-- 1 root root 3267 Oct  2 09:13 /etc/ssh/sshd_config
```

Chỉ đúng một dòng thay đổi; quyền file vẫn là `-rw-r--r-- root root`.

Phương án drop-in (không sửa file chính): tạo `/etc/ssh/sshd_config.d/10-port.conf` chỉ chứa một dòng `Port 2222`:

```bash
echo "Port 2222" | sudo tee /etc/ssh/sshd_config.d/10-port.conf
```

Ưu điểm: nâng cấp gói `openssh-server` không đụng tới file của mình, và dễ gỡ bỏ (xóa file là xong). Lưu ý: `sshd_config` của Ubuntu có `Include /etc/ssh/sshd_config.d/*.conf` ở đầu file và sshd lấy giá trị đọc ĐẦU TIÊN, nên drop-in có độ ưu tiên cao hơn file chính. Không nên khai báo `Port` khác nhau ở hai nơi. Bài này tôi chọn sửa file chính theo đúng gợi ý của đề; mẫu cả hai cách có trong [sshd_config.snippet](sshd_config.snippet).

#### 3c. Kiểm tra cú pháp trước khi khởi động lại

```text
devops@halo:~$ sudo sshd -t
devops@halo:~$ echo $?
0
devops@halo:~$ sudo sshd -T | grep -i "^port"
port 2222
```

`sshd -t` không in gì và trả mã `0` nghĩa là cấu hình hợp lệ. Nếu có lỗi cú pháp thì phải sửa ngay, tuyệt đối không restart, vì sshd không khởi động được sẽ khiến mọi phiên mới bị từ chối.

Ngay sau khi sửa file, tiến trình vẫn đang nghe cổng cũ - sửa file chưa có tác dụng cho tới khi áp dụng lại:

```text
devops@halo:~$ sudo ss -tlnp | grep sshd
LISTEN 0      4096         0.0.0.0:22         0.0.0.0:*    users:(("sshd",pid=1184,fd=3),("systemd",pid=1,fd=71))
LISTEN 0      4096            [::]:22            [::]:*    users:(("sshd",pid=1184,fd=4),("systemd",pid=1,fd=72))
```

#### 3d. Lưu ý riêng của Ubuntu 22.10 trở lên và 24.04: socket activation (`ssh.socket`)

Từ Ubuntu 22.10, OpenSSH được chạy theo kiểu systemd socket activation: unit `ssh.socket` mở sẵn cổng và chuyển socket cho `ssh.service`. Hệ quả:

- Cổng đang nghe do `ssh.socket` quyết định, không phải một mình dịch vụ `ssh`.
- Nếu chỉ chạy `systemctl restart ssh`, socket vẫn nghe cổng cũ (22), dù `sshd_config` đã ghi 2222. Đây là lý do `ss` ở trên vẫn thấy cổng 22.
- Với Ubuntu 24.04 (gói openssh bản cập nhật gần đây), bộ sinh cấu hình `sshd-socket-generator` đọc `Port` trong `sshd_config` và tạo drop-in cho `ssh.socket` mỗi lần `daemon-reload`. Vì vậy trình tự đúng là: `daemon-reload` -> restart `ssh.socket` -> restart `ssh`.

```text
devops@halo:~$ sudo systemctl daemon-reload
devops@halo:~$ sudo systemctl restart ssh.socket
devops@halo:~$ sudo systemctl restart ssh
devops@halo:~$ cat /run/systemd/generator/ssh.socket.d/addr.conf
# Automatically generated by sshd-socket-generator

[Socket]
ListenStream=
ListenStream=0.0.0.0:2222
ListenStream=[::]:2222
```

Trạng thái `ssh.socket` (tôi thêm `--ascii` để hệ thống in ký tự ASCII thay cho ký hiệu đồ họa):

```text
devops@halo:~$ systemctl --no-pager --ascii status ssh.socket
* ssh.socket - OpenBSD Secure Shell server socket
     Loaded: loaded (/usr/lib/systemd/system/ssh.socket; enabled; preset: enabled)
    Drop-In: /run/systemd/generator/ssh.socket.d
             `-addr.conf
     Active: active (listening) since Fri 2026-10-02 09:16:41 +07; 11s ago
   Triggers: * ssh.service
     Listen: 0.0.0.0:2222 (Stream)
             [::]:2222 (Stream)
      Tasks: 0 (limit: 4543)
     Memory: 8.0K (peak: 512.0K)
        CPU: 3ms
     CGroup: /system.slice/ssh.socket
```

Hai dòng `Listen:` xác nhận socket đã nghe `0.0.0.0:2222` và `[::]:2222`. Trạng thái `ssh.service`:

```text
devops@halo:~$ systemctl --no-pager --ascii status ssh
* ssh.service - OpenBSD Secure Shell server
     Loaded: loaded (/usr/lib/systemd/system/ssh.service; disabled; preset: enabled)
     Active: active (running) since Fri 2026-10-02 09:16:44 +07; 25s ago
TriggeredBy: * ssh.socket
    Process: 2925 ExecStartPre=/usr/sbin/sshd -t (code=exited, status=0/SUCCESS)
   Main PID: 2927 (sshd)
     CGroup: /system.slice/ssh.service
             |-2288 "sshd: devops [priv]"
             `-2927 "sshd: /usr/sbin/sshd -D [listener] 0 of 10-100 startups"

Oct 02 09:16:44 halo sshd[2927]: Server listening on 0.0.0.0 port 2222.
Oct 02 09:16:44 halo sshd[2927]: Server listening on :: port 2222.
```

Giải thích:

- `ssh.service` hiển thị `disabled` là bình thường khi dùng socket activation: dịch vụ được kích hoạt qua `TriggeredBy: ssh.socket`.
- Tiến trình `sshd: devops [priv]` (pid 2288) là của phiên Terminal 1, vẫn còn nguyên sau khi restart: kết nối đang mở không bị ngắt.

Kiểm tra tiến trình đang nghe:

```text
devops@halo:~$ sudo ss -tlnp | grep 2222
LISTEN 0      4096         0.0.0.0:2222       0.0.0.0:*    users:(("sshd",pid=2927,fd=3),("systemd",pid=1,fd=79))
LISTEN 0      4096            [::]:2222          [::]:*    users:(("sshd",pid=2927,fd=4),("systemd",pid=1,fd=80))
devops@halo:~$ sudo ss -tlnp | grep -c ':22 '
0
```

Cổng 2222 đã được nghe và không còn socket nào nghe cổng 22 (đếm được `0`).

Nếu phiên bản gói chưa có bộ sinh cấu hình thì `daemon-reload` không tự đổi cổng của socket. Khi đó có hai cách:

```bash
# Cách A: ghi đè ListenStream cho ssh.socket
sudo systemctl edit ssh.socket
#   [Socket]
#   ListenStream=
#   ListenStream=0.0.0.0:2222
#   ListenStream=[::]:2222
sudo systemctl daemon-reload && sudo systemctl restart ssh.socket

# Cách B: quay về kiểu chạy cổ điển, không dùng socket activation
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
```

Phiên bản trên máy chủ của tôi đã hoạt động đúng bằng trình tự `daemon-reload` -> `ssh.socket` -> `ssh`, nên không cần đến hai cách này.

Lấy fingerprint host key của máy chủ để đối chiếu khi kết nối lần đầu qua cổng mới:

```text
devops@halo:~$ ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
256 SHA256:n8Qx3VwK0dRfT7yJbLm2HcAe9uZsPo5GtYiN4XkWq1E root@halo (ED25519)
```

### Bước 4. Giữ phiên cũ, mở Terminal MỚI để kiểm tra cổng 2222

Terminal 1 không được đóng. Tôi mở thêm một cửa sổ Git Bash mới (Terminal 2) và kết nối qua cổng mới:

```text
$ ssh -p 2222 -i ~/.ssh/id_ed25519_ptit_s02 devops@103.116.104.228
The authenticity of host '[103.116.104.228]:2222 ([103.116.104.228]:2222)' can't be established.
ED25519 key fingerprint is SHA256:n8Qx3VwK0dRfT7yJbLm2HcAe9uZsPo5GtYiN4XkWq1E.
This key is not known by any other names.
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added '[103.116.104.228]:2222' (ED25519) to the list of known hosts.
Welcome to Ubuntu 24.04.3 LTS (GNU/Linux 6.8.0-87-generic x86_64)
...
Last login: Fri Oct  2 09:02:11 2026 from 113.161.72.19
devops@halo:~$
```

Điểm cần chú ý:

- Thông báo `authenticity of host '[103.116.104.228]:2222'` xuất hiện vì `known_hosts` lưu host key theo cặp "host + cổng"; mục của cổng 22 và cổng 2222 là hai mục riêng. Fingerprint hiển thị trùng với fingerprint tôi lấy trên máy chủ ở Bước 3d, nên tôi gõ `yes`.
- Banner `Welcome to Ubuntu 24.04.3 LTS` và dòng `Last login` (đúng thời điểm đăng nhập đầu tiên lúc 09:02:11) cho thấy đăng nhập thành công.

Xác nhận phiên mới đi qua cổng 2222 và xác thực bằng publickey:

```text
devops@halo:~$ echo $SSH_CONNECTION
113.161.72.19 51872 103.116.104.228 2222
devops@halo:~$ who
devops   pts/0        2026-10-02 09:02 (113.161.72.19)
devops   pts/1        2026-10-02 09:18 (113.161.72.19)
devops@halo:~$ sudo grep "Accepted publickey" /var/log/auth.log | tail -n 2
2026-10-02T09:02:11.482310+07:00 halo sshd[2288]: Accepted publickey for devops from 113.161.72.19 port 51406 ssh2: ED25519 SHA256:Vb2LxQ8dT5mRjH0wYk7NzAe4cUo1PgS9iFtXn6DuMsE
2026-10-02T09:18:36.907154+07:00 halo sshd[2958]: Accepted publickey for devops from 113.161.72.19 port 51872 ssh2: ED25519 SHA256:Vb2LxQ8dT5mRjH0wYk7NzAe4cUo1PgS9iFtXn6DuMsE
```

`who` thấy hai phiên cùng lúc (`pts/0` qua cổng 22, `pts/1` qua cổng 2222). Cổng cuối của `SSH_CONNECTION` là `2222` và `auth.log` ghi `Accepted publickey` cho phiên mới.

### Bước 5. Chỉ sau khi cổng 2222 hoạt động mới đóng cổng 22

Thực hiện ngay trong Terminal 2 (phiên đã vào qua cổng mới), nên dù có sự cố với rule thì Terminal 1 vẫn là đường lui.

```text
devops@halo:~$ sudo ufw status numbered
Status: active

     To                         Action      From
     --                         ------      ----
[ 1] 22/tcp                     ALLOW IN    Anywhere
[ 2] 80/tcp                     ALLOW IN    Anywhere
[ 3] 2222/tcp                   ALLOW IN    Anywhere
[ 4] 22/tcp (v6)                ALLOW IN    Anywhere (v6)
[ 5] 80/tcp (v6)                ALLOW IN    Anywhere (v6)
[ 6] 2222/tcp (v6)              ALLOW IN    Anywhere (v6)
devops@halo:~$ sudo ufw delete allow 22/tcp
Rule deleted
Rule deleted (v6)
devops@halo:~$ sudo ufw status numbered
Status: active

     To                         Action      From
     --                         ------      ----
[ 1] 80/tcp                     ALLOW IN    Anywhere
[ 2] 2222/tcp                   ALLOW IN    Anywhere
[ 3] 80/tcp (v6)                ALLOW IN    Anywhere (v6)
[ 4] 2222/tcp (v6)              ALLOW IN    Anywhere (v6)
```

Kết quả `sudo ufw status verbose` cuối cùng:

```text
devops@halo:~$ sudo ufw status verbose
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), disabled (routed)
New profiles: skip

To                         Action      From
--                         ------      ----
80/tcp                     ALLOW IN    Anywhere
2222/tcp                   ALLOW IN    Anywhere
80/tcp (v6)                ALLOW IN    Anywhere (v6)
2222/tcp (v6)              ALLOW IN    Anywhere (v6)
```

Chỉ còn `2222/tcp` (SSH) và `80/tcp` (web do nginx phục vụ) được mở cho cả IPv4 và IPv6. Rule của cổng 80 không bị ảnh hưởng.

### Bước 6. Kiểm tra cổng 22 bị chặn hoàn toàn

Từ máy cá nhân (Terminal 3):

```text
$ time ssh -p 22 devops@103.116.104.228
ssh: connect to host 103.116.104.228 port 22: Connection timed out

real    0m21.142s
user    0m0.000s
sys     0m0.015s
```

Kết nối không nhận được bất kỳ phản hồi nào và hết thời gian chờ sau khoảng 21 giây: đúng yêu cầu "bị chặn hoàn toàn". Bằng chứng ở phía máy chủ - UFW ghi nhận các gói SYN bị chặn:

```text
devops@halo:~$ sudo grep "DPT=22 " /var/log/ufw.log | tail -n 3
2026-10-02T09:25:34.215903+07:00 halo kernel: [359871.204516] [UFW BLOCK] IN=eth0 OUT= MAC=fa:16:3e:5b:2c:91:fa:16:3e:a0:77:d4:08:00 SRC=113.161.72.19 DST=103.116.104.228 LEN=52 TOS=0x00 PREC=0x00 TTL=114 ID=20931 DF PROTO=TCP SPT=51990 DPT=22 WINDOW=64240 RES=0x00 SYN URGP=0
2026-10-02T09:25:37.224471+07:00 halo kernel: [359874.213012] [UFW BLOCK] IN=eth0 OUT= MAC=fa:16:3e:5b:2c:91:fa:16:3e:a0:77:d4:08:00 SRC=113.161.72.19 DST=103.116.104.228 LEN=52 TOS=0x00 PREC=0x00 TTL=114 ID=20944 DF PROTO=TCP SPT=51990 DPT=22 WINDOW=64240 RES=0x00 SYN URGP=0
2026-10-02T09:25:43.236098+07:00 halo kernel: [359880.224733] [UFW BLOCK] IN=eth0 OUT= MAC=fa:16:3e:5b:2c:91:fa:16:3e:a0:77:d4:08:00 SRC=113.161.72.19 DST=103.116.104.228 LEN=52 TOS=0x00 PREC=0x00 TTL=114 ID=20987 DF PROTO=TCP SPT=51990 DPT=22 WINDOW=64240 RES=0x00 SYN URGP=0
```

Ba gói SYN cùng cổng nguồn `SPT=51990`, cách nhau khoảng 3 giây và 6 giây (client gửi lại gói SYN), đều bị `[UFW BLOCK]`. Đây là cơ chế sinh ra thông báo `Connection timed out`.

Phân biệt `Connection timed out` và `Connection refused`:

| Hiện tượng | Nguyên nhân | Trường hợp áp dụng |
|---|---|---|
| `Connection timed out` | Gói SYN bị tường lửa loại bỏ (DROP) nên client không nhận được gì | UFW `deny incoming` hoặc Cloud Firewall của nhà cung cấp chặn cổng. Đây là kết quả của bài này |
| `Connection refused` | Gói SYN tới được máy chủ nhưng không có tiến trình nào nghe cổng đó, nên hệ điều hành trả gói RST | Cổng không có rule chặn (hoặc rule `allow`) nhưng sshd đã ngừng nghe. Ví dụ: để lại rule `allow 22/tcp` rồi đổi cổng |

Cả hai kết quả đều thỏa yêu cầu "bị chặn hoàn toàn". Timeout còn có lợi thế là bot không biết cổng đó có tồn tại hay không.

Ngoài ra, Terminal 1 (phiên cũ qua cổng 22) vẫn hoạt động sau khi xóa rule. Lý do là UFW cho phép các gói thuộc kết nối đã thiết lập (`ESTABLISHED`) đi qua; chỉ kết nối MỚI tới cổng 22 mới bị chặn. Đây cũng là lý do rất nên đóng Terminal cũ sau khi hoàn tất.

### Bước 7. Chứng minh xác thực bằng publickey (`ssh -v`)

```text
$ ssh -v -p 2222 -i ~/.ssh/id_ed25519_ptit_s02 devops@103.116.104.228 exit 2>&1 | grep -E "^OpenSSH|Remote protocol|Server host key|is known and matches|Authentications that can continue|Next authentication method|Offering public key|Server accepts key|^Authenticated to|Sending command|^Transferred"
OpenSSH_9.8p1, OpenSSL 3.2.2 4 Jun 2024
debug1: Remote protocol version 2.0, remote software version OpenSSH_9.6p1 Ubuntu-3ubuntu13.14
debug1: Server host key: ssh-ed25519 SHA256:n8Qx3VwK0dRfT7yJbLm2HcAe9uZsPo5GtYiN4XkWq1E
debug1: Host '[103.116.104.228]:2222' is known and matches the ED25519 host key.
debug1: Authentications that can continue: publickey,password
debug1: Next authentication method: publickey
debug1: Offering public key: /c/Users/gigabyte/.ssh/id_ed25519_ptit_s02 ED25519 SHA256:Vb2LxQ8dT5mRjH0wYk7NzAe4cUo1PgS9iFtXn6DuMsE explicit agent
debug1: Server accepts key: /c/Users/gigabyte/.ssh/id_ed25519_ptit_s02 ED25519 SHA256:Vb2LxQ8dT5mRjH0wYk7NzAe4cUo1PgS9iFtXn6DuMsE explicit agent
Authenticated to 103.116.104.228 ([103.116.104.228]:2222) using "publickey".
debug1: Sending command: exit
Transferred: sent 3052, received 2124 bytes, in 0.4 seconds
```

Đọc kết quả:

- Server là OpenSSH 9.6p1 và host key trùng với fingerprint đã xác nhận (`is known and matches`), nên không bị tấn công trung gian.
- Client chào mời khóa công khai `id_ed25519_ptit_s02`, server chấp nhận (`Server accepts key`) và dòng cuối `Authenticated ... using "publickey"` chứng tỏ đăng nhập bằng SSH key, không phải mật khẩu.
- Dòng `Authentications that can continue: publickey,password` cho thấy server vẫn còn cho phép mật khẩu. Việc tắt hẳn `PasswordAuthentication` là bước hardening riêng, không thuộc phạm vi bài này.

### Bước 8. Tiện ích: cấu hình `~/.ssh/config` trên máy cá nhân

Để không phải gõ `-p 2222 -i ...` mỗi lần, tôi thêm khối `Host` vào `~/.ssh/config` (mẫu đầy đủ: [ssh_config.sample](ssh_config.sample)):

```text
$ cat >> ~/.ssh/config <<'EOF'

Host ptit-halo
    HostName 103.116.104.228
    Port 2222
    User devops
    IdentityFile ~/.ssh/id_ed25519_ptit_s02
    IdentitiesOnly yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
EOF
$ chmod 600 ~/.ssh/config
$ ssh -G ptit-halo | grep -E "^(hostname|port|user|identityfile) "
hostname 103.116.104.228
port 2222
user devops
identityfile ~/.ssh/id_ed25519_ptit_s02
$ ssh ptit-halo
Welcome to Ubuntu 24.04.3 LTS (GNU/Linux 6.8.0-87-generic x86_64)
...
Last login: Fri Oct  2 09:18:36 2026 from 113.161.72.19
devops@halo:~$ hostname; echo $SSH_CONNECTION
halo
113.161.72.19 52077 103.116.104.228 2222
```

`ssh -G` in cấu hình hiệu lực mà ssh sẽ dùng cho alias `ptit-halo`, xác nhận cổng 2222. Từ đây chỉ cần gõ `ssh ptit-halo`.

Kiểm tra lần cuối ở Terminal 1 (phiên cũ vẫn sống qua kết nối đã thiết lập, `SSH_CONNECTION` còn cổng 22):

```text
devops@halo:~$ echo $SSH_CONNECTION
113.161.72.19 51406 103.116.104.228 22
devops@halo:~$ sudo sshd -T | grep -i "^port"
port 2222
devops@halo:~$ sudo ss -tlnp | grep sshd
LISTEN 0      4096         0.0.0.0:2222       0.0.0.0:*    users:(("sshd",pid=2927,fd=3),("systemd",pid=1,fd=79))
LISTEN 0      4096            [::]:2222          [::]:*    users:(("sshd",pid=2927,fd=4),("systemd",pid=1,fd=80))
```

## 5. Phương án khôi phục khi bị lockout

Tình huống: đã restart SSH nhưng không còn đăng nhập được, đồng thời Terminal cũ cũng đã đóng.

1. Đăng nhập vào console/VNC/serial của nhà cung cấp (không đi qua SSH), dùng user `devops` hoặc tài khoản khôi phục do nhà cung cấp cấp.
2. Khôi phục bản sao lưu cấu hình:

   ```bash
   sudo cp /etc/ssh/sshd_config.bak-20261002 /etc/ssh/sshd_config
   sudo sshd -t
   ```

3. Áp dụng lại cấu hình, đúng trình tự với socket activation:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl restart ssh.socket
   sudo systemctl restart ssh
   ```

4. Mở lại cổng 22 trên UFW nếu cần: `sudo ufw allow 22/tcp`.
5. Kiểm tra bằng `sudo ss -tlnp | grep sshd` rồi thử đăng nhập lại từ Terminal mới trước khi làm bất cứ điều gì khác.

Bảng xử lý sự cố thường gặp:

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| `ssh -p 2222` bị `Connection timed out` | Quên mở `2222/tcp` trên UFW | Dùng phiên cũ hoặc console: `sudo ufw allow 2222/tcp`, kiểm tra `sudo ufw status` |
| `ssh -p 2222` bị `Connection refused`, `ss` vẫn thấy cổng 22 | Quên `daemon-reload` hoặc chỉ restart `ssh.service`, `ssh.socket` vẫn nghe cổng cũ | `sudo systemctl daemon-reload && sudo systemctl restart ssh.socket && sudo systemctl restart ssh` |
| `ssh -p 2222` timeout dù UFW đã có rule | Cloud Firewall / Security Group của nhà cung cấp chưa mở 2222 | Vào bảng điều khiển của nhà cung cấp, thêm rule cho phép TCP 2222 (nguồn là IP của mình hoặc dải cần thiết) |
| `ss` hiện cả 22 và 2222 | Còn một dòng `Port 22` đang hoạt động ở file khác (drop-in) | `sudo sshd -T \| grep -i "^port"`, rồi `sudo grep -rn "^Port" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/` và sửa cho thống nhất |
| `sshd -t` báo lỗi | Sai cú pháp khi sửa | Sửa theo thông báo, hoặc khôi phục từ `.bak-20261002`; không restart khi chưa hết lỗi |
| Lo ngại SELinux chặn cổng mới | Chỉ gặp trên RHEL/CentOS/Fedora (cần `semanage port -a -t ssh_port_t`); Ubuntu dùng AppArmor và không chặn cổng SSH tùy chọn | Không cần thao tác trên Ubuntu |
| Cảnh báo `REMOTE HOST IDENTIFICATION HAS CHANGED` | Mục `known_hosts` cũ không khớp | Xác minh fingerprint trên máy chủ, rồi `ssh-keygen -R "[103.116.104.228]:2222"` |
| Đăng nhập được nhưng `Permission denied (publickey)` | Sai đường dẫn key hoặc quên `-i` khi dùng cổng mới | Dùng `-i ~/.ssh/id_ed25519_ptit_s02` hoặc alias `ssh ptit-halo` |

## 6. Kết quả cuối cùng

| Hạng mục | Trước | Sau |
|---|---|---|
| `sshd -T \| grep -i "^port"` | `port 22` | `port 2222` |
| Cổng nghe (`ss -tlnp`) | `0.0.0.0:22`, `[::]:22` | `0.0.0.0:2222`, `[::]:2222` |
| UFW | `22/tcp`, `80/tcp` | `2222/tcp`, `80/tcp` (cả IPv4 và IPv6) |
| `ssh -p 2222 devops@103.116.104.228` | Không khả dụng | Thành công bằng publickey |
| `ssh -p 22 devops@103.116.104.228` | Thành công | `Connection timed out` (UFW DROP) |

## 7. Kết luận

- Đã đổi cổng SSH từ 22 sang 2222 đúng thứ tự chống lockout: mở UFW trước, sửa cấu hình, kiểm tra cú pháp bằng `sshd -t`, áp dụng bằng `daemon-reload` -> `ssh.socket` -> `ssh`, kiểm chứng ở Terminal mới rồi mới đóng cổng 22.
- Điểm dễ sai nhất trên Ubuntu 24.04 là socket activation: chỉ restart `ssh.service` thì cổng không đổi. Cần restart cả `ssh.socket`.
- Đổi cổng chỉ giúp giảm nhiễu từ bot quét cổng 22 (6218 lần `Failed password` từ 97 IP trong log trước khi đổi). Nó không phải lớp bảo vệ chính; cần kết hợp xác thực bằng key, tắt mật khẩu, `fail2ban` và tường lửa theo nguyên tắc tối thiểu.

Bảng đối chiếu yêu cầu đề bài:

| Yêu cầu | Trạng thái | Minh chứng |
|---|---|---|
| Đặt `Port 2222` trong `/etc/ssh/sshd_config` (hoặc drop-in) | Đạt | Bước 3b: `grep -n`, `diff`, `sshd -T` -> `port 2222` |
| Mở `2222/tcp` bằng UFW TRƯỚC khi restart SSH | Đạt | Bước 3a (09:10) trước restart (09:16); `ufw status numbered` |
| Chỉ dùng user thường `devops` có sudo, không dùng root | Đạt | Prompt `devops@halo:~$`, các lệnh đặc quyền đều có `sudo` |
| `ssh -p 2222 devops@<IP>` thành công bằng SSH key | Đạt | Bước 4 và Bước 7: `Authenticated ... using "publickey"` |
| `ssh -p 22 devops@<IP>` bị chặn | Đạt | Bước 6: `Connection timed out`, log `[UFW BLOCK] ... DPT=22` |
| Không để lockout, giữ phiên cũ khi test | Đạt | Terminal 1 mở suốt bài; kiểm tra bằng Terminal 2 và 3 |
| README mô tả các bước kèm log terminal | Đạt | File này và [terminal_log.txt](terminal_log.txt) |

## 8. Danh sách file trong thư mục

| File | Nội dung |
|---|---|
| [README.md](README.md) | Báo cáo các bước cấu hình kèm đoạn trích log |
| [terminal_log.txt](terminal_log.txt) | Toàn bộ log phiên làm việc theo thứ tự thời gian |
| [harden_ssh_port.sh](harden_ssh_port.sh) | Script bash idempotent tự động hóa các bước 2-4 (không tự xóa rule cổng 22) |
| [sshd_config.snippet](sshd_config.snippet) | Đoạn cấu hình `sshd_config` liên quan sau khi sửa, kèm phương án drop-in |
| [ssh_config.sample](ssh_config.sample) | Mẫu `~/.ssh/config` trên máy cá nhân |
