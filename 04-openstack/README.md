# ☁️ Giai đoạn 3 – Hướng dẫn Chi tiết: OpenStack (Ngày 9–12)

> **Mục tiêu cuối giai đoạn:**
> - VM4 chạy OpenStack DevStack ổn định
> - Đăng nhập được Horizon Dashboard
> - Tạo được network/router/instance, gán floating IP, cấu hình security group
> - Hiểu và giải thích được vai trò của Keystone, Nova, Neutron, Glance, Cinder
>
> ⚠️ **TẮT VM1, VM2, VM3 TRƯỚC KHI BẬT VM4** — máy 16GB RAM không chạy đồng thời được!

---

## 📋 Ngày 9 – Tạo VM4 và Cài DevStack

### Bước 9.1 – Tạo VM4 trong VMware

**Cấu hình bắt buộc:**

| Thông số | Giá trị | Ghi chú |
|----------|---------|---------|
| OS | Ubuntu Server 22.04 LTS | LTS quan trọng — DevStack hay lỗi với non-LTS |
| RAM | 8192 MB (8 GB) | Tối thiểu — thấp hơn DevStack sẽ lỗi |
| vCPU | 4 | Tối thiểu |
| Disk | 60 GB | Thin provisioned OK |
| Network | VMware NAT | Cần ra Internet để tải packages |

**Bật Nested Virtualization (BẮT BUỘC):**
1. Tắt VM4 hoàn toàn (nếu đang chạy)
2. VM Settings → Processors → ✅ "Virtualize Intel VT-x/EPT or AMD-V/RVI"
3. Nếu không thấy option này: Edit → Preferences → check Workstation version

```bash
# Kiểm tra nested virt đã bật chưa (trong VM4)
grep -cw vmx /proc/cpuinfo
# Kết quả > 0 → OK ✅
# Kết quả = 0 → Chưa bật VT-x trong VMware Settings
```

### Bước 9.2 – Chuẩn bị Ubuntu Server 22.04

```bash
# Cập nhật hệ thống
sudo apt update
sudo apt upgrade -y

# Cài các package cần thiết
sudo apt install -y git vim curl wget net-tools python3-pip

# Kiểm tra IP (ghi lại để dùng trong local.conf)
ip addr show ens33
# Ghi lại IP, ví dụ: 192.168.x.y

# Tắt firewall (DevStack tự quản lý)
sudo ufw disable

# Tắt systemd-resolved (tránh xung đột DNS với Neutron)
sudo systemctl disable systemd-resolved
sudo systemctl stop systemd-resolved
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
```

### Bước 9.3 – Tạo user stack (DevStack yêu cầu không chạy root)

```bash
# Tạo user stack
sudo useradd -s /bin/bash -d /opt/stack -m stack

# Cấp sudo không cần password (DevStack cần)
echo "stack ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/stack

# Chuyển sang user stack
sudo su - stack
```

### Bước 9.4 – Clone DevStack và cấu hình

```bash
# Đang chạy với user stack
git clone https://opendev.org/openstack/devstack -b stable/2024.1
cd devstack

# Tạo local.conf
cat > local.conf << EOF
[[local|localrc]]
# ============================================================
# DevStack local.conf — VM4 OpenStack all-in-one
# ============================================================

# THAY IP NÀY bằng IP thực của VM4
HOST_IP=$(hostname -I | awk '{print $1}')

# Passwords (dùng password đơn giản cho lab)
ADMIN_PASSWORD=openstack123
DATABASE_PASSWORD=openstack123
RABBIT_PASSWORD=openstack123
SERVICE_PASSWORD=openstack123

# ── Services ──────────────────────────────────────────────────
# Core services (bật)
enable_service key         # Keystone
enable_service nova        # Compute
enable_service placement   # Placement API
enable_service glance      # Image
enable_service cinder      # Block Storage
enable_service horizon     # Dashboard

# Neutron (networking)
enable_service neutron
enable_service q-svc
enable_service q-agt
enable_service q-dhcp
enable_service q-l3
enable_service q-meta

# Tắt những gì không cần (tiết kiệm RAM)
disable_service tempest
disable_service swift
disable_service heat
disable_service ceilometer

# ── Logging ──────────────────────────────────────────────────
VERBOSE=True
LOG_COLOR=True
LOGFILE=/opt/stack/logs/stack.sh.log
LOGDAYS=2

# ── Network config ────────────────────────────────────────────
# Floating IP range (external network)
FLOATING_RANGE=192.168.200.0/24
Q_FLOATING_ALLOCATION_POOL=start=192.168.200.200,end=192.168.200.250
PUBLIC_NETWORK_GATEWAY=192.168.200.1

# Fixed IP range (internal network)
FIXED_RANGE=10.11.12.0/24
FIXED_NETWORK_SIZE=256
FLAT_INTERFACE=ens33
EOF

echo "✅ local.conf created"
cat local.conf
```

### Bước 9.5 – Chạy DevStack

```bash
# Đang ở /opt/stack/devstack với user stack
# Quá trình này mất 30-60 phút — ĐỪNG INTERRUPT

./stack.sh 2>&1 | tee /tmp/devstack-install.log

# Theo dõi progress (mở terminal khác)
tail -f /opt/stack/logs/stack.sh.log
```

**Các giai đoạn bạn sẽ thấy:**
```
+ Installing base dependencies...
+ Configuring MySQL...
+ Installing Python packages...
+ Starting Keystone...
+ Starting Glance...
+ Starting Nova...
+ Starting Neutron...
+ Starting Cinder...
+ Starting Horizon...
=========================
DevStack Component Timing
=========================
...
This is your host IP address: 192.168.x.y
Horizon is now available at http://192.168.x.y/dashboard
```

> ⚠️ **Nếu bị lỗi giữa chừng:** Chạy `./unstack.sh` rồi `./stack.sh` lại.
> Lỗi phổ biến nhất: package conflict hoặc network timeout. Xem log để biết chính xác.

---

## 📋 Ngày 10 – Horizon Dashboard: Tạo Instance và Gán Floating IP

### Bước 10.1 – Đăng nhập Horizon

```
URL:      http://<IP_VM4>/dashboard
Username: admin
Password: openstack123 (giá trị ADMIN_PASSWORD trong local.conf)
```

### Bước 10.2 – Khám phá Horizon (theo thứ tự)

**Kiểm tra services đang chạy:**
```bash
# Từ terminal VM4 (user stack)
source /opt/stack/devstack/openrc admin admin

# Kiểm tra tất cả services
openstack service list
openstack endpoint list

# Compute nodes
openstack compute service list

# Network agents
openstack network agent list
```

### Bước 10.3 – Tạo Network và Router

**Qua Horizon UI:**
```
1. Network → Networks → Create Network
   - Network Name: private-net
   - Subnet Name: private-subnet
   - Network Address: 10.11.12.0/24
   - Gateway IP: 10.11.12.1
   - DNS: 8.8.8.8

2. Network → Routers → Create Router
   - Router Name: main-router
   - External Network: public (network bên ngoài — DevStack tạo sẵn)

3. Gắn router vào private-net:
   - Click vào main-router → Interfaces → Add Interface
   - Chọn subnet: private-subnet
```

**Qua CLI (nhanh hơn, ghi vào notes):**
```bash
source /opt/stack/devstack/openrc admin admin

# Tạo private network
openstack network create private-net
openstack subnet create \
    --network private-net \
    --subnet-range 10.11.12.0/24 \
    --gateway 10.11.12.1 \
    --dns-nameserver 8.8.8.8 \
    private-subnet

# Tạo router và kết nối
openstack router create main-router
openstack router set main-router --external-gateway public
openstack router add subnet main-router private-subnet

# Kiểm tra
openstack network list
openstack router list
openstack router show main-router
```

### Bước 10.4 – Upload Image

```bash
# Download Cirros (image nhỏ gọn để test — 15MB)
wget http://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img

# Upload lên Glance
openstack image create "cirros-0.6.2" \
    --file cirros-0.6.2-x86_64-disk.img \
    --disk-format qcow2 \
    --container-format bare \
    --public

# Kiểm tra
openstack image list
```

### Bước 10.5 – Tạo Security Group

```bash
# Tạo security group cho web server
openstack security group create web-sg \
    --description "Allow SSH and HTTP"

# Mở port SSH
openstack security group rule create web-sg \
    --protocol tcp \
    --dst-port 22 \
    --remote-ip 0.0.0.0/0

# Mở port HTTP
openstack security group rule create web-sg \
    --protocol tcp \
    --dst-port 80 \
    --remote-ip 0.0.0.0/0

# Mở ICMP (ping)
openstack security group rule create web-sg \
    --protocol icmp \
    --remote-ip 0.0.0.0/0

# Kiểm tra
openstack security group rule list web-sg
```

### Bước 10.6 – Tạo Flavor (cấu hình VM)

```bash
# Flavor nhỏ cho Cirros
openstack flavor create --ram 512 --vcpus 1 --disk 5 tiny-lab
openstack flavor create --ram 1024 --vcpus 1 --disk 10 small-lab

# Kiểm tra
openstack flavor list
```

### Bước 10.7 – Tạo SSH Key Pair

```bash
# Tạo keypair
openstack keypair create lab-key > ~/lab-key.pem
chmod 600 ~/lab-key.pem

# Hoặc import keypair đã có
openstack keypair create --public-key ~/.ssh/id_rsa.pub lab-key

# Kiểm tra
openstack keypair list
```

### Bước 10.8 – Launch Instance

```bash
# Lấy IDs cần thiết
NETWORK_ID=$(openstack network show private-net -f value -c id)
IMAGE_ID=$(openstack image show "cirros-0.6.2" -f value -c id)
FLAVOR_ID=$(openstack flavor show tiny-lab -f value -c id)

# Tạo instance
openstack server create \
    --image $IMAGE_ID \
    --flavor $FLAVOR_ID \
    --network $NETWORK_ID \
    --security-group web-sg \
    --key-name lab-key \
    web-instance-01

# Kiểm tra status
openstack server list
openstack server show web-instance-01

# Chờ đến khi status = ACTIVE
watch -n 3 openstack server list
```

**Kiểm tra qua Horizon:**
```
Compute → Instances → web-instance-01
→ thấy Status: Running ✅
→ thấy Fixed IP: 10.11.12.x
```

### Bước 10.9 – Gán Floating IP

```bash
# Tạo floating IP từ external network
FLOATING_IP=$(openstack floating ip create public -f value -c floating_ip_address)
echo "Floating IP: $FLOATING_IP"

# Gán vào instance
openstack server add floating ip web-instance-01 $FLOATING_IP

# Kiểm tra
openstack server list
# thấy cột Addresses: private-net=10.11.12.x, <FLOATING_IP>
```

```bash
# Test kết nối qua floating IP
ping -c 3 $FLOATING_IP

# SSH vào instance Cirros
ssh -i ~/lab-key.pem cirros@$FLOATING_IP
# Password mặc định của Cirros: gocubsgo

# Bên trong Cirros
ip addr
ping 8.8.8.8   # Kiểm tra ra Internet
```

---

## 📋 Ngày 11 – Ghi chú Component và Thực hành thêm

### Bước 11.1 – Xem Keystone hoạt động

```bash
source /opt/stack/devstack/openrc admin admin

# Xem tất cả users
openstack user list

# Xem tất cả projects
openstack project list

# Xem roles
openstack role list

# Tạo user mới (thực hành)
openstack user create --password test123 testuser
openstack role add --project demo --user testuser member

# Lấy token (xem Keystone hoạt động như thế nào)
openstack token issue
```

### Bước 11.2 – Xem Nova hoạt động

```bash
# Xem hypervisor stats
openstack hypervisor stats show
openstack hypervisor list

# Xem resource usage
openstack quota show

# Console log của instance (debug khi instance không boot được)
openstack console log show web-instance-01

# VNC console URL
openstack console url show web-instance-01
```

### Bước 11.3 – Xem Neutron hoạt động

```bash
# Xem tất cả networks
openstack network list

# Xem routers
openstack router list
openstack router show main-router

# Xem ports
openstack port list

# Xem floating IPs
openstack floating ip list

# Xem network topology (Horizon)
# Network → Network Topology → thấy sơ đồ trực quan
```

### Bước 11.4 – Xem Glance hoạt động

```bash
# Xem images
openstack image list
openstack image show "cirros-0.6.2"

# Download image (test Glance API)
openstack image save "cirros-0.6.2" --file /tmp/cirros-downloaded.img
ls -lh /tmp/cirros-downloaded.img
```

### Bước 11.5 – Cinder (Block Storage)

```bash
# Tạo volume
openstack volume create --size 5 my-volume

# Kiểm tra
openstack volume list

# Gắn volume vào instance
openstack server add volume web-instance-01 my-volume

# Kiểm tra bên trong instance
ssh -i ~/lab-key.pem cirros@$FLOATING_IP
# fdisk -l   ← thấy disk mới /dev/vdb

# Detach volume
openstack server remove volume web-instance-01 my-volume

# Xoá volume (cleanup)
openstack volume delete my-volume
```

### Bước 11.6 – Điền vào openstack-notes.md

```bash
# Mở file notes và điền bằng lời của chính mình
nano ~/private-cloud-lab/04-openstack/openstack-notes.md
```

---

## 📋 Ngày 12 – Dự phòng: KVM + virsh (nếu DevStack thất bại)

> **Dùng plan này nếu:** DevStack không dựng được sau 2 ngày thử.
> Vẫn học được kiến trúc ảo hóa, trình bày trung thực trên CV.

### Cài KVM trên VM4

```bash
# Kiểm tra CPU hỗ trợ virtualization
egrep -c '(vmx|svm)' /proc/cpuinfo
# > 0 → OK

# Cài KVM stack
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst virt-manager

# Thêm user vào group
sudo usermod -aG libvirt $USER
sudo usermod -aG kvm $USER

# Khởi động libvirt
sudo systemctl enable libvirtd
sudo systemctl start libvirtd
```

```bash
# Tạo VM bằng virt-install
virt-install \
  --name test-vm1 \
  --ram 512 \
  --vcpus 1 \
  --disk path=/var/lib/libvirt/images/test-vm1.qcow2,size=5 \
  --os-variant ubuntu22.04 \
  --network network=default \
  --graphics none \
  --console pty,target_type=serial \
  --location 'http://archive.ubuntu.com/ubuntu/dists/jammy/main/installer-amd64/' \
  --extra-args 'console=ttyS0,115200n8 serial'

# Quản lý VMs bằng virsh
virsh list --all
virsh start test-vm1
virsh shutdown test-vm1
virsh dominfo test-vm1
```

**Ghi vào CV/notes nếu dùng plan dự phòng:**
> *"Tìm hiểu kiến trúc OpenStack (Keystone, Nova, Neutron, Glance, Cinder) qua tài liệu chính thức; thực hành ảo hóa thực tế bằng KVM/libvirt và virsh trên Ubuntu 22.04"*

---

## 📸 Screenshots cần chụp — Giai đoạn 3

- [ ] VM4 Settings: "Virtualize Intel VT-x/EPT" được tick
- [ ] Terminal: `./stack.sh` hoàn thành — thấy "DevStack Component Timing"
- [ ] Horizon login page + logged in với admin
- [ ] Horizon → Network Topology (sơ đồ visual đẹp)
- [ ] Horizon → Compute → Instances: web-instance-01 Status Running
- [ ] Terminal: `openstack server list` — thấy Fixed IP + Floating IP
- [ ] Terminal: `ping <floating_ip>` — success
- [ ] Terminal: `ssh cirros@<floating_ip>` — connected
- [ ] Horizon → Volumes → my-volume attached
- [ ] `openstack service list` — thấy đủ Keystone/Nova/Neutron/Glance/Cinder

---

## 🐛 Lỗi thường gặp — Giai đoạn 3

| Lỗi | Nguyên nhân | Cách sửa |
|-----|-------------|----------|
| `ERROR: No module named 'openstack'` | Cài không đủ packages | `pip3 install python-openstackclient` |
| `./stack.sh` treo ở MySQL | MySQL conflict | `./unstack.sh; sudo apt purge mysql*; ./stack.sh` |
| Instance stuck "Spawning" | Nova compute lỗi | `journalctl -u devstack@n-cpu` xem log |
| Floating IP không ping được | Security group chưa mở ICMP | Thêm rule ICMP vào security group |
| Horizon 500 error | Apache/Django lỗi | `sudo systemctl restart apache2` |
| DevStack lỗi package hash | Apt cache cũ | `sudo apt clean; sudo apt update` |
| "VT-x not available" | Nested virt chưa bật | Tắt VM → VMware Settings → Processors → tick VT-x |
| Stack timeout sau 60 phút | RAM không đủ | Đảm bảo 8GB RAM, tắt hết VM khác |

---

## ✅ Checklist hoàn thành Giai đoạn 3

```bash
source /opt/stack/devstack/openrc admin admin

# Services đủ không?
openstack service list | grep -c "enabled"   # phải >= 5

# Instance chạy không?
openstack server list | grep "ACTIVE"

# Floating IP gán chưa?
openstack floating ip list | grep -v "None"

# SSH vào được instance không?
ssh -i ~/lab-key.pem cirros@<FLOATING_IP> "echo 'SSH OK'"
```

---

*Hoàn thành Giai đoạn 3 → Sang [Giai đoạn 4: Hoàn thiện repo](../README.md)*
