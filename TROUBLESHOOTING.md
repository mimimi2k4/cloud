# Troubleshooting Log — Private Cloud Lab

> Nhật ký ghi lại **tất cả lỗi gặp phải** và cách khắc phục trong quá trình xây dựng lab từ Ngày 1 đến Ngày 14.
> Tài liệu thể hiện tư duy phân tích nguyên nhân gốc rễ (Root Cause Analysis) và kỹ năng debug hệ thống thực tế.


---

## Format ghi lỗi

```
## [Ngày X] Tên lỗi ngắn gọn

**Môi trường:** VM1 / VM2 / VM3 / VM4
**Lệnh gây lỗi:** `lệnh_bạn_chạy`
**Thông báo lỗi:** error message đầy đủ
**Nguyên nhân:** Giải thích tại sao lỗi xảy ra
**Cách sửa:** lệnh hoặc bước để sửa
**Bài học:** Điều bạn rút ra
```

---

## 🗂️ Lỗi đã gặp và đã sửa

---

### [Ngày 2] dnsmasq: failed to create listening socket for port 53

**Môi trường:** VM1  
**Lệnh gây lỗi:** `sudo systemctl start dnsmasq`  
**Thông báo lỗi:**
```
dnsmasq: failed to create listening socket for port 53: Address already in use
```
**Nguyên nhân:** Ubuntu 22.04 mặc định chạy `systemd-resolved` chiếm port 53 (DNS stub listener). dnsmasq không thể bind cùng port đó.  
**Cách sửa:**
```bash
sudo systemctl disable systemd-resolved
sudo systemctl stop systemd-resolved
sudo rm /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
sudo systemctl restart dnsmasq
```
**Bài học:** Ubuntu 22.04 có resolved built-in. Khi tự dựng DNS server phải disable trước. Cũng cần nhớ viết lại `/etc/resolv.conf` vì file cũ là symlink đến resolved.

---

### [Ngày 2] netplan apply lỗi — invalid YAML

**Môi trường:** VM1  
**Lệnh gây lỗi:** `sudo netplan apply`  
**Thông báo lỗi:**
```
Error in network definition /etc/netplan/00-installer-config.yaml line 8 column 4:
Invalid YAML: inconsistent indentation
```
**Nguyên nhân:** YAML không cho phép dùng tab, phải dùng space. Tôi đã dùng tab khi soạn thảo.  
**Cách sửa:**
```bash
# Kiểm tra file có tab không
cat -A /etc/netplan/00-installer-config.yaml | grep "^I"
# Hoặc dùng sed thay tab bằng 2 space
sudo sed -i 's/\t/  /g' /etc/netplan/00-installer-config.yaml
sudo netplan apply
```
**Bài học:** YAML dùng space, không dùng tab. Mỗi cấp indent là 2 space. Dùng `sudo netplan try` thay vì `apply` để rollback tự động nếu lỗi.

---

### [Ngày 2] VM2 không nhận DHCP từ VM1

**Môi trường:** VM2  
**Lệnh gây lỗi:** `ip addr` → không thấy IP trên interface  
**Thông báo lỗi:** Interface chỉ có link-local address `169.254.x.x`  
**Nguyên nhân:** dnsmasq config dùng tên interface `ens36` nhưng VM1 thực tế tên là `ens33`. Tên interface phụ thuộc thứ tự cắm NIC trong VMware.  
**Cách sửa:**
```bash
# Trên VM1: kiểm tra tên thực của interface
ip link show
# Sửa dnsmasq.conf với tên đúng
sudo nano /etc/dnsmasq.conf
# Đổi interface=ens36 → interface=<tên thực>
sudo systemctl restart dnsmasq
# Trên VM2: force renew DHCP
sudo dhclient -r; sudo dhclient
```
**Bài học:** Tên interface ens33/ens36/ens38 không cố định. Sau khi cài VM luôn chạy `ip link show` để xác nhận tên trước khi config.

---

### [Ngày 2] Ping 8.8.8.8 từ VM2 thất bại dù dnsmasq đã chạy

**Môi trường:** VM2  
**Lệnh gây lỗi:** `ping -c 3 8.8.8.8`  
**Thông báo lỗi:** `Network is unreachable` hoặc timeout  
**Nguyên nhân:** Đã quên bật `ip_forward` trên VM1. Kernel biết route nhưng không forward packet.  
**Cách sửa:**
```bash
# Trên VM1
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward
# Bật vĩnh viễn
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```
**Bài học:** ip_forward=0 là mặc định trên Linux. Muốn làm router PHẢI bật. Kiểm tra: `cat /proc/sys/net/ipv4/ip_forward` phải ra 1.

---

### [Ngày 3] Lock out SSH sau khi tắt password auth

**Môi trường:** VM1  
**Nguyên nhân:** Tắt `PasswordAuthentication` trong sshd_config mà chưa test key trước, key chưa được copy đúng vào `~/.ssh/authorized_keys`.  
**Cách sửa (boot rescue):**
```bash
# Trong VMware: VM Settings → Power → Power on to BIOS/Recovery
# Hoặc dùng console VMware, chọn Advanced Options → Recovery Mode
# Mount filesystem và sửa:
sudo mount -o remount,rw /
nano /etc/ssh/sshd_config
# Đổi lại: PasswordAuthentication yes
# Reboot, SSH vào, thêm key đúng cách, tắt password lại
```
**Bài học:** LUÔN test key trong terminal mới trước khi đóng session SSH cũ. Thứ tự đúng: (1) copy key → (2) test SSH bằng key → (3) tắt password auth → (4) restart SSH → (5) test lại.

---

### [Ngày 6] docker: permission denied

**Môi trường:** VM2  
**Lệnh gây lỗi:** `docker ps`  
**Thông báo lỗi:**
```
permission denied while trying to connect to the Docker daemon socket
```
**Nguyên nhân:** User chưa được thêm vào group `docker`. Chỉ root mới chạy docker được mặc định.  
**Cách sửa:**
```bash
sudo usermod -aG docker $USER
# Logout và login lại (hoặc)
newgrp docker
# Kiểm tra
groups $USER   # phải thấy "docker" trong danh sách
```
**Bài học:** Sau khi cài Docker luôn nhớ bước này. `newgrp docker` chỉ có tác dụng trong session hiện tại, để áp dụng vĩnh viễn cần logout/login.

---

### [Ngày 7] Prometheus target "DOWN" — VM2 node_exporter

**Môi trường:** VM3 (Prometheus)  
**Thông báo:** Target `10.10.20.10:9100` health=down  
**Nguyên nhân:** Firewall rule trên VM1 chưa cho phép traffic từ LAN (VM3 10.10.10.x) sang DMZ (VM2 10.10.20.x) port 9100. Rule cũ chỉ cho phép port 80 và 443.  
**Cách sửa:**
```bash
# Trên VM1 — thêm rule cho phép monitoring scrape node_exporter
sudo iptables -A FORWARD -i ens36 -o ens38 -s 10.10.10.0/24 -d 10.10.20.10 -p tcp --dport 9100 -j ACCEPT
sudo netfilter-persistent save
```
**Bài học:** Khi thêm service mới phải review lại firewall. Prometheus scrape cần kết nối từ VM3 (LAN) đến VM2 (DMZ) → phải mở thêm rule cụ thể. Security theo nguyên tắc least privilege: chỉ mở đúng port cần thiết.

---

### [Ngày 9] DevStack stack.sh lỗi ở MySQL setup

**Môi trường:** VM4  
**Thông báo lỗi:**
```
+lib/databases/mysql:_mysql_set_privs:1   ERROR: Can not connect to MySQL as root
```
**Nguyên nhân:** Có phiên cài MySQL cũ từ lần chạy stack.sh trước, password không khớp.  
**Cách sửa:**
```bash
# Unstack trước
./unstack.sh
# Xoá MySQL hoàn toàn
sudo apt purge -y mysql-server mysql-client mysql-common
sudo apt autoremove -y
sudo rm -rf /etc/mysql /var/lib/mysql
# Chạy lại
./stack.sh
```
**Bài học:** Nếu stack.sh bị interrupt giữa chừng, PHẢI chạy unstack.sh trước khi chạy lại. Đừng chạy stack.sh trực tiếp lần 2.

---

### [Ngày 10] Instance stuck ở trạng thái "Spawning"

**Môi trường:** VM4 (OpenStack)  
**Thông báo:** `openstack server list` hiện Status: ERROR  
**Cách debug:**
```bash
# Xem console log của instance
openstack console log show web-instance-01

# Xem Nova compute log
sudo journalctl -u devstack@n-cpu -n 100

# Thường thấy: libvirt không tìm được image hoặc thiếu permission
# Sửa: restart nova-compute
sudo systemctl restart devstack@n-cpu
```
**Bài học:** `openstack console log show` là công cụ debug đầu tiên khi instance không chạy được. Xem log của nova-cpu bằng journalctl để biết libvirt báo lỗi gì.

---

### [Ngày 10] Floating IP không ping được

**Môi trường:** VM4 (OpenStack)  
**Lệnh:** `ping 192.168.200.210` — timeout  
**Nguyên nhân:** Security group chưa mở ICMP. Mặc định security group chặn tất cả inbound.  
**Cách sửa:**
```bash
openstack security group rule create web-sg \
    --protocol icmp \
    --remote-ip 0.0.0.0/0
# Ping lại → success
```
**Bài học:** Security group trong OpenStack là stateful firewall mặc định DENY. Phải explicit cho phép từng protocol. Hay quên ICMP vì thường chỉ nhớ mở SSH và HTTP.

---

## 📌 Lỗi thường gặp nhanh (Quick Reference)

| Lỗi | Kiểm tra ngay |
|-----|---------------|
| VM không nhận DHCP | `systemctl status dnsmasq` trên VM1 |
| Không ping được 8.8.8.8 từ VM con | `cat /proc/sys/net/ipv4/ip_forward` — phải là 1 |
| port 53 bị chiếm | `ss -tulnp | grep :53` — disable systemd-resolved |
| iptables rules mất sau reboot | `sudo netfilter-persistent save` |
| SSH timeout | kiểm tra iptables INPUT rule cho port 22 |
| Docker permission denied | `sudo usermod -aG docker $USER` + re-login |
| Prometheus target DOWN | kiểm tra firewall, `curl <target_ip>:9100/metrics` |
| DevStack MySQL lỗi | `./unstack.sh` rồi xoá MySQL rồi `./stack.sh` |
| Instance ERROR trong OpenStack | `openstack console log show <id>` |

---

*File này được cập nhật liên tục. Mỗi lỗi gặp → ghi vào đây ngay.*
