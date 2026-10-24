# 🐳 Giai đoạn 2 – Hướng dẫn Chi tiết: Dịch vụ và Giám sát (Ngày 6–8)

> **Mục tiêu cuối giai đoạn:**
> - VM2: 3 Docker container web chạy ổn định, Nginx phân phối Round Robin
> - Tắt 1 container → hệ thống vẫn phục vụ bình thường (fault tolerance)
> - VM3: Prometheus scrape metrics từ cả 3 VM, Grafana hiện dashboard
> - Health check script chạy tự động mỗi 5 phút, gửi Telegram khi dịch vụ chết

---

## 📋 Ngày 6 – VM2: Docker + Nginx Load Balancer

> **Chạy trên VM2 (DMZ 10.10.20.x)**

### Bước 6.1 – Cài Docker Engine

```bash
# Cập nhật package list
sudo apt update

# Cài các dependency cần thiết
sudo apt install -y ca-certificates curl gnupg lsb-release

# Thêm Docker GPG key
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Thêm Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Cài Docker
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Thêm user vào group docker (không cần sudo mỗi lần)
sudo usermod -aG docker $USER

# Áp dụng group (hoặc logout/login lại)
newgrp docker

# Kiểm tra
docker --version
docker compose version
```

```bash
# Bật Docker khi reboot
sudo systemctl enable docker
sudo systemctl status docker
```

### Bước 6.2 – Chuẩn bị HTML cho 3 container

```bash
# Tạo thư mục làm việc
mkdir -p ~/webapp/{html/web1,html/web2,html/web3}
cd ~/webapp

# Tạo trang HTML phân biệt cho từng container
cat > html/web1/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
  <title>Web Server 1</title>
  <style>
    body { font-family: Arial; background: #1a1a2e; color: #e0e0e0;
           display:flex; justify-content:center; align-items:center; height:100vh; margin:0; }
    .box { text-align:center; padding:40px; background:#16213e;
           border-radius:12px; border:2px solid #0f3460; }
    h1 { color:#e94560; font-size:3em; }
    p  { color:#a0a0a0; font-size:1.2em; }
  </style>
</head>
<body>
  <div class="box">
    <h1>🚀 Web Server 1</h1>
    <p>Container: web1 | Port: 3001</p>
    <p>Private Cloud Lab — Nginx Load Balancer</p>
  </div>
</body>
</html>
EOF

cat > html/web2/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
  <title>Web Server 2</title>
  <style>
    body { font-family: Arial; background: #0f2027; color: #e0e0e0;
           display:flex; justify-content:center; align-items:center; height:100vh; margin:0; }
    .box { text-align:center; padding:40px; background:#203a43;
           border-radius:12px; border:2px solid #2c5364; }
    h1 { color:#00b4d8; font-size:3em; }
    p  { color:#a0a0a0; font-size:1.2em; }
  </style>
</head>
<body>
  <div class="box">
    <h1>⚡ Web Server 2</h1>
    <p>Container: web2 | Port: 3002</p>
    <p>Private Cloud Lab — Nginx Load Balancer</p>
  </div>
</body>
</html>
EOF

cat > html/web3/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
  <title>Web Server 3</title>
  <style>
    body { font-family: Arial; background: #1b1b2f; color: #e0e0e0;
           display:flex; justify-content:center; align-items:center; height:100vh; margin:0; }
    .box { text-align:center; padding:40px; background:#162447;
           border-radius:12px; border:2px solid #1f4068; }
    h1 { color:#1b998b; font-size:3em; }
    p  { color:#a0a0a0; font-size:1.2em; }
  </style>
</head>
<body>
  <div class="box">
    <h1>🌊 Web Server 3</h1>
    <p>Container: web3 | Port: 3003</p>
    <p>Private Cloud Lab — Nginx Load Balancer</p>
  </div>
</body>
</html>
EOF

echo "✅ HTML files created"
```

### Bước 6.3 – docker-compose.yml

```bash
cat > ~/webapp/docker-compose.yml << 'EOF'
version: '3.8'

services:
  web1:
    image: nginx:alpine
    container_name: web1
    ports:
      - "3001:80"
    volumes:
      - ./html/web1:/usr/share/nginx/html:ro
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost/"]
      interval: 10s
      timeout: 3s
      retries: 3

  web2:
    image: nginx:alpine
    container_name: web2
    ports:
      - "3002:80"
    volumes:
      - ./html/web2:/usr/share/nginx/html:ro
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost/"]
      interval: 10s
      timeout: 3s
      retries: 3

  web3:
    image: nginx:alpine
    container_name: web3
    ports:
      - "3003:80"
    volumes:
      - ./html/web3:/usr/share/nginx/html:ro
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost/"]
      interval: 10s
      timeout: 3s
      retries: 3
EOF
```

```bash
# Chạy containers
cd ~/webapp
docker compose up -d

# Kiểm tra
docker ps
docker compose ps

# Test từng container trực tiếp
curl http://localhost:3001/   # Web Server 1
curl http://localhost:3002/   # Web Server 2
curl http://localhost:3003/   # Web Server 3
```

### Bước 6.4 – Cài và cấu hình Nginx Load Balancer

```bash
sudo apt install -y nginx

# Backup config mặc định
sudo mv /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/default.bak
```

```bash
# Tạo config load balancer
sudo tee /etc/nginx/sites-available/loadbalancer.conf << 'EOF'
upstream web_backend {
    # Round Robin — mặc định, phân phối lần lượt
    server 127.0.0.1:3001;
    server 127.0.0.1:3002;
    server 127.0.0.1:3003;

    # Passive health check: bỏ qua backend bị lỗi
    # (không cần nginx Plus)
}

server {
    listen 80;
    server_name _;

    # Access log với upstream info để thấy Round Robin
    log_format lb_log '$remote_addr - [$time_local] "$request" '
                      '$status $upstream_addr $upstream_response_time';
    access_log /var/log/nginx/lb-access.log lb_log;
    error_log  /var/log/nginx/lb-error.log;

    location / {
        proxy_pass         http://web_backend;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;

        # Tự động skip backend lỗi
        proxy_next_upstream     error timeout http_502 http_503 http_504;
        proxy_connect_timeout   2s;
        proxy_read_timeout      5s;
    }

    # Endpoint xem status Nginx (dùng cho Prometheus)
    location /nginx_status {
        stub_status on;
        allow 127.0.0.1;
        allow 10.10.10.0/24;   # cho phép VM3 (monitoring) scrape
        deny all;
    }
}
EOF

# Kích hoạt site
sudo ln -s /etc/nginx/sites-available/loadbalancer.conf /etc/nginx/sites-enabled/

# Kiểm tra config
sudo nginx -t

# Reload Nginx
sudo systemctl reload nginx
sudo systemctl enable nginx
```

### Bước 6.5 – Test Load Balancer và Fault Tolerance

```bash
# Test Round Robin — gửi 9 request, mỗi server nhận 3
for i in $(seq 1 9); do
    echo "Request $i: $(curl -s http://localhost/ | grep -oP '(?<=<h1>).*(?=</h1>)')"
    sleep 0.5
done

# Output mong đợi:
# Request 1: 🚀 Web Server 1
# Request 2: ⚡ Web Server 2
# Request 3: 🌊 Web Server 3
# Request 4: 🚀 Web Server 1
# ... (lặp lại)
```

```bash
# ── TEST FAULT TOLERANCE ─────────────────────────────────────
# Tắt web1
docker stop web1
echo "web1 đã tắt!"

# Gửi request — phải vẫn hoạt động với web2 và web3
for i in $(seq 1 6); do
    echo "Request $i: $(curl -s http://localhost/ | grep -oP '(?<=<h1>).*(?=</h1>)')"
    sleep 0.5
done

# Output mong đợi: chỉ thấy Web Server 2 và Web Server 3
# Web Server 1 không xuất hiện (đang tắt)

# Bật lại web1
docker start web1
echo "web1 đã bật lại!"
```

```bash
# Xem log Nginx để thấy upstream server nào xử lý request
sudo tail -f /var/log/nginx/lb-access.log
# Output: 10.10.10.10 - [24/Oct/2026] "GET / HTTP/1.1" 200 127.0.0.1:3001 0.002
```

---

## 📋 Ngày 7 – VM3: Prometheus + Grafana + node_exporter

> **Cài node_exporter trên VM1, VM2, VM3 — cài Prometheus + Grafana trên VM3**

### Bước 7.1 – Cài node_exporter trên TẤT CẢ VM (VM1, VM2, VM3)

> Chạy lệnh này trên từng VM

```bash
# Tải node_exporter (kiểm tra version mới nhất tại https://github.com/prometheus/node_exporter/releases)
NODE_EXPORTER_VERSION="1.8.2"
wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz

# Giải nén và cài
tar xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
sudo mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
sudo chmod +x /usr/local/bin/node_exporter

# Tạo user riêng cho node_exporter (security best practice)
sudo useradd --no-create-home --shell /bin/false node_exporter

# Tạo systemd service
sudo tee /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Bật và khởi động
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter
sudo systemctl status node_exporter

# Kiểm tra metrics endpoint
curl http://localhost:9100/metrics | head -20
```

> **Mở firewall trên từng VM cho port 9100:**
> ```bash
> # Trên VM1 — cho VM3 (10.10.10.10) scrape
> sudo iptables -A INPUT -s 10.10.10.0/24 -p tcp --dport 9100 -j ACCEPT
>
> # Trên VM2 — cho VM3 scrape từ LAN sang DMZ
> # (Cần thêm rule trên VM1 Gateway cho phép 10.10.10.0/24 → 10.10.20.x:9100)
> sudo iptables -A INPUT -p tcp --dport 9100 -j ACCEPT  # tạm thời
> ```

### Bước 7.2 – Cài Prometheus trên VM3

```bash
# Chạy trên VM3
PROMETHEUS_VERSION="2.53.0"
wget https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz

tar xzf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
cd prometheus-${PROMETHEUS_VERSION}.linux-amd64

# Cài binary
sudo mv prometheus promtool /usr/local/bin/

# Tạo thư mục config và data
sudo mkdir -p /etc/prometheus /var/lib/prometheus

# Cài console files
sudo mv consoles/ console_libraries/ /etc/prometheus/

# Tạo user
sudo useradd --no-create-home --shell /bin/false prometheus
sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
```

```bash
# Tạo prometheus.yml
sudo tee /etc/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'vm1-gateway'
    static_configs:
      - targets: ['10.10.10.1:9100']
        labels:
          instance: 'vm1-gateway'
          role: 'gateway'

  - job_name: 'vm2-webserver'
    static_configs:
      - targets: ['10.10.20.10:9100']
        labels:
          instance: 'vm2-webserver'
          role: 'webserver'

  - job_name: 'vm3-monitoring'
    static_configs:
      - targets: ['localhost:9100']
        labels:
          instance: 'vm3-monitoring'
          role: 'monitoring'
EOF

sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml
```

```bash
# Tạo systemd service cho Prometheus
sudo tee /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus Monitoring System
After=network.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/prometheus \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --storage.tsdb.retention.time=15d \
    --web.enable-lifecycle
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl start prometheus
sudo systemctl status prometheus
```

```bash
# Kiểm tra Prometheus targets
# Mở trình duyệt: http://10.10.10.10:9090/targets
# Hoặc từ command line:
curl http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -A3 '"health"'
# Phải thấy "health": "up" cho cả 3 targets
```

### Bước 7.3 – Cài Grafana trên VM3

```bash
# Cài Grafana từ repo chính thức
sudo apt install -y software-properties-common apt-transport-https

# Thêm GPG key và repo
wget -q -O - https://apt.grafana.com/gpg.key | sudo apt-key add -
echo "deb https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

sudo apt update
sudo apt install -y grafana

# Bật và khởi động
sudo systemctl enable grafana-server
sudo systemctl start grafana-server
sudo systemctl status grafana-server
```

### Bước 7.4 – Cấu hình Grafana Dashboard

```
1. Mở trình duyệt: http://10.10.10.10:3000
2. Đăng nhập: admin / admin → đổi password
3. Thêm Data Source:
   - Vào Configuration → Data Sources → Add data source
   - Chọn Prometheus
   - URL: http://localhost:9090
   - Click "Save & Test" → phải thấy "Data source is working"

4. Import dashboard có sẵn (nhanh và đẹp):
   - Vào Dashboards → Import
   - Nhập ID: 1860 (Node Exporter Full — dashboard phổ biến nhất)
   - Chọn Prometheus data source → Import
   - Dashboard tự động hiện CPU, RAM, Disk, Network

5. Tạo dashboard riêng (tuỳ chọn):
   - New Dashboard → Add Panel
   - Query: node_cpu_seconds_total{mode="idle"}
   - Visualization: Time series
```

```bash
# Các PromQL query hữu ích để dùng trong Grafana:

# CPU usage (%)
100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# RAM usage (%)
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Disk usage (%)
(1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100

# Network traffic (bytes/s)
rate(node_network_receive_bytes_total{device="ens33"}[5m])
rate(node_network_transmit_bytes_total{device="ens33"}[5m])
```

---

## 📋 Ngày 8 – Health Check Script + Systemd Timer + Telegram Alert

### Bước 8.1 – Tạo Telegram Bot

```
1. Mở Telegram → tìm @BotFather
2. Gửi lệnh: /newbot
3. Đặt tên bot: CloudLabAlertBot (hoặc tuỳ ý)
4. BotFather trả về: TOKEN (dạng 123456:ABC-DEF...)
5. Ghi lại TOKEN này

6. Lấy Chat ID:
   - Gửi 1 tin nhắn bất kỳ cho bot của bạn
   - Truy cập: https://api.telegram.org/bot<TOKEN>/getUpdates
   - Tìm "chat":{"id": 123456789} → đó là CHAT_ID của bạn
```

### Bước 8.2 – Cài script và systemd timer trên VM3

```bash
# Cài netcat (dùng để check port)
sudo apt install -y netcat-openbsd

# Copy script
sudo cp ~/private-cloud-lab/03-monitoring/healthcheck.sh /usr/local/bin/healthcheck.sh
sudo chmod +x /usr/local/bin/healthcheck.sh

# Điền token và chat ID thật vào script
sudo nano /usr/local/bin/healthcheck.sh
# Sửa 2 dòng:
# TELEGRAM_BOT_TOKEN="TOKEN_CỦA_BẠN"
# TELEGRAM_CHAT_ID="CHAT_ID_CỦA_BẠN"

# Tạo log file
sudo touch /var/log/healthcheck.log
sudo chmod 644 /var/log/healthcheck.log

# Test thử chạy tay
sudo bash /usr/local/bin/healthcheck.sh
sudo tail -20 /var/log/healthcheck.log
```

### Bước 8.3 – Cài systemd service và timer

```bash
# Copy service và timer files
sudo cp ~/private-cloud-lab/03-monitoring/healthcheck.service /etc/systemd/system/
sudo cp ~/private-cloud-lab/03-monitoring/healthcheck.timer /etc/systemd/system/

# Reload và bật timer
sudo systemctl daemon-reload
sudo systemctl enable healthcheck.timer
sudo systemctl start healthcheck.timer

# Kiểm tra timer
sudo systemctl status healthcheck.timer
sudo systemctl list-timers | grep healthcheck

# Output mẫu:
# healthcheck.timer  Sun 2026-10-25 09:15:00 +07  4min 32s left
```

### Bước 8.4 – Test cảnh báo Telegram

```bash
# Trên VM2: tắt Nginx để trigger alert
sudo systemctl stop nginx

# Chờ đến lần timer chạy tiếp theo (tối đa 5 phút)
# Hoặc chạy thủ công ngay:
sudo systemctl start healthcheck.service

# Kiểm tra log
sudo tail -20 /var/log/healthcheck.log
# Phải thấy: ❌ Nginx (VM2) 10.10.20.10:80 — FAILED
# Telegram nhận được tin nhắn cảnh báo 🚨

# Bật lại Nginx
sudo systemctl start nginx

# Chạy check lại
sudo systemctl start healthcheck.service
sudo tail -5 /var/log/healthcheck.log
# Phải thấy: ✅ All services healthy
```

---

## 📸 Screenshots cần chụp — Giai đoạn 2

- [ ] `docker ps` trên VM2 — 3 containers đang chạy
- [ ] Browser: mở từng container (localhost:3001, 3002, 3003) — 3 màu khác nhau
- [ ] Terminal: vòng lặp `for` hiện Round Robin (1→2→3→1→2→3)
- [ ] Terminal: tắt web1, gửi request → chỉ thấy web2, web3 (fault tolerance)
- [ ] Prometheus: http://10.10.10.10:9090/targets — 3 targets "UP"
- [ ] Grafana: Dashboard Node Exporter Full — CPU/RAM/Disk đang chạy
- [ ] Telegram: nhận cảnh báo khi Nginx tắt
- [ ] `sudo systemctl list-timers | grep healthcheck` — timer active

---

## 🐛 Lỗi thường gặp — Giai đoạn 2

| Lỗi | Nguyên nhân | Cách sửa |
|-----|-------------|----------|
| `docker: permission denied` | User chưa vào group docker | `sudo usermod -aG docker $USER` rồi logout/login |
| Nginx báo `502 Bad Gateway` | Container chưa chạy hoặc port sai | `docker ps` kiểm tra, `curl localhost:3001` test trực tiếp |
| Prometheus target "DOWN" | node_exporter chưa chạy hoặc firewall chặn | `systemctl status node_exporter`; kiểm tra iptables |
| Grafana không kết nối Prometheus | Sai URL | URL phải là `http://localhost:9090`, không phải IP ngoài |
| Telegram bot không gửi được | Sai TOKEN hoặc CHAT_ID | Test: `curl "https://api.telegram.org/bot<TOKEN>/getMe"` |
| Timer không chạy | service file bị lỗi | `journalctl -u healthcheck.service` xem log lỗi |

---

## ✅ Checklist hoàn thành Giai đoạn 2

```bash
# VM2
docker ps | grep -c "Up"      # phải ra 3
curl http://localhost/ | grep "Web Server"   # thấy 1 trong 3 servers

# VM3
curl http://localhost:9090/api/v1/targets | grep '"health":"up"' | wc -l  # phải ra 3
curl http://localhost:3000/   # Grafana trả về 200

# Health check
sudo systemctl is-active healthcheck.timer   # active
sudo tail -1 /var/log/healthcheck.log        # "All services healthy"
```

---

*Hoàn thành Giai đoạn 2 → Sang [Giai đoạn 3: OpenStack](../04-openstack/)*
