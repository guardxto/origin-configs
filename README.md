# origin-configs

Configuration examples for running a web server behind a reverse proxy or CDN: nginx, Caddy, Apache httpd and HAProxy, plus a firewall lock for the origin. They work with any proxy or CDN that publishes its address ranges and sets `X-Forwarded-For`.

Each example covers the same five jobs:

1. **Restore the visitor's address** from `X-Forwarded-For`, trusting the header only from the proxy's own ranges.
2. **Log both addresses**: the visitor and the proxy that connected.
3. **Pass the visitor on** to the application as `X-Real-IP`.
4. **Sensible defaults** for an origin: HSTS, cache headers for static files, keep-alive longer than the proxy's, and a `/healthz` endpoint.
5. **Close the origin** to everything except the proxy (`firewall/origin-lock.nft`).

The address ranges in every file are documentation examples (`192.0.2.0/24`, `2001:db8::/32`). Replace them with the list your provider publishes.

| Server | Files | Checked with |
| :-- | :-- | :-- |
| nginx | [`nginx/realip.conf`](nginx/realip.conf), [`nginx/site.conf`](nginx/site.conf) | `nginx -t` on nginx 1.22 (Debian 12) and in CI on `nginx:stable` and `nginx:mainline` |
| Caddy 2.8+ | [`caddy/Caddyfile`](caddy/Caddyfile) | `caddy validate` in CI on `caddy:2` |
| Apache httpd 2.4 | [`apache/remoteip.conf`](apache/remoteip.conf), [`apache/site.conf`](apache/site.conf) | `httpd -t` in CI on `httpd:2.4` |
| HAProxy 2.2+ | [`haproxy/haproxy.cfg`](haproxy/haproxy.cfg), [`haproxy/trusted-proxies.lst`](haproxy/trusted-proxies.lst) | `haproxy -c` in CI on `haproxy:lts` |
| nftables | [`firewall/origin-lock.nft`](firewall/origin-lock.nft) | `nft -c` on Debian 12 and in CI |

CI runs on every change and weekly, see [`.github/workflows/validate.yml`](.github/workflows/validate.yml).

## Why the trusted list matters

Behind a proxy, every connection comes from the proxy, and the visitor's address arrives in a header. Anyone can send that header. Trust it from the whole internet and every visitor can choose the address your logs, rate limits and allow lists see. Trust it only from the proxy's ranges and a forged header from anywhere else is ignored.

`real_ip_recursive on` (nginx), `trusted_proxies_strict` (Caddy) and `RemoteIPTrustedProxy` (Apache) all read the header from the right and stop at the first address that is not trusted. That way a visitor cannot push a fake address in front of the real one. The [nginx real IP guide](https://guardx.to/learning/nginx-real-ip) shows the log lines that prove it, header by header, and the [X-Forwarded-For guide](https://guardx.to/learning/x-forwarded-for-header) explains which entry to believe.

## Keep the list current

Providers add and retire ranges. [`scripts/update-ranges.sh`](scripts/update-ranges.sh) rebuilds nginx's list from the plain-text lists a provider publishes, runs `nginx -t` and only then reloads:

```sh
SOURCES="https://example.net/ips-v4 https://example.net/ips-v6" ./scripts/update-ranges.sh
```

It refuses a short download, does nothing when the list is unchanged, and puts the previous file back if `nginx -t` fails. Include the generated `/etc/nginx/conf.d/realip-trusted.conf` instead of the example `set_real_ip_from` lines. These cases were tested against local lists: a good list, an unchanged list, a truncated list, a range nginx rejects, an unreachable source and a missing `SOURCES`.

## Close the origin

Restoring addresses does not stop anyone from skipping the proxy and connecting to the origin directly. [`firewall/origin-lock.nft`](firewall/origin-lock.nft) accepts ports 80 and 443 only from the proxy's ranges and leaves every other rule on the host alone:

```sh
nft -c -f firewall/origin-lock.nft   # check
nft -f firewall/origin-lock.nft      # load (replaces its own table when run again)
```

Do this in the firewall, not with `allow`/`deny` in nginx: after the address rewrite those rules see the visitor, not the proxy. More on this in [how to hide your origin IP](https://guardx.to/learning/how-to-hide-your-origin-ip).

## Pitfalls

- **Trusting too much.** A range that contains addresses anyone can rent, or `0.0.0.0/0`, lets anyone choose their address.
- **Lists that override each other.** In nginx, a `set_real_ip_from` inside a `server` block replaces the list from `http` instead of adding to it.
- **`add_header` in a location** drops every `add_header` from the server block. That is why `nginx/site.conf` repeats HSTS in the static-file location.
- **Forwarding the chain.** After the rewrite, `$proxy_add_x_forwarded_for` names the visitor twice. Pass `$remote_addr` and let the application trust only the web server.
- **Rate limits before the rewrite.** Without the rewrite, all visitors share the proxy's address and its limit bucket, and real users get 429s.
- **HAProxy rule order.** Decide on the connecting address before `set-src`; after it, `src` is the visitor.

## License

[MIT](LICENSE). Found a mistake or want another server? [Open an issue](https://github.com/guardxto/origin-configs/issues).

---

Maintained by [GuardX](https://guardx.to): WAF, DDoS protection and CDN for websites and APIs, operated in the EU.
