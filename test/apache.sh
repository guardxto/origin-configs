#!/bin/sh
# httpd -t on apache/remoteip.conf and apache/site.conf inside the official
# httpd:2.4 image, with paths moved into a scratch directory.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/ssl" "$tmp/log"
cp "$CERT_DIR/fullchain.pem" "$CERT_DIR/privkey.pem" "$tmp/ssl/"

for f in remoteip.conf site.conf; do
  sed -e "s#/etc/ssl/example.com#$tmp/ssl#g" "$here/apache/$f" > "$tmp/$f"
done

cat > "$tmp/test.conf" <<CONF
LoadModule remoteip_module modules/mod_remoteip.so
LoadModule ssl_module modules/mod_ssl.so
LoadModule proxy_module modules/mod_proxy.so
LoadModule proxy_http_module modules/mod_proxy_http.so
Define APACHE_LOG_DIR $tmp/log
Listen 443
Include $tmp/remoteip.conf
Include $tmp/site.conf
CONF

httpd -t -c "Include $tmp/test.conf"
