# 🖥️ Private Cloud Lab: Network, Linux, Virtualization & Monitoring

> **Stack:** VMware Workstation · Ubuntu Server 22.04 · Docker · Nginx · Prometheus/Grafana · OpenStack (DevStack)
>
> **Mục tiêu:** Xây dựng môi trường private cloud thu nhỏ trên máy tính cá nhân, tích hợp đủ các thành phần của một hạ tầng cloud thực tế: mạng, Linux, container, load balancing, giám sát và IaaS.

---

## 📐 Kiến trúc tổng thể

```
Internet ── Host Windows (16GB RAM) ── VMware NAT (192.168.x.x)
                                              │
                                   ┌──────────▼──────────┐
                                   │   VM1: Gateway/FW   │ 1GB RAM
                                   │  Ubuntu Server 22.04 │
                                   │  NAT · DHCP · DNS   │
                                   │  iptables firewall  │
                                   └──────┬──────────┬───┘
                                          │          │
                          ┌───────────────┘          └────────────────┐
                          │  LAN: 10.10.10.0/24                       │  DMZ: 10.10.20.0/24
                ┌─────────▼──────────┐                    ┌───────────▼──────────┐
                │  VM3: Monitoring   │ 2GB RAM             │  VM2: Web Services   │ 2GB RAM
                │  Prometheus        │                     │  Docker containers   │
                │  Grafana           │                     │  Nginx Load Balancer │
                │  node_exporter     │                     │  node_exporter       │
                └────────────────────┘                     └──────────────────────┘

─────────────── Giai đoạn riêng (tắt VM1-3 trước) ───────────────
                ┌────────────────────────────────────────────────┐
                │  VM4: OpenStack (DevStack)         8GB RAM     │
                │  Keystone · Nova · Neutron · Glance · Cinder   │
                │  Horizon Dashboard                             │
                └────────────────────────────────────────────────┘
```

### Bảng chia subnet

| Vùng | Subnet | Gateway | DHCP Range | Mục đích |
|------|--------|---------|------------|----------|
| LAN | 10.10.10.0/24 | 10.10.10.1 | 10.10.10.100-200 | Monitoring, internal |
| DMZ | 10.10.20.0/24 | 10.10.20.1 | 10.10.20.100-200 | Web services, exposed |

---

## 🗓️ Lịch 14 ngày

| Ngày | Nội dung | Trạng thái |
|------|----------|------------|
| 1 | Tạo VMware Host-only network, cài VM1 Ubuntu Server 3 NIC | ⬜ |
| 2 | VM1: netplan IP tĩnh, ip_forward, NAT iptables, dnsmasq DHCP/DNS | ⬜ |
| 3 | Firewall rules: LAN→DMZ port 80/443; SSH key + fail2ban | ⬜ |
| 4 | Wireshark/tcpdump bắt DHCP, DNS, TCP handshake, chụp ảnh | ⬜ |
| 5 | Viết sơ đồ mạng, bảng subnet vào README | ⬜ |
| 6 | VM2: Docker + 3 container web + Nginx reverse proxy/LB Round Robin | ⬜ |
| 7 | VM3: Prometheus + Grafana + node_exporter trên cả 3 VM | ⬜ |
| 8 | Bash health check script + cron/systemd timer + Telegram alert | ⬜ |
| 9 | Tạo VM4, bật VT-x/EPT trong VMware, cài DevStack | ⬜ |
| 10 | Horizon: tạo network/router/image, chạy instance, floating IP | ⬜ |
| 11 | Ghi chú Keystone/Nova/Neutron/Glance/Cinder bằng lời của mình | ⬜ |
| 12 | (Dự phòng) KVM + virsh nếu DevStack thất bại | ⬜ |
| 13 | Dọn repo: README, sơ đồ, config files, scripts, screenshots | ⬜ |
| 14 | Cập nhật CV, kiểm tra GitHub link | ⬜ |

---

## 📁 Cấu trúc repo

```
cloud/
├── README.md                    ← file này
├── TROUBLESHOOTING.md           ← lỗi gặp phải và cách sửa
├── 01-network/
│   ├── vm1-netplan.yaml         ← cấu hình IP tĩnh VM1
│   ├── dnsmasq.conf             ← DHCP + DNS
│   ├── iptables-rules.sh        ← NAT + firewall rules
│   ├── sshd_hardening.conf      ← hardened SSH config (drop-in sshd_config.d)
│   └── screenshots/             ← ảnh Wireshark, tcpdump
├── 02-services/
│   ├── docker-compose.yml       ← 3 web containers
│   ├── nginx.conf               ← reverse proxy + load balancer
│   └── screenshots/
├── 03-monitoring/
│   ├── prometheus.yml           ← scrape config
│   ├── grafana-dashboard.json   ← dashboard export
│   ├── healthcheck.sh           ← health check + Telegram alert
│   ├── healthcheck.service      ← systemd unit
│   ├── healthcheck.timer        ← systemd timer
│   └── screenshots/
├── 04-openstack/
│   ├── local.conf               ← DevStack config
│   ├── openstack-notes.md       ← giải thích các component
│   └── screenshots/             ← Horizon dashboard
└── docs/
    └── network-diagram.png      ← sơ đồ mạng xuất từ draw.io
```

---

## 🔧 Giai đoạn 1: Network + Linux (Ngày 1–5)

> Chi tiết từng lệnh: xem [`01-network/`](./01-network/)

### Nội dung giai đoạn này

- Tạo 2 VMware Host-only network: `vmnet2` (LAN 10.10.10.0/24) và `vmnet3` (DMZ 10.10.20.0/24)
- VM1 có 3 NIC: `ens33` (WAN/NAT), `ens36` (LAN), `ens38` (DMZ)
- Cấu hình IP tĩnh bằng **netplan**
- Bật `net.ipv4.ip_forward = 1` để VM1 hoạt động như router
- **NAT** bằng `iptables MASQUERADE` cho phép LAN/DMZ ra Internet qua WAN
- **DHCP + DNS** bằng `dnsmasq` cấp IP và phân giải tên nội bộ
- **Firewall** mặc định DROP, chỉ cho phép LAN→DMZ cổng 80/443
- **SSH hardening**: key-only, tắt root login, fail2ban giới hạn brute-force

### Lệnh kiểm tra nhanh

```bash
# Kiểm tra VM2/VM3 có nhận IP từ DHCP không
ip a

# Từ VM2/VM3 ping ra Internet qua VM1
ping -c 3 8.8.8.8

# Kiểm tra DNS nội bộ
dig web.lab @10.10.10.1

# Xem NAT table
sudo iptables -t nat -L -n -v
```

---

## 🐳 Giai đoạn 2: Dịch vụ và giám sát (Ngày 6–8)

> Chi tiết: xem [`02-services/`](./02-services/) và [`03-monitoring/`](./03-monitoring/)

### VM2 – Docker + Nginx Load Balancer

- 3 container web app (Node.js/Python Flask) chạy trên port 3001, 3002, 3003
- Nginx làm reverse proxy, load balance Round Robin
- Test fault tolerance: tắt 1 container → request vẫn được phục vụ bởi 2 container còn lại

```bash
# Xem các container đang chạy
docker ps

# Xem access log Nginx (thấy request phân phối đều)
sudo tail -f /var/log/nginx/access.log

# Giả lập container chết
docker stop web1
curl http://10.10.20.x/  # vẫn trả về 200
```

### VM3 – Monitoring Stack

- Prometheus scrape metrics từ `node_exporter` trên VM1, VM2, VM3
- Grafana dashboard: CPU, RAM, Disk I/O, Network traffic
- Health check script chạy mỗi 5 phút qua systemd timer

```bash
# Kiểm tra Prometheus targets
curl http://10.10.10.x:9090/api/v1/targets | python3 -m json.tool

# Truy cập Grafana
# http://10.10.10.x:3000 (admin/admin)
```

---

## ☁️ Giai đoạn 3: OpenStack (Ngày 9–12)

> Chi tiết: xem [`04-openstack/`](./04-openstack/)

> ⚠️ **Tắt VM1, VM2, VM3 trước khi bật VM4** — máy 16GB RAM không chạy được đồng thời.

### Thông số VM4

| Thông số | Giá trị |
|----------|---------|
| OS | Ubuntu Server 22.04 LTS |
| vCPU | 4 (bật VT-x/EPT) |
| RAM | 8 GB |
| Disk | 60 GB |
| Network | VMware NAT |

### Các component OpenStack đã tìm hiểu

| Component | Vai trò |
|-----------|---------|
| **Keystone** | Identity service — xác thực, phân quyền (token/API) |
| **Nova** | Compute — tạo/quản lý VM instances |
| **Neutron** | Network — virtual network, router, floating IP |
| **Glance** | Image service — lưu và quản lý OS images |
| **Cinder** | Block storage — tạo volume gắn vào instance |
| **Horizon** | Dashboard Web UI |

### Luồng tạo instance

```
1. Upload image (Glance)
2. Tạo network + subnet + router (Neutron)
3. Tạo flavor (Nova)
4. Launch instance → gán vào network → nhận fixed IP
5. Gán floating IP (Neutron) → truy cập từ ngoài
6. Cấu hình security group: mở port 22, 80
```

---

## 📊 Kết quả đạt được

- [ ] Mô hình mạng 2 vùng LAN/DMZ với Linux gateway thực hiện NAT, DHCP, DNS, firewall
- [ ] Phân tích gói tin DHCP, DNS, TCP handshake bằng Wireshark/tcpdump
- [ ] Nginx load balancer cho Docker containers, kiểm thử fault tolerance
- [ ] Prometheus + Grafana monitoring toàn bộ hệ thống
- [ ] Bash script health check + Telegram alert
- [ ] SSH hardening (key-only) + fail2ban
- [ ] OpenStack DevStack: tạo instance, floating IP, security group

---

## 🎓 Câu hỏi phỏng vấn thường gặp

<details>
<summary><b>Gói tin từ VM trong LAN ra Internet đi qua những bước nào?</b></summary>

1. VM2 (10.10.10.x) gửi packet đến default gateway = VM1 (10.10.10.1)
2. VM1 nhận packet trên interface `ens36` (LAN)
3. Kernel forward packet (ip_forward=1) ra interface `ens33` (WAN)
4. iptables rule MASQUERADE thay source IP: `10.10.10.x` → IP WAN của VM1
5. Packet ra Internet với IP của VM1, reply về thì VM1 DNAT lại cho VM2
6. NAT thay đổi: **source IP + source port** trong IP header và TCP header

</details>

<details>
<summary><b>Subnet /24 có bao nhiêu host? Vì sao chia LAN và DMZ riêng?</b></summary>

- `/24` = 256 địa chỉ, trừ network (x.x.x.0) và broadcast (x.x.x.255) = **254 host usable**
- Chia LAN/DMZ để **kiểm soát traffic bằng firewall**: DMZ chứa server public (web), LAN chứa server internal (monitoring). Nếu DMZ bị tấn công, attacker không tự do vào được LAN

</details>

<details>
<summary><b>Round Robin khác Least Connections ra sao?</b></summary>

- **Round Robin**: phân phối lần lượt 1-2-3-1-2-3. Đơn giản, không quan tâm server đang bận
- **Least Connections**: gửi request đến server có ít connection nhất. Phù hợp khi request có thời gian xử lý khác nhau

</details>

<details>
<summary><b>Neutron làm gì? Floating IP khác Fixed IP chỗ nào?</b></summary>

- **Neutron**: tạo và quản lý virtual network trong OpenStack (virtual switch, router, DHCP, security group)
- **Fixed IP**: IP cấp từ internal network của OpenStack, instance dùng để giao tiếp nội bộ
- **Floating IP**: IP từ external network, gán vào instance để truy cập từ bên ngoài. Có thể detach và gán cho instance khác

</details>

<details>
<summary><b>Container khác VM ở điểm nào?</b></summary>

| | Container (Docker) | VM (VMware) |
|--|--|--|
| Isolation | Process-level (namespace/cgroup) | Hardware-level (hypervisor) |
| OS | Dùng chung kernel host | Kernel riêng |
| Boot time | Giây | Phút |
| Size | MB | GB |
| Use case | Microservice, app packaging | OS khác, full isolation |

</details>

---

## 📝 Mẫu mô tả CV

> **PRIVATE CLOUD LAB: Mạng, Linux, ảo hóa và giám sát** | *VMware Workstation, Ubuntu Server, Docker, Nginx, Prometheus/Grafana, OpenStack* | [github.com/mimimi2k4/cloud](https://github.com/mimimi2k4/cloud)
>
> - Thiết kế mô hình mạng 2 vùng (LAN/DMZ); cấu hình Linux gateway thực hiện NAT, DHCP, DNS và firewall bằng iptables; phân tích gói tin DHCP/DNS/TCP bằng Wireshark
> - Triển khai Nginx load balancer (Round Robin) cho 3 Docker containers; kiểm thử fault tolerance khi tắt 1 backend, hệ thống tiếp tục phục vụ bình thường
> - Xây dựng hệ thống giám sát Prometheus + Grafana (CPU/RAM/Disk/Network) và Bash health check script cảnh báo qua Telegram; bảo mật SSH bằng key và fail2ban
> - Dựng OpenStack all-in-one (DevStack) trên Ubuntu 22.04; tìm hiểu Keystone, Nova, Neutron, Glance; tạo instance, gán floating IP và cấu hình security group

---

## 📚 Tài liệu tham khảo

- [Ubuntu Netplan docs](https://netplan.io/)
- [dnsmasq manual](http://www.thekelleys.org.uk/dnsmasq/doc.html)
- [iptables tutorial](https://www.frozentux.net/iptables-tutorial/iptables-tutorial.html)
- [Docker Compose docs](https://docs.docker.com/compose/)
- [Nginx load balancing](https://nginx.org/en/docs/http/load_balancing.html)
- [Prometheus getting started](https://prometheus.io/docs/prometheus/latest/getting_started/)
- [DevStack documentation](https://docs.openstack.org/devstack/latest/)

---

*Được xây dựng trong 14 ngày như một lab thực hành cho vị trí Fresher Cloud Engineer.*
