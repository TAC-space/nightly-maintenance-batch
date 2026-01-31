#!/bin/bash

# ==============================================================================
# Nightly Maintenance Batch Script for TAC Server
# (C) 2026 YANASE Ryota, Tokyo City University Aerospace Community
# Licensed under the MIT license
# ==============================================================================

# 設定方法: 
# 1. /usr/local/bin/nightly_maintenance.sh に置いて、
# 2. DISCORD_WEBHOOK_URL を自分のDiscord Webhook URLに書き換えて、
# 3. sudo chmod +x /usr/local/bin/nightly_maintenance.sh して実行権限を付与して、
# 4. sudo crontab -e でrootのcron設定を開き、
# 5. 0 2 * * * /usr/local/bin/nightly_maintenance.sh を追加して毎日午前2時に実行するように設定 (時間は任意)して、
# 6. sudo /usr/local/bin/nightly_maintenance.sh を手動で一度実行して動作確認（任意）。

# ログローテーションの設定 (定期的にログを削除する場合): 
# 1. 以下を設定
# /etc/logrotate.d/nightly_maintenance
# --------------------------------------
# /var/log/nightly_maintenance.log {
#     monthly
#     rotate 12
#     compress
#     missingok
#     notifempty
#     create 640 root adm
# }
# --------------------------------------
# 2. sudo logrotate -d /etc/logrotate.d/nightly_maintenance で設定をテスト
# 3. sudo logrotate -f /etc/logrotate.d/nightly_maintenance で手動実行 (任意)

# --- 設定 ---
LOGFILE="/var/log/nightly_maintenance.log"
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/xxxx/xxxx" # ← ★ここを書き換える
HOSTNAME=$(hostname)

# パス設定
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin

# Nextcloudコマンドの定義
OCC_CMD="/snap/bin/nextcloud.occ"

# --- Discord通知関数 ---
send_discord() {
    local title="$1"
    local description="$2"
    local color="$3"
    description=$(echo "$description" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    json_payload=$(cat <<EOF
{
  "username": "${HOSTNAME} Maintenance",
  "embeds": [{
    "title": "${title}",
    "description": "${description}",
    "color": ${color}
  }]
}
EOF
)
    curl -H "Content-Type: application/json" -d "$json_payload" "$DISCORD_WEBHOOK_URL" > /dev/null 2>&1
}

# 色コード
COLOR_BLUE=3447003
COLOR_GREEN=3066993
COLOR_RED=15158332

# --- 開始通知 ---
send_discord "Maintenance Started" "夜間メンテナンスを開始します。" "$COLOR_BLUE"

{
echo "========================================================"
echo "Maintenance Started: $(date)"
echo "========================================================"

ERROR_OCCURRED=0

handle_error() {
    echo "[ERROR] $1"
    ERROR_OCCURRED=1
}

# 日付判定
IS_SUNDAY=0
IS_FIRST_DAY=0
[ "$(date +%u)" -eq 7 ] && IS_SUNDAY=1
[ "$(date +%d)" -eq 01 ] && IS_FIRST_DAY=1

# ==============================================================================
# 1. 日次処理 (Daily Tasks)
# ==============================================================================
echo "[Daily] System & Application Updates..."

apt-get update && apt-get upgrade -y || handle_error "APT Update/Upgrade failed"
snap refresh || handle_error "Snap Refresh failed"
docker system prune -f || handle_error "Docker prune failed"

# Nextcloud Preview Generator
if $OCC_CMD app:list | grep -q "previewgenerator: enabled"; then
    echo "[Daily] Nextcloud: Pre-generating previews..."
    $OCC_CMD preview:pre-generate || handle_error "Nextcloud Preview Generation failed"
else
    echo "[Daily] Nextcloud: Preview Generator app is not enabled or not found. Skipping."
fi

# ==============================================================================
# 2. 週次処理 (Weekly Tasks) - 毎週日曜日
# ==============================================================================
if [ $IS_SUNDAY -eq 1 ]; then
    echo "--------------------------------------------------------"
    echo "[Weekly] Starting Weekly Tasks..."

    echo "[Weekly] Running fstrim for SSD..."
    fstrim -v -a || handle_error "fstrim failed"

    # Nextcloud DB & Cleanup
    echo "[Weekly] Nextcloud: Optimizing Database..."
    $OCC_CMD db:add-missing-indices --no-interaction || handle_error "Nextcloud DB Indices failed"
    $OCC_CMD db:add-missing-columns --no-interaction || handle_error "Nextcloud DB Columns failed"
    $OCC_CMD db:add-missing-primary-keys --no-interaction || handle_error "Nextcloud DB PrimaryKeys failed"

    echo "[Weekly] Nextcloud: Cleaning up..."
    $OCC_CMD files:cleanup || handle_error "Nextcloud Files Cleanup failed"
    $OCC_CMD trashbin:cleanup --all-users || handle_error "Nextcloud Trashbin Cleanup failed"
    $OCC_CMD versions:cleanup || handle_error "Nextcloud Versions Cleanup failed"
fi

# ==============================================================================
# 3. 月次処理 (Monthly Tasks) - 毎月1日
# ==============================================================================
if [ $IS_FIRST_DAY -eq 1 ]; then
    echo "--------------------------------------------------------"
    echo "[Monthly] Starting Monthly Tasks..."

    echo "[Monthly] Removing old kernels and logs..."
    apt-get autoremove -y || handle_error "APT Autoremove failed"
    journalctl --vacuum-time=1month || handle_error "Journalctl vacuum failed"
fi

# ==============================================================================
# 4. S.M.A.R.T. テスト (排他制御)
# ==============================================================================
echo "--------------------------------------------------------"
# 優先順位: 月初(Long) > 日曜(Short)
# 1日であればロングテストを実行。そうでなくて日曜日ならショートテストを実行。

if [ $IS_FIRST_DAY -eq 1 ]; then
    echo "[Monthly] HDD SMART Long Test (Priority High)..."
    smartctl -t long /dev/sda || handle_error "SMART Long Test (sda) failed"
    smartctl -t long /dev/sdb || handle_error "SMART Long Test (sdb) failed"

elif [ $IS_SUNDAY -eq 1 ]; then
    echo "[Weekly] HDD SMART Short Test..."
    smartctl -t short /dev/sda || handle_error "SMART Short Test (sda) failed"
    smartctl -t short /dev/sdb || handle_error "SMART Short Test (sdb) failed"
fi

echo "========================================================"
echo "Maintenance Finished: $(date)"
echo ""

} >> "$LOGFILE" 2>&1

# --- 終了通知 ---
LOG_TAIL=$(tail -n 10 "$LOGFILE")

if [ "$ERROR_OCCURRED" -eq 1 ]; then
    send_discord "Maintenance Completed with ERRORS" "メンテナンス中にエラーが発生しました。\nログを確認してください。\n\`\`\`\n${LOG_TAIL}\n\`\`\`" "$COLOR_RED"
else
    send_discord "Maintenance Finished Successfully" "全ての処理が完了しました。\n\`\`\`\n${LOG_TAIL}\n\`\`\`" "$COLOR_GREEN"
fi

exit 0