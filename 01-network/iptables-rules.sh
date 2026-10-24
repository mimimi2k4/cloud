#!/bin/bash
# ============================================================
# VM1 Gateway — iptables rules
# WAN: ens33 | LAN: ens36 (10.10.10.0/24) | DMZ: ens38 (10.10.20.0/24)
# Run as root: sudo bash iptables-rules.sh
# ============================================================

WAN="ens33"
LAN="ens34"
DMZ="ens35"
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
iptables -A INPUT   -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# ── SSH vào VM1 từ LAN ───────────────────────────────────────
iptables -A INPUT -i $LAN -p tcp --dport 22 -j ACCEPT

# ── ICMP (ping) ───────────────────────────────────────────────
iptables -A INPUT   -p icmp -j ACCEPT
iptables -A FORWARD -p icmp -j ACCEPT

# ── NAT: Masquerade LAN và DMZ ra Internet ───────────────────
iptables -t nat -A POSTROUTING -s $LAN_NET -o $WAN -j MASQUERADE
iptables -t nat -A POSTROUTING -s $DMZ_NET -o $WAN -j MASQUERADE

# ── FORWARD: LAN → Internet ──────────────────────────────────
iptables -A FORWARD -i $LAN -o $WAN -j ACCEPT

# ── FORWARD: DMZ → Internet ──────────────────────────────────
iptables -A FORWARD -i $DMZ -o $WAN -j ACCEPT

# ── FORWARD: LAN → DMZ (chỉ port 80 và 443) ─────────────────
iptables -A FORWARD -i $LAN -o $DMZ -p tcp --dport 80  -j ACCEPT
iptables -A FORWARD -i $LAN -o $DMZ -p tcp --dport 443 -j ACCEPT

# ── Monitoring: Prometheus (VM3 ở LAN) scrape node_exporter :9100 ──
# VM1 (chính gateway này): chỉ cho phép từ LAN
iptables -A INPUT -i $LAN -s $LAN_NET -p tcp --dport 9100 -j ACCEPT
# VM2 (DMZ): chỉ cho phép đúng VM3 (10.10.10.10) đi qua gateway tới 10.10.20.10:9100
iptables -A FORWARD -i $LAN -o $DMZ -s 10.10.10.10 -d 10.10.20.10 -p tcp --dport 9100 -j ACCEPT

# ── DHCP requests từ LAN và DMZ ──────────────────────────────
iptables -A INPUT -i $LAN -p udp --dport 67 -j ACCEPT
iptables -A INPUT -i $DMZ -p udp --dport 67 -j ACCEPT

# ── DNS từ LAN và DMZ ────────────────────────────────────────
iptables -A INPUT -i $LAN -p udp --dport 53 -j ACCEPT
iptables -A INPUT -i $LAN -p tcp --dport 53 -j ACCEPT
iptables -A INPUT -i $DMZ -p udp --dport 53 -j ACCEPT
iptables -A INPUT -i $DMZ -p tcp --dport 53 -j ACCEPT

# Lưu rules để giữ sau khi reboot (cần: apt install iptables-persistent)
if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save
fi

echo "✅ iptables rules applied successfully"
echo ""
iptables -L -n -v --line-numbers
