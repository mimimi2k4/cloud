#!/bin/bash
# ============================================================
# Health Check Script — Private Cloud Lab
# Checks services on VM1, VM2, VM3 and sends Telegram alert
# Runs every 5 minutes via systemd timer
# ============================================================

# ── Configuration ────────────────────────────────────────────
TELEGRAM_BOT_TOKEN="YOUR_BOT_TOKEN_HERE"
TELEGRAM_CHAT_ID="YOUR_CHAT_ID_HERE"

VM1_IP="10.10.10.1"
VM2_IP="10.10.20.10"
VM3_IP="10.10.10.10"

LOG_FILE="/var/log/healthcheck.log"
HOSTNAME=$(hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# ── Helper functions ─────────────────────────────────────────
log() {
    echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
}

send_telegram() {
    local message="$1"
    curl -s -X POST \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text="${message}" \
        -d parse_mode="Markdown" \
        > /dev/null 2>&1
}

check_service() {
    local name="$1"
    local host="$2"
    local port="$3"

    if nc -z -w 2 "$host" "$port" 2>/dev/null; then
        log "✅ $name ($host:$port) — OK"
        return 0
    else
        log "❌ $name ($host:$port) — FAILED"
        return 1
    fi
}

# ── Health Checks ─────────────────────────────────────────────
ALERTS=""

# VM2: Nginx web server
if ! check_service "Nginx (VM2)" "$VM2_IP" 80; then
    ALERTS="${ALERTS}❌ *Nginx trên VM2* (${VM2_IP}:80) không phản hồi!\n"
fi

# VM3: Prometheus
if ! check_service "Prometheus (VM3)" "$VM3_IP" 9090; then
    ALERTS="${ALERTS}❌ *Prometheus trên VM3* (${VM3_IP}:9090) không phản hồi!\n"
fi

# VM3: Grafana
if ! check_service "Grafana (VM3)" "$VM3_IP" 3000; then
    ALERTS="${ALERTS}❌ *Grafana trên VM3* (${VM3_IP}:3000) không phản hồi!\n"
fi

# VM1: dnsmasq DNS
if ! check_service "DNS (VM1)" "$VM1_IP" 53; then
    ALERTS="${ALERTS}❌ *dnsmasq DNS trên VM1* (${VM1_IP}:53) không phản hồi!\n"
fi

# ── Send alert if any service is down ─────────────────────────
if [ -n "$ALERTS" ]; then
    MESSAGE="🚨 *CẢNH BÁO — Private Cloud Lab*\n\n${ALERTS}\n🕐 ${TIMESTAMP}\n🖥️ Host: ${HOSTNAME}"
    send_telegram "$MESSAGE"
    log "📤 Alert sent to Telegram"
else
    log "✅ All services healthy"
fi
