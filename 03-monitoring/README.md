# 📊 Giai đoạn 2 (Ngày 8) + Monitoring Stack — Hướng dẫn Chi tiết

> File hướng dẫn đầy đủ cho toàn bộ monitoring stack.
> Xem hướng dẫn Ngày 6-7 (Docker + Nginx + Prometheus + Grafana) tại: [`../02-services/README.md`](../02-services/README.md)

---

## 📋 Nội dung thư mục này

| File | Mục đích |
|------|----------|
| `prometheus.yml` | Cấu hình Prometheus scrape 3 VM |
| `healthcheck.sh` | Script kiểm tra dịch vụ + Telegram alert |
| `healthcheck.service` | systemd service unit |
| `healthcheck.timer` | systemd timer — chạy mỗi 5 phút |
| `grafana-dashboard.json` | Dashboard export từ Grafana |
| `screenshots/` | Ảnh chụp màn hình |

---

## 🚀 Cài đặt nhanh (chạy trên VM3)

### 1. Cài node_exporter (chạy trên VM1, VM2, VM3)

```bash
NODE_VER="1.8.2"
wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_VER}/node_exporter-${NODE_VER}.linux-amd64.tar.gz
tar xzf node_exporter-${NODE_VER}.linux-amd64.tar.gz
sudo mv node_exporter-${NODE_VER}.linux-amd64/node_exporter /usr/local/bin/
sudo useradd --no-create-home --shell /bin/false node_exporter

sudo tee /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Prometheus Node Exporter
After=network.target
[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
curl http://localhost:9100/metrics | head -5   # kiểm tra
```

### 2. Cài Prometheus (chỉ VM3)

```bash
PROM_VER="2.53.0"
wget https://github.com/prometheus/prometheus/releases/download/v${PROM_VER}/prometheus-${PROM_VER}.linux-amd64.tar.gz
tar xzf prometheus-${PROM_VER}.linux-amd64.tar.gz
sudo mv prometheus-${PROM_VER}.linux-amd64/{prometheus,promtool} /usr/local/bin/
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo mv prometheus-${PROM_VER}.linux-amd64/{consoles,console_libraries} /etc/prometheus/
sudo useradd --no-create-home --shell /bin/false prometheus
sudo cp prometheus.yml /etc/prometheus/prometheus.yml
sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

sudo tee /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus
After=network.target
[Service]
User=prometheus
ExecStart=/usr/local/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/prometheus \
    --storage.tsdb.retention.time=15d \
    --web.enable-lifecycle
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now prometheus
```

### 3. Cài Grafana (chỉ VM3)

```bash
wget -q -O - https://apt.grafana.com/gpg.key | sudo apt-key add -
echo "deb https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt update
sudo apt install -y grafana
sudo systemctl enable --now grafana-server
# Truy cập: http://10.10.10.10:3000  (admin/admin)
# Import dashboard ID: 1860
```

### 4. Cài healthcheck script

```bash
sudo cp healthcheck.sh /usr/local/bin/healthcheck.sh
sudo chmod +x /usr/local/bin/healthcheck.sh

# Điền Telegram token và chat ID vào file riêng (không ghi vào script)
sudo tee /etc/healthcheck.env << 'EOF'
TELEGRAM_BOT_TOKEN="TOKEN_CỦA_BẠN"
TELEGRAM_CHAT_ID="CHAT_ID_CỦA_BẠN"
EOF
sudo chmod 600 /etc/healthcheck.env

sudo cp healthcheck.service healthcheck.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now healthcheck.timer

# Kiểm tra
sudo systemctl list-timers | grep healthcheck
sudo bash /usr/local/bin/healthcheck.sh
```

---

## 📈 PromQL Queries cho Grafana

```promql
# CPU usage (%)
100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# RAM usage (%)
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Disk usage (%)
(1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100

# Network RX (bytes/s)
rate(node_network_receive_bytes_total{device!~"lo|vmnet.*"}[5m])

# Network TX (bytes/s)
rate(node_network_transmit_bytes_total{device!~"lo|vmnet.*"}[5m])

# Uptime (seconds)
time() - node_boot_time_seconds
```

---

## ✅ Kiểm tra tổng thể

```bash
# Prometheus targets UP?
curl -s http://localhost:9090/api/v1/targets | python3 -c \
  "import json,sys; t=json.load(sys.stdin)['data']['activeTargets']; \
   [print(x['labels']['instance'], x['health']) for x in t]"

# Grafana đang chạy?
curl -s http://localhost:3000/api/health | python3 -m json.tool

# Timer active?
sudo systemctl is-active healthcheck.timer

# Log gần nhất
sudo tail -5 /var/log/healthcheck.log
```
