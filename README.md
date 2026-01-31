# nightly-maintenance-batch
cronを使って夜間に自動でメンテナンスを行います。実行開始と終了時にDiscordへwebhookで通知を飛ばせます。

## 設定方法
1. `nightly_maintenance,sh`を`/usr/local/bin/nightly_maintenance.sh`に置いて、
2. `nightly_maintenance.sh`の`DISCORD_WEBHOOK_URL=`を設定して、
3. `sudo chmod +x /usr/local/bin/nightly_maintenance.sh`で実行権限を付与して、
4. `sudo crontab -e`でrootのcron設定を開き、
5. `0 2 * * * /usr/local/bin/nightly_maintenance.sh` を追加して毎日午前2時に実行するように設定 (時間は任意)。