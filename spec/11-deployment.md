# 11. Deployment

[← HTTP Server](10-http-server.md) | [Index](00-index.md) | [Next: Appendices →](12-appendices.md)

---

## 11.1 Systemd Service

When installed via Debian package, a systemd service is included at `/lib/systemd/system/machinestate.service`.

## 11.2 Configuration

The service reads configuration from `/etc/default/machinestate`:

```bash
# Port for HTTP server
MACHINESTATE_PORT=8080
```

## 11.3 Usage

```bash
# Enable and start the service
sudo systemctl enable machinestate
sudo systemctl start machinestate

# Check status
sudo systemctl status machinestate

# View logs
journalctl -u machinestate -f

# Restart after configuration change
sudo systemctl restart machinestate
```

## 11.4 Security

The service runs with security hardening:

- `NoNewPrivileges=true`
- `ProtectSystem=strict`
- `ProtectHome=read-only`
- `PrivateTmp=true`

---

[← HTTP Server](10-http-server.md) | [Index](00-index.md) | [Next: Appendices →](12-appendices.md)
