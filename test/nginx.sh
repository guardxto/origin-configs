#!/bin/sh
# nginx -t on nginx/realip.conf and nginx/site.conf, with every path moved into
# a scratch directory. Uses $CERT_DIR (fullchain.pem, privkey.pem) when set,
# otherwise makes a throwaway certificate with openssl.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/ssl" "$tmp/log" "$tmp/www"

if [ -n "${CERT_DIR:-}" ]; then
  cp "$CERT_DIR/fullchain.pem" "$CERT_DIR/privkey.pem" "$tmp/ssl/"
else
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=example.com \
    -keyout "$tmp/ssl/privkey.pem" -out "$tmp/ssl/fullchain.pem" 2>/dev/null
fi

for f in realip.conf site.conf; do
  sed -e "s#/etc/ssl/example.com#$tmp/ssl#g" \
      -e "s#/var/log/nginx#$tmp/log#g" \
      -e "s#/var/www/example.com#$tmp/www#g" "$here/nginx/$f" > "$tmp/$f"
done

cat > "$tmp/nginx.conf" <<CONF
pid $tmp/nginx.pid;
error_log $tmp/log/error.log;
events {}
http {
    access_log $tmp/log/access.log;
    client_body_temp_path $tmp/body;
    proxy_temp_path $tmp/proxy;
    fastcgi_temp_path $tmp/fastcgi;
    uwsgi_temp_path $tmp/uwsgi;
    scgi_temp_path $tmp/scgi;
    include $tmp/realip.conf;
    include $tmp/site.conf;
}
CONF

nginx -t -p "$tmp" -c "$tmp/nginx.conf"
