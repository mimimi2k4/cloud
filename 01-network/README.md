# 🔧 Giai đoạn 1 – Hướng dẫn Chi tiết: Network + Linux (Ngày 1–5)

> **Mục tiêu cuối giai đoạn:**
> - VM2 và VM3 nhận IP qua DHCP, ping được 8.8.8.8 qua VM1
> - Firewall chặn đúng: LAN chỉ được vào DMZ qua port 80/443
> - SSH vào VM1 bằng key, không dùng password
> - Chụp được ảnh gói tin DHCP, DNS, TCP handshake bằng Wireshark

---

## 📋 Ngày 1 – Tạo VMware Network & Cài VM1

### Bước 1.1 – Tạo 2 Host-only network trong VMware

1. Mở **VMware Workstation** → menu **Edit** → **Virtual Network Editor**
2. Click **"Change Settings"** (cần quyền Admin)
3. Click **"Add Network"** → chọn **vmnet2**:
   - Type: **Host-only**
   - Subnet IP: `10.10.10.0`
   - Subnet mask: `255.255.255.0`
   - ❌ Bỏ tick "Use local DHCP" (ta tự dùng dnsmasq)
4. Click **"Add Network"** → chọn **vmnet3**:
   - Type: **Host-only**
   - Subnet IP: `10.10.20.0`
   - Subnet mask: `255.255.255.0`
   - ❌ Bỏ tick "Use local DHCP"
5. Click **OK** để lưu

> ✅ **Kiểm tra:** Vào Windows Control Panel → Network → bạn thấy "VMware Network Adapter VMnet2" và "VMnet3"

### Bước 1.2 – Tạo VM1 (Gateway/Firewall)

**Cấu hình VM:**
| Thông số | Giá trị |
|----------|---------|
| RAM | 1024 MB |
| vCPU | 1 |
| Disk | 20 GB |
| OS | Ubuntu Server 22.04 LTS |
| NIC 1 | NAT (WAN — ra Internet) |
| NIC 2 | vmnet2 (LAN 10.10.10.x) |
| NIC 3 | vmnet3 (DMZ 10.10.20.x) |

**Thêm NIC trong VMware:**
- VM Settings → Add → Network Adapter → vmnet2
- VM Settings → Add → Network Adapter → vmnet3

**Cài Ubuntu Server:**
- Download ISO: `ubuntu-22.04.x-live-server-amd64.iso`
- Khi cài: không cần cài OpenSSH (ta cài sau), chọn minimal
- Đặt hostname: `vm1-gateway`, username: `sysadmin`

### Bước 1.3 – Xác định tên interface sau khi cài

```bash
# Đăng nhập VM1, xem tên các interface
ip link show

# Output mẫu:
# 2: ens33: <BROADCAST,MULTICAST,UP,LOWER_UP> ...  ← NIC1 (NAT/WAN)
# 3: ens36: <BROADCAST,MULTICAST> ...               ← NIC2 (LAN)
# 4: ens38: <BROADCAST,MULTICAST> ...               ← NIC3 (DMZ)

# Xác nhận NIC nào là NAT (đã có IP từ VMware DHCP)
ip a show ens33
# Sẽ thấy IP dạng 192.168.x.x
```

> 📝 **Ghi lại tên interface thực tế của máy bạn** — có thể khác (`ens32`, `eth0`, v.v.)

---

## 📋 Ngày 2 – IP tĩnh (Netplan), Routing & NAT

### Bước 2.1 – Cấu hình IP tĩnh bằng Netplan

```bash
# Xem file netplan hiện tại
ls /etc/netplan/
# Thường là: 00-installer-config.yaml

# Backup file gốc
sudo cp /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.bak

# Chỉnh sửa
sudo nano /etc/netplan/00-installer-config.yaml
```

**Nội dung file `/etc/netplan/00-installer-config.yaml`:**

```yaml
network:
  version: 2
  ethernets:
    ens33:
      # WAN interface — lấy IP từ VMware NAT (DHCP)
      dhcp4: true

    ens36:
      # LAN interface — IP tĩnh cho subnet LAN
      dhcp4: false
      addresses:
        - 10.10.10.1/24

    ens38:
      # DMZ interface — IP tĩnh cho subnet DMZ
      dhcp4: false
      addresses:
        - 10.10.20.1/24
```

```bash
# Áp dụng cấu hình
sudo netplan apply

# Kiểm tra
ip addr show ens36    # phải thấy 10.10.10.1/24
ip addr show ens38    # phải thấy 10.10.20.1/24

# Kiểm tra routing table
ip route show
# Output mẫu:
# default via 192.168.x.1 dev ens33 (route ra Internet qua WAN)
# 10.10.10.0/24 dev ens36 proto kernel
# 10.10.20.0/24 dev ens38 proto kernel
```

### Bước 2.2 – Bật IP Forwarding (biến VM1 thành router)

```bash
# Bật tạm thời (mất khi reboot)
sudo sysctl -w net.ipv4.ip_forward=1

# Bật vĩnh viễn
sudo nano /etc/sysctl.conf
```

Tìm dòng `#net.ipv4.ip_forward=1`, bỏ dấu `#`:

```ini
# Uncomment the next line to enable packet forwarding for IPv4
net.ipv4.ip_forward=1
```

```bash
# Áp dụng
sudo sysctl -p

# Kiểm tra (kết quả phải là 1)
cat /proc/sys/net/ipv4/ip_forward
```

### Bước 2.3 – Cấu hình NAT bằng iptables

```bash
# Tạo script để dễ quản lý
sudo mkdir -p /etc/iptables
sudo nano /etc/iptables/rules.sh
```

**Nội dung `/etc/iptables/rules.sh`:**

```bash
#!/bin/bash
# ============================================================
# VM1 Gateway — iptables rules
# WAN: ens33 | LAN: ens36 (10.10.10.0/24) | DMZ: ens38 (10.10.20.0/24)
# ============================================================

WAN="ens33"
LAN="ens36"
DMZ="ens38"
LAN_NET="10.10.10.0/24"
DMZ_NET="10.10.20.0/24"

# ── Flush all existing rules ──────────────────────────────────
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

# ── Default policies ──────────────────────────────────────────
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# ── Loopback ─────────────────────────────────────────────────
iptables -A INPUT -i lo -j ACCEPT

# ── Allow established/related connections ─────────────────────
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# ── SSH vào VM1 từ LAN (để admin) ────────────────────────────
iptables -A INPUT -i $LAN -p tcp --dport 22 -j ACCEPT

# ── ICMP ping (debug) ─────────────────────────────────────────
iptables -A INPUT -p icmp -j ACCEPT
iptables -A FORWARD -p icmp -j ACCEPT

# ── NAT: Masquerade LAN và DMZ ra Internet qua WAN ───────────
iptables -t nat -A POSTROUTING -s $LAN_NET -o $WAN -j MASQUERADE
iptables -t nat -A POSTROUTING -s $DMZ_NET -o $WAN -j MASQUERADE

# ── FORWARD: LAN → Internet ──────────────────────────────────
iptables -A FORWARD -i $LAN -o $WAN -j ACCEPT

# ── FORWARD: DMZ → Internet ──────────────────────────────────
iptables -A FORWARD -i $DMZ -o $WAN -j ACCEPT

# ── FORWARD: LAN → DMZ (chỉ port 80 và 443) ─────────────────
iptables -A FORWARD -i $LAN -o $DMZ -p tcp --dport 80 -j ACCEPT
iptables -A FORWARD -i $LAN -o $DMZ -p tcp --dport 443 -j ACCEPT

# ── DHCP: VM1 nhận request DHCP từ LAN và DMZ ────────────────
iptables -A INPUT -i $LAN -p udp --dport 67 -j ACCEPT
iptables -A INPUT -i $DMZ -p udp --dport 67 -j ACCEPT

# ── DNS: VM1 phục vụ DNS cho LAN và DMZ ──────────────────────
iptables -A INPUT -i $LAN -p udp --dport 53 -j ACCEPT
iptables -A INPUT -i $LAN -p tcp --dport 53 -j ACCEPT
iptables -A INPUT -i $DMZ -p udp --dport 53 -j ACCEPT
iptables -A INPUT -i $DMZ -p tcp --dport 53 -j ACCEPT

echo "✅ iptables rules applied successfully"
iptables -L -n -v --line-numbers
```

```bash
# Cấp quyền thực thi và chạy
sudo chmod +x /etc/iptables/rules.sh
sudo bash /etc/iptables/rules.sh

# Lưu rules để tự động load khi reboot (file iptables-rules.sh trong repo đã có sẵn rule cho port 9100 của node_exporter)
sudo apt install iptables-persistent -y
sudo netfilter-persistent save

# Kiểm tra NAT table
sudo iptables -t nat -L -n -v
```

### Bước 2.4 – Cài và cấu hình dnsmasq

```bash
sudo apt update
sudo apt install dnsmasq -y

# Backup config gốc
sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.bak

sudo nano /etc/dnsmasq.conf
```

**Nội dung `/etc/dnsmasq.conf`:**

```ini
# ============================================================
# dnsmasq config — VM1 Gateway
# ============================================================

interface=ens36
interface=ens38
bind-interfaces

# ── DNS ──────────────────────────────────────────────────────
server=8.8.8.8
server=1.1.1.1
domain=lab.local
local=/lab.local/

# A records nội bộ
address=/gateway.lab.local/10.10.10.1
address=/vm1.lab.local/10.10.10.1
address=/monitoring.lab.local/10.10.10.10
address=/vm3.lab.local/10.10.10.10
address=/web.lab.local/10.10.20.10
address=/vm2.lab.local/10.10.20.10

# ── DHCP cho LAN (vmnet2) ─────────────────────────────────────
dhcp-range=ens36,10.10.10.100,10.10.10.200,255.255.255.0,12h
dhcp-option=ens36,3,10.10.10.1
dhcp-option=ens36,6,10.10.10.1

# ── DHCP cho DMZ (vmnet3) ─────────────────────────────────────
dhcp-range=ens38,10.10.20.100,10.10.20.200,255.255.255.0,12h
dhcp-option=ens38,3,10.10.20.1
dhcp-option=ens38,6,10.10.20.1

dhcp-leasefile=/var/lib/misc/dnsmasq.leases
log-queries
log-facility=/var/log/dnsmasq.log
```

```bash
sudo systemctl restart dnsmasq
sudo systemctl enable dnsmasq
sudo systemctl status dnsmasq
```

> ⚠️ **Lỗi thường gặp — systemd-resolved chiếm port 53:**
> ```bash
> sudo systemctl disable systemd-resolved
> sudo systemctl stop systemd-resolved
> sudo rm /etc/resolv.conf
> echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
> sudo systemctl restart dnsmasq
> ```

---

## 📋 Ngày 3 – SSH Hardening + fail2ban

### Bước 3.1 – Tạo SSH key pair (trên Windows Host)

```powershell
# Mở PowerShell trên Windows
ssh-keygen -t ed25519 -C "private-cloud-lab" -f "$env:USERPROFILE\.ssh\cloud-lab-key"

# Copy public key lên VM1
$pubkey = Get-Content "$env:USERPROFILE\.ssh\cloud-lab-key.pub"
ssh sysadmin@<IP_VM1> "mkdir -p ~/.ssh && echo '$pubkey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

# Test đăng nhập bằng key
ssh -i ~/.ssh/cloud-lab-key sysadmin@<IP_VM1>
```

### Bước 3.2 – Hardening sshd_config

```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
sudo nano /etc/ssh/sshd_config
```

> ✅ **Cách khuyên dùng:** thay vì sửa `sshd_config`, dùng file drop-in `sshd_hardening.conf` trong repo:
> ```bash
> sudo cp sshd_hardening.conf /etc/ssh/sshd_config.d/00-hardening.conf
> sudo sshd -t && sudo systemctl restart ssh
> ```
> Tên file phải bắt đầu bằng `00-`: OpenSSH lấy giá trị **đầu tiên** gặp được, và các file trong `sshd_config.d/` đọc theo thứ tự chữ cái, nên một file như `50-cloud-init.conf` (nếu có, đặt `PasswordAuthentication yes`) sẽ thắng file tên `99-`.

Hoặc sửa trực tiếp `sshd_config`, thay đổi/thêm các dòng sau:

```ini
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
AllowUsers sysadmin
LoginGraceTime 30
X11Forwarding no
```

```bash
# Kiểm tra config
sudo sshd -t

# Restart (giữ session cũ, mở terminal mới test trước!)
sudo systemctl restart ssh
```

### Bước 3.3 – fail2ban

```bash
sudo apt install fail2ban -y
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo nano /etc/fail2ban/jail.local
```

Trong `[DEFAULT]`:
```ini
maxretry = 5
findtime = 600
bantime  = 3600
ignoreip = 127.0.0.1/8
```

Trong `[sshd]`:
```ini
[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 5
```

```bash
sudo systemctl enable fail2ban
sudo systemctl restart fail2ban
sudo fail2ban-client status sshd
```

---

## 📋 Ngày 4 – Bắt gói tin

### Bắt DHCP

```bash
# Trên VM1
sudo tcpdump -i ens36 -n port 67 or port 68 -w /tmp/dhcp-capture.pcap

# Trên VM2/VM3 — trigger DHCP renew
sudo dhclient -r && sudo dhclient
```

### Bắt DNS

```bash
sudo tcpdump -i ens36 -n port 53 -w /tmp/dns-capture.pcap
# Từ VM2: dig web.lab.local @10.10.10.1
```

### Bắt TCP Handshake

```bash
# Trên VM1 interface DMZ
sudo tcpdump -i ens38 -n 'tcp[tcpflags] & (tcp-syn|tcp-fin) != 0' -w /tmp/tcp-capture.pcap
# Từ VM3: curl http://10.10.20.10/
```

### Copy pcap về Windows để mở Wireshark

```powershell
scp -i ~/.ssh/cloud-lab-key sysadmin@<IP_VM1>:/tmp/*.pcap C:\Users\<User>\Desktop\
```

---

## 📋 Ngày 5 – Checklist kiểm tra tổng thể

```bash
# ── VM1 ──────────────────────────────────────────────────────
ip addr show ens36    # 10.10.10.1/24 ✅
ip addr show ens38    # 10.10.20.1/24 ✅
cat /proc/sys/net/ipv4/ip_forward   # 1 ✅
sudo iptables -t nat -L POSTROUTING -n -v   # MASQUERADE rules ✅
sudo systemctl status dnsmasq   # active ✅
sudo systemctl status fail2ban  # active ✅

# ── VM2 (DMZ) ────────────────────────────────────────────────
ip addr        # 10.10.20.1xx ✅
ip route       # default via 10.10.20.1 ✅
ping -c 3 8.8.8.8   # OK ✅
dig gateway.lab.local @10.10.20.1   # 10.10.10.1 ✅

# ── VM3 (LAN) ────────────────────────────────────────────────
ip addr        # 10.10.10.1xx ✅
curl http://10.10.20.10/   # 200 OK ✅ (nếu VM2 có web)
nc -zv 10.10.20.10 22      # timeout/refused ✅ (bị firewall chặn)
```

---

## 🐛 Lỗi thường gặp

| Lỗi | Nguyên nhân | Cách sửa |
|-----|-------------|----------|
| `dnsmasq: failed to create listening socket for port 53` | systemd-resolved chiếm port 53 | `sudo systemctl disable --now systemd-resolved` |
| VM2 không nhận DHCP | dnsmasq sai interface name | Kiểm tra `ip link show`, sửa `interface=` trong dnsmasq.conf |
| Ping 8.8.8.8 từ VM2 thất bại | ip_forward=0 hoặc thiếu NAT rule | `cat /proc/sys/net/ipv4/ip_forward`; kiểm tra MASQUERADE |
| netplan apply lỗi | Lỗi indent YAML | Dùng space, không dùng tab; mỗi level 2 spaces |
| SSH lock out | Tắt password auth trước khi test key | Boot recovery mode, sửa sshd_config |
| iptables mất sau reboot | Chưa save | `sudo netfilter-persistent save` |

---

## 📸 Screenshots cần chụp

- [ ] VMware Virtual Network Editor (vmnet2 + vmnet3)
- [ ] `ip addr show` trên VM1 (3 IP đúng)
- [ ] Wireshark: DHCP Discover/Offer/Request/ACK
- [ ] Wireshark: TCP 3-way handshake (SYN, SYN-ACK, ACK)
- [ ] `sudo iptables -L -n -v` — đủ rules
- [ ] `ping 8.8.8.8` từ VM2 — success
- [ ] `sudo fail2ban-client status sshd` — active

---

*Hoàn thành Giai đoạn 1 → Sang [Giai đoạn 2](../02-services/)*
