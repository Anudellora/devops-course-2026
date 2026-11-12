#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0
check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf '  [OK]   %s\n' "$desc"
        ((PASS++))
    else
        printf '  [FAIL] %s (expected: %s; actual: %s)\n' "$desc" "$expected" "$actual"
        ((FAIL++))
    fi
}
echo "System audit: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"
echo "[1] SSH"
sshd_config="$(sudo sshd -T)"
check "Root login disabled" "no" "$(awk 'tolower($1)=="permitrootlogin" {print $2}' <<< "$sshd_config")"
check "Password authentication disabled" "no" "$(awk 'tolower($1)=="passwordauthentication" {print $2}' <<< "$sshd_config")"
check "SSH port" "2222" "$(awk 'tolower($1)=="port" {print $2}' <<< "$sshd_config")"
check "Maximum authentication attempts" "3" "$(awk 'tolower($1)=="maxauthtries" {print $2}' <<< "$sshd_config")"
echo "[2] Firewall"
ufw_status="$(sudo ufw status verbose)"
check "UFW active" "active" "$(awk '/^Status:/ {print $2}' <<< "$ufw_status")"
check "Default incoming policy" "deny" "$(awk '/^Default:/ {gsub(/[()]/, "", $2); print $2}' <<< "$ufw_status")"
check "SSH rate limit" "LIMIT" "$(awk '$1 == "2222/tcp" {print $2; exit}' <<< "$ufw_status")"
echo "[3] User accounts"
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd
echo "[4] Web server"
check "Nginx service active" "ok" "$(systemctl is-active --quiet nginx && echo ok || echo fail)"
check "Nginx configuration valid" "ok" "$(sudo nginx -t >/dev/null 2>&1 && echo ok || echo fail)"
cert_min_seconds="${CERT_MIN_SECONDS:-2592000}"
check "Certificate valid for at least 30 days" "ok" "$(openssl x509 -in /etc/ssl/certs/devops.crt -checkend "$cert_min_seconds" -noout >/dev/null 2>&1 && echo ok || echo fail)"
web_writable="$(find /var/www/devops-site -perm -o+w -print -quit 2>/dev/null)"
key_mode="$(sudo stat -c '%a' /etc/ssl/private/devops.key 2>/dev/null)"
if [[ -z "$web_writable" && "$key_mode" == 600 ]]; then
    web_permissions=ok
else
    web_permissions=fail
fi
check "Web files not world-writable and private key mode 600" "ok" "$web_permissions"
echo "[5] Containerization"
check "Docker service active" "ok" "$(systemctl is-active --quiet docker && echo ok || echo fail)"
db_health="$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null || echo missing)"
check "Database container healthy" "healthy" "$db_health"
listeners="$(ss -tlnH 2>/dev/null | awk '$4 ~ /:(5000|5432)$/ {print $4}')"
if [[ "$listeners" == "127.0.0.1:5000" ]]; then
    port_status=ok
else
    port_status="${listeners:-missing}"
fi
check "App bound only to 127.0.0.1:5000; DB port unpublished" "ok" "$port_status"
env_mode="$(stat -c '%a' /home/devops/app/.env 2>/dev/null || echo missing)"
check "App .env mode 600" "600" "$env_mode"
echo "Passed: $PASS; failed: $FAIL"
[[ $FAIL -eq 0 ]]
