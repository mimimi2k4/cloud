# OpenStack Components — Ghi chú bằng lời của mình

> ⚠️ **BẢN NHÁP:** phần lý thuyết (vai trò từng component) dùng được ngay, nhưng các câu kiểu "những gì tôi đã làm trên Horizon" và "luồng tạo instance" chỉ đúng khi bạn đã tự dựng được DevStack. Sau khi thực hành, viết lại bằng lời của mình, sửa cho đúng những gì đã làm, rồi xoá dòng cảnh báo này.
>
> Viết sau khi thực hành xong. Phần này dùng khi phỏng vấn hỏi "em hiểu OpenStack như thế nào?"

---

## Keystone — Identity Service

**Vai trò:** Keystone là "bảo vệ cổng" của OpenStack. Mọi service đều phải hỏi Keystone trước khi làm gì. Khi tôi gõ lệnh `openstack server create`, client gửi username/password đến Keystone, Keystone trả về một **token** có thời hạn. Token đó được dùng để gọi các service khác (Nova, Neutron...) mà không cần nhập lại password.

**Các khái niệm:**
- **User**: tài khoản người dùng (admin, testuser...)
- **Project**: nhóm tài nguyên (demo, admin...) — tương tự namespace
- **Role**: quyền hạn (admin, member, reader)
- **Token**: chứng minh thư tạm thời, thường hết hạn sau 1 giờ
- **Endpoint**: địa chỉ API của từng service (internal/public/admin)

**Lệnh thực hành:**
```bash
openstack token issue              # lấy token
openstack user list                # xem users
openstack project list             # xem projects
openstack role assignment list     # xem ai có role gì
```

---

## Nova — Compute Service

**Vai trò:** Nova quản lý vòng đời của VM instances — tạo, chạy, tắt, xoá. Nova nhận yêu cầu "tạo VM" rồi quyết định chạy VM đó trên hypervisor nào (KVM trong trường hợp này), sau đó ra lệnh cho libvirt/KVM thực thi.

**Các component:**
- **nova-api**: nhận API request từ người dùng
- **nova-scheduler**: chọn compute node phù hợp (lab chỉ có 1 node)
- **nova-compute**: chạy trực tiếp trên hypervisor, tạo VM bằng libvirt/KVM
- **nova-conductor**: trung gian giữa scheduler và compute (tránh compute truy cập DB trực tiếp)
- **Flavor**: template cấu hình VM (vCPU, RAM, disk) — tôi tạo flavor `tiny-lab` 512MB/1vCPU/5GB

**Lệnh thực hành:**
```bash
openstack server create ...        # tạo instance
openstack server list              # xem instances
openstack server show <id>         # chi tiết instance
openstack hypervisor list          # xem compute nodes
openstack console log show <id>    # debug boot log
```

---

## Neutron — Network Service

**Vai trò:** Neutron tạo toàn bộ hạ tầng mạng ảo bên trong OpenStack. Không có Neutron, các VM không kết nối được với nhau hay ra ngoài.

**Các khái niệm:**
- **Network**: switch ảo (layer 2)
- **Subnet**: dải IP gắn với network (layer 3)
- **Router**: kết nối các subnet, làm gateway ra external network
- **Port**: "cổng cắm" ảo, mỗi VM có 1 port trên network
- **Security Group**: firewall ở tầng VM (stateful, giống iptables)
- **Fixed IP**: IP nội bộ cấp từ DHCP của Neutron, gắn với VM trong suốt vòng đời
- **Floating IP**: IP từ external network, *map* vào Fixed IP bằng NAT — có thể detach và gán cho VM khác

**Fixed IP vs Floating IP:**
```
Fixed IP:   10.11.12.5   ← VM luôn có, giao tiếp nội bộ
Floating IP: 192.168.200.210  ← gán thêm, truy cập từ ngoài
Neutron router làm DNAT: 192.168.200.210 → 10.11.12.5
```

**Lệnh thực hành:**
```bash
openstack network list
openstack router show main-router
openstack floating ip create public   # tạo floating IP
openstack server add floating ip <server> <ip>  # gán
```

---

## Glance — Image Service

**Vai trò:** Glance là kho lưu trữ disk images. Khi Nova cần tạo VM, nó hỏi Glance để lấy base image (Cirros, Ubuntu...) rồi clone ra disk của VM mới.

**Các khái niệm:**
- **Image**: file disk (qcow2, raw, vmdk...) chứa OS
- **Snapshot**: ảnh chụp VM đang chạy → có thể tạo VM mới từ đó
- Glance không lưu file trực tiếp — nó delegate sang backend (filesystem, Swift, Ceph...)

**Lệnh thực hành:**
```bash
openstack image list
openstack image create "cirros-0.6.2" --file cirros.img --disk-format qcow2 --public
openstack image show "cirros-0.6.2"
openstack image save "cirros-0.6.2" --file backup.img   # download
```

---

## Cinder — Block Storage Service

**Vai trò:** Cinder cung cấp persistent block storage (giống ổ cứng thêm) cho VM. VM có thể detach volume, VM chết nhưng data vẫn còn. Khác với ephemeral disk (mất khi VM xoá).

**Các khái niệm:**
- **Volume**: ổ đĩa ảo (5GB, 10GB...) — xuất hiện trong VM là `/dev/vdb`, `/dev/vdc`...
- **Snapshot**: bản sao volume tại một thời điểm
- **Backend**: LVM (mặc định trong DevStack), Ceph, NFS...

**Lệnh thực hành:**
```bash
openstack volume create --size 5 my-volume
openstack server add volume web-instance-01 my-volume
# Trong VM: fdisk -l → thấy /dev/vdb
openstack server remove volume web-instance-01 my-volume
openstack volume delete my-volume
```

---

## Horizon — Dashboard

**Vai trò:** Web UI để tương tác với OpenStack mà không cần CLI. Horizon gọi API của các service khác (Keystone, Nova, Neutron...) y hệt OpenStack CLI, chỉ là qua giao diện đồ họa.

**Những gì tôi đã làm trên Horizon:**
- Đăng nhập với tài khoản admin
- Xem Network Topology — sơ đồ visual: instance → port → network → router → external
- Tạo instance qua wizard
- Gán/gỡ Floating IP bằng nút Actions
- Mở VNC console trực tiếp trong browser
- Xem console log khi instance không boot được

---

## Luồng tạo instance — bằng lời của mình

Khi tôi chạy `openstack server create`:

1. **Keystone** xác thực token của tôi, kiểm tra tôi có quyền tạo VM không
2. **Nova API** nhận request, validate các parameter (image, flavor, network...)
3. **Nova Scheduler** chọn compute node phù hợp (có đủ RAM/CPU)
4. **Neutron** tạo một port trên private-net, cấp Fixed IP (10.11.12.x) qua DHCP
5. **Glance** cung cấp base image (cirros) cho Nova
6. **Nova Compute** clone image, tạo VM bằng libvirt/KVM, gắn network interface
7. VM boot lên, DHCP client lấy IP từ Neutron DHCP agent
8. Tôi tạo **Floating IP** → Neutron router cấu hình DNAT rule
9. SSH vào Floating IP → đến được VM

---

## So sánh với VMware (thực tế)

| OpenStack | VMware tương đương |
|-----------|-------------------|
| Nova | vSphere / ESXi |
| Neutron | NSX / vSwitch |
| Glance | Content Library |
| Cinder | vSAN / Datastore |
| Keystone | vCenter SSO |
| Horizon | vSphere Web Client |
| Floating IP | NAT rule / Published IP |

---

*Screenshots: xem thư mục `screenshots/`*
