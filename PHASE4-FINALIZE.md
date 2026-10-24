# 🏁 Giai đoạn 4 — Hoàn thiện Repo (Ngày 13–14)

> **Mục tiêu:** Repo GitHub sạch, chuyên nghiệp, sẵn sàng để link vào CV.

---

## 📋 Ngày 13 – Dọn dẹp và hoàn thiện nội dung

### Checklist nội dung

**README chính (`/README.md`):**
- [ ] Cập nhật link GitHub thật (thay `YOUR_USERNAME`)
- [ ] Tick vào các mục "Kết quả đạt được" đã hoàn thành
- [ ] Thêm link sơ đồ mạng từ `docs/network-diagram.png`

**TROUBLESHOOTING.md:**
- [ ] Đã ghi ít nhất 5 lỗi thực sự gặp phải với nguyên nhân và cách sửa
- [ ] Có mục "Quick Reference" để tra nhanh

**04-openstack/openstack-notes.md:**
- [ ] Đã điền đủ 6 component bằng lời của mình (không copy-paste tài liệu)
- [ ] Có "luồng tạo instance" viết lại theo hiểu biết cá nhân

### Chụp Screenshots

```bash
# Ngày 13: chụp đủ ảnh, đặt vào đúng thư mục screenshots/
# Đặt tên file rõ ràng:
# 01-network/screenshots/01-vmware-network-editor.png
# 01-network/screenshots/02-vm1-ip-addr.png
# 01-network/screenshots/03-wireshark-dhcp.png
# 02-services/screenshots/01-docker-ps.png
# 02-services/screenshots/02-round-robin-test.png
# 02-services/screenshots/03-fault-tolerance-web1-down.png
# 03-monitoring/screenshots/01-prometheus-targets-up.png
# 03-monitoring/screenshots/02-grafana-dashboard.png
# 03-monitoring/screenshots/03-telegram-alert.png
# 04-openstack/screenshots/01-devstack-complete.png
# 04-openstack/screenshots/02-horizon-dashboard.png
# 04-openstack/screenshots/03-instance-running.png
# 04-openstack/screenshots/04-floating-ip-ssh.png
```

### Vẽ sơ đồ mạng (draw.io)

```
1. Mở https://app.diagrams.net/
2. New Diagram → Network
3. Vẽ theo kiến trúc trong README.md
4. File → Export as → PNG → lưu vào docs/network-diagram.png
5. Commit vào repo
```

### Commit cuối Ngày 13

```bash
cd e:\cloud

# Add tất cả screenshots và updates
git add .
git commit -m "docs: add screenshots, network diagram, and complete troubleshooting log"
git push
```

---

## 📋 Ngày 14 – Cập nhật CV và Final Check

### Cập nhật CV

**Template mô tả dự án (copy vào CV):**

```
PRIVATE CLOUD LAB: Mạng, Linux, ảo hóa và giám sát
VMware Workstation · Ubuntu Server 22.04 · Docker · Nginx · Prometheus/Grafana · OpenStack

• Thiết kế mô hình mạng 2 vùng (LAN/DMZ); cấu hình Linux gateway thực hiện
  NAT, DHCP (dnsmasq), DNS và firewall bằng iptables; phân tích gói tin
  DHCP/DNS/TCP bằng Wireshark/tcpdump

• Triển khai Nginx load balancer Round Robin cho 3 Docker containers;
  kiểm thử fault tolerance: tắt 1 backend, hệ thống tiếp tục phục vụ bình thường

• Xây dựng hệ thống giám sát Prometheus + Grafana (CPU/RAM/Disk/Network)
  và Bash health check script cảnh báo qua Telegram; systemd timer chạy mỗi 5 phút;
  bảo mật SSH bằng key và fail2ban

• Dựng OpenStack all-in-one (DevStack/Ubuntu 22.04); tìm hiểu Keystone, Nova,
  Neutron, Glance, Cinder; tạo instance, gán floating IP, cấu hình security group

GitHub: github.com/mimimi2k4/cloud
```

### Final GitHub Check

```bash
# Kiểm tra repo từ góc nhìn người đọc
# 1. Mở https://github.com/mimimi2k4/cloud
# 2. README hiển thị đẹp không?
# 3. Tất cả link nội bộ hoạt động không?
# 4. Screenshots hiển thị không?
# 5. Code blocks có syntax highlight không?

# Kiểm tra số file
git -C e:\cloud ls-files | wc -l

# Kiểm tra commit history
git -C e:\cloud log --oneline
```

### Final push

```powershell
git -C e:\cloud add .
git -C e:\cloud commit -m "chore: final cleanup - project complete"
git -C e:\cloud push
```

---

## ✅ Final Checklist trước phỏng vấn

### Kiến thức cần trả lời được

- [ ] **Network:** Gói tin từ VM ra Internet đi qua bước nào? NAT thay đổi gì trong header?
- [ ] **Subnet:** /24 có bao nhiêu host? Tại sao chia LAN và DMZ riêng?
- [ ] **Load Balancing:** Round Robin vs Least Connections? Passive health check hoạt động thế nào?
- [ ] **Monitoring:** Prometheus pull hay push? Grafana lấy data từ đâu?
- [ ] **OpenStack:** Neutron làm gì? Fixed IP vs Floating IP khác nhau chỗ nào?
- [ ] **Container vs VM:** Isolation khác nhau thế nào? Khi nào dùng container, khi nào dùng VM?
- [ ] **fail2ban:** Hoạt động thế nào? Log nào nó đọc? Ban bằng gì (iptables)?
- [ ] **systemd:** service vs timer khác nhau thế nào? `journalctl -u <service>` để làm gì?

### Câu chuyện kể khi phỏng vấn

> ⚠️ Đoạn mẫu dưới đây nhắc tới hai lỗi cụ thể. **Chỉ dùng khi bạn thực sự gặp chúng**; nếu không, thay bằng lỗi thật của bạn trong TROUBLESHOOTING.md. Người phỏng vấn sẽ hỏi sâu vào đúng những chi tiết này.

> *"Em xây dựng lab này để tự thực hành các skill cần cho vị trí Cloud Engineer.
> Em gặp khá nhiều lỗi — chẳng hạn systemd-resolved chiếm port 53 nên dnsmasq
> không start được, hay lần bị lock out SSH vì tắt password auth trước khi test key.
> Em đều ghi lại vào TROUBLESHOOTING.md. Điều em thấy có giá trị nhất là việc
> phải debug từng layer: network, OS, service, application — đúng như môi trường
> production thực tế."*

---

## 🎯 Link chia sẻ

- **GitHub Repo:** https://github.com/mimimi2k4/cloud
- **Giai đoạn 1 (Network):** github.com/mimimi2k4/cloud/blob/master/01-network/README.md
- **Giai đoạn 2 (Services):** github.com/mimimi2k4/cloud/blob/master/02-services/README.md
- **Giai đoạn 3 (OpenStack):** github.com/mimimi2k4/cloud/blob/master/04-openstack/README.md
- **Troubleshooting:** github.com/mimimi2k4/cloud/blob/master/TROUBLESHOOTING.md
