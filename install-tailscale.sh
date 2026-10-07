#!/bin/bash
set -e

AUTHKEY="$1"
HOSTNAME="$2"

if [ -z "$AUTHKEY" ] || [ -z "$HOSTNAME" ]; then
    echo "用法：sudo bash install-tailscale.sh <AuthKey> <Hostname>"
    exit 1
fi

ARCH=$(uname -m)

case "$ARCH" in
    x86_64) A=amd64 ;;
    aarch64|arm64) A=arm64 ;;
    armv7l|armv6l) A=arm ;;
    i386|i686) A=386 ;;
    *)
        echo "不支援的架構: $ARCH"
        exit 1
        ;;
esac

LATEST=$(curl -kfsSL https://pkgs.tailscale.com/stable/ \
    | grep -o "tailscale_[0-9.]*_${A}\.tgz" \
    | head -n1 \
    | sed -E "s/tailscale_([0-9.]+)_.*/\1/")

NEED_DOWNLOAD=1

if [ -f /root/tailscale.tgz ]; then
    TMPDIR=$(mktemp -d)

    if tar -xzf /root/tailscale.tgz -C "$TMPDIR" --strip-components=1 2>/dev/null \
       && [ -x "$TMPDIR/tailscale" ]; then

        LOCAL=$("$TMPDIR/tailscale" version 2>/dev/null | head -n1 | awk '{print $1}')

        echo "本機壓縮檔版本: $LOCAL"
        echo "官方最新版本: $LATEST"

        if [ "$LOCAL" = "$LATEST" ]; then
            NEED_DOWNLOAD=0
            echo "版本相同，直接使用現有 /root/tailscale.tgz"
        else
            echo "版本不同，重新下載最新版"
        fi
    else
        echo "現有 /root/tailscale.tgz 無法正常讀取，重新下載"
    fi

    rm -rf "$TMPDIR"
fi

if [ "$NEED_DOWNLOAD" = "1" ]; then
    echo "下載 Tailscale $LATEST ..."
    curl -kfL \
        "https://pkgs.tailscale.com/stable/tailscale_${LATEST}_${A}.tgz" \
        -o /root/tailscale.tgz
fi

systemctl stop tailscale-portable.service 2>/dev/null || true

rm -rf /root/tailscale-run
mkdir -p /root/tailscale-run /root/tailscale-state

tar -xzf /root/tailscale.tgz \
    -C /root/tailscale-run \
    --strip-components=1

chmod 755 \
    /root/tailscale-run/tailscaled \
    /root/tailscale-run/tailscale

FIRST=0
[ -f /root/tailscale-state/tailscaled.state ] || FIRST=1

printf "%s\n" \
"[Unit]" \
"Description=Tailscale Portable" \
"After=network-online.target" \
"Wants=network-online.target" \
"" \
"[Service]" \
"Type=simple" \
"ExecStart=/root/tailscale-run/tailscaled --state=/root/tailscale-state/tailscaled.state" \
"Restart=always" \
"RestartSec=3" \
"" \
"[Install]" \
"WantedBy=multi-user.target" \
> /etc/systemd/system/tailscale-portable.service

systemctl daemon-reload
systemctl enable tailscale-portable.service
systemctl restart tailscale-portable.service

sleep 3

if [ "$FIRST" = "1" ]; then
    echo "第一次加入 Tailscale..."
    /root/tailscale-run/tailscale up \
        --auth-key="$AUTHKEY" \
        --hostname="$HOSTNAME"
else
    echo "已存在 state，沿用原本身分..."
    /root/tailscale-run/tailscale up \
        --hostname="$HOSTNAME"
fi

echo
echo "Tailscale 安裝完成"
echo "主機名稱：$HOSTNAME"
echo "State：/root/tailscale-state/tailscaled.state"
echo "服務：tailscale-portable.service"
