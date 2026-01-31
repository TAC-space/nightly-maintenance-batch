#!/bin/bash

# ==============================================================================
# Nightly Maintenance Batch Script for TAC Server
# (C) 2026 YANASE Ryota, Tokyo City University Aerospace Community
# Licensed under the MIT license
# ==============================================================================

# 設定方法: 
# 1. /usr/local/bin/nightly_maintenance.sh に置いて、
# 2. sudo chmod +x /usr/local/bin/nightly_maintenance.sh して実行権限を付与して、
# 3. sudo crontab -e でrootのcron設定を開き、
# 4. 0 2 * * * /usr/local/bin/nightly_maintenance.sh を追加して毎日午前2時に実行するように設定 (時間は任意)。

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
LOGFILE="/var/log/nightly_maintenance.log" # ログファイルのパス
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin # PATH設定

# --- ログ開始 ---
{
echo "========================================================"
echo "Maintenance Started: $(date)"
echo "========================================================"

# ==============================================================================
# 1. 日次処理 (Daily Tasks) - 毎日実行
# ==============================================================================
echo "[Daily] System & Application Updates..."

# 1-1. システムパッケージの更新
# Nextcloud(Snap)もここで更新
apt-get update && apt-get upgrade -y
snap refresh

# 1-2. Dockerの掃除
# 停止中のコンテナ、リンク切れボリューム、danglingイメージを削除
docker system prune -f

# 1-3. Nextcloud: 画像プレビューの事前生成 (Daily)
# 新規追加分のサムネイルを生成
if nextcloud.occ app:list | grep -q "previewgenerator: enabled"; then
    echo "[Daily] Nextcloud: Pre-generating previews..."
    nextcloud.occ preview:pre-generate
else
    echo "[Daily] Nextcloud: Preview Generator app is not enabled. Skipping."
fi

# ==============================================================================
# 2. 週次処理 (Weekly Tasks) - 毎週日曜日に実行
# ==============================================================================
if [ "$(date +%u)" -eq 7 ]; then
    echo "--------------------------------------------------------"
    echo "[Weekly] Starting Weekly Tasks..."

    # 2-1. SSDへのTRIM発行 (重要)
    echo "[Weekly] Running fstrim for SSD..."
    fstrim -v -a

    # 2-2. HDD S.M.A.R.T. ショートテスト
    # /dev/sda, /dev/sdb のSMARTショートテストを実行
    echo "[Weekly] HDD SMART Short Test..."
    smartctl -t short /dev/sda
    smartctl -t short /dev/sdb

    # 2-3. Nextcloud: データベース構造の最適化
    echo "[Weekly] Nextcloud: Optimizing Database..."
    nextcloud.occ db:add-missing-indices --no-interaction
    nextcloud.occ db:add-missing-columns --no-interaction
    nextcloud.occ db:add-missing-primary-keys --no-interaction

    # 2-4. Nextcloud: ゴミ掃除
    echo "[Weekly] Nextcloud: Cleaning up trash and versions..."
    nextcloud.occ files:cleanup
    nextcloud.occ trashbin:cleanup --all-users
    nextcloud.occ versions:cleanup
fi

# ==============================================================================
# 3. 月次処理 (Monthly Tasks) - 毎月1日に実行
# ==============================================================================
if [ "$(date +%d)" -eq 01 ]; then
    echo "--------------------------------------------------------"
    echo "[Monthly] Starting Monthly Tasks..."

    # 3-1. HDD S.M.A.R.T. ロングテスト
    # ディスク全領域の読み取りテスト
    echo "[Monthly] HDD SMART Long Test..."
    smartctl -t long /dev/sda
    smartctl -t long /dev/sdb

    # 3-2. システムの掃除
    # 古いカーネルの削除とジャーナルログの圧縮
    echo "[Monthly] Removing old kernels and logs..."
    apt-get autoremove -y
    journalctl --vacuum-time=1mo
fi

echo "========================================================"
echo "Maintenance Finished: $(date)"
echo ""

} >> "$LOGFILE" 2>&1

exit 0