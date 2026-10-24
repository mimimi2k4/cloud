#!/bin/bash
# ============================================================
# Health Check Script — Private Cloud Lab
# Kiểm tra dịch vụ trên VM1, VM2, VM3 và gửi cảnh báo Telegram
# Chạy mỗi 5 phút bằng systemd timer
#
# CẤU HÌNH BÍ MẬT: KHÔNG ghi token vào script này (repo public).
# Tạo file /etc/healthcheck.env trên VM3:
#   TELEGRAM_BOT_TOKEN="123456:ABC..."
#   TELEGRAM_CHAT_ID="123456789"
# rồi: sudo chmod 600 /etc/healthcheck.env
# ============================================================

ENV_FILE="/etc/healthcheck.env"
# shellcheck disable=SC1090
[ -f "$ENV_FILE" ] && . "$ENV_FILE"

VM1_IP="10.10.10.1"
VM2_IP="10.10.20.10"
VM3_IP="10.10.10.10"

LOG_FILE="/var/log/healthcheck.log"
HOSTNAME=$(hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

log() {
    echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
}

send_telegram() {
    local message="$1"
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        log "⚠️ Chưa cấu hình Telegram (thiếu $ENV_FILE) — bỏ qua gửi cảnh báo"
        return 1
    fi
    # --data-urlencode để xuống dòng và ký tự đặc biệt hiển thị đúng
    curl -s -m 10 -X POST \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${message}" \
        > /dev/null 2>&1
}

check_service() {
    local name="$1" host="$2" port="$3"
    if nc -z -w 2 "$host" "$port" 2>/dev/null; then
        log "✅ $name ($host:$port) — OK"
        return 0
    else
        log "❌ $name ($host:$port) — FAILED"
        return 1
    fi
}

ALERTS=""
add_alert() { ALERTS="${ALERTS}❌ $1"$'\n'; }

check_service "Nginx (VM2)"      "$VM2_IP" 80   || add_alert "Nginx trên VM2 (${VM2_IP}:80) không phản hồi"
check_service "node_exporter VM2" "$VM2_IP" 9100 || add_alert "node_exporter trên VM2 (${VM2_IP}:9100) không phản hồi"
check_service "Prometheus (VM3)" "$VM3_IP" 9090 || add_alert "Prometheus trên VM3 (${VM3_IP}:9090) không phản hồi"
check_service "Grafana (VM3)"    "$VM3_IP" 3000 || add_alert "Grafana trên VM3 (${VM3_IP}:3000) không phản hồi"
check_service "DNS (VM1)"        "$VM1_IP" 53   || add_alert "dnsmasq DNS trên VM1 (${VM1_IP}:53) không phản hồi"

if [ -n "$ALERTS" ]; then
    MESSAGE="🚨 CẢNH BÁO — Private Cloud Lab"$'\n\n'"${ALERTS}"$'\n'"🕐 ${TIMESTAMP}"$'\n'"🖥️ Host: ${HOSTNAME}"
    if send_telegram "$MESSAGE"; then
        log "📤 Alert sent to Telegram"
    fi
    exit 1
else
    log "✅ All services healthy"
fi
