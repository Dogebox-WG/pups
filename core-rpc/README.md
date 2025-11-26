<div align="center">
  <img src="../docs/img/dogebox-logo.png" alt="Dogebox Logo"/>
  <p>Core RPC</p>
</div>

This pup exposes your Dogecoin Core node's RPC interface externally via an authenticated proxy pup.

- **Dependencies**: Requires a Dogecoin Core pup linked as the `core-rpc` provider.
- **Config**: You choose an external `RPC_USERNAME` / `RPC_PASSWORD`; the proxy translates these to Core's internal credentials.
- **Access**: Once running, RPC is available on port `22555` on your Dogebox host.

Example call from a remote machine:

```bash
curl --user "<your-username>:<your-password>" \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"1.0","id":"test","method":"getblockcount","params":[]}' \
  http://<dogebox-host-ip>:22555/
```

# Core RPC

This pup provides authenticated external access to your Dogecoin Core node's RPC interface.

## Why Use This?

By default, Dogecoin Core's RPC is only accessible internally (by other pups on your Dogebox). If you need to connect external applications, wallets, or services to your Core node's RPC, install this pup.

## How It Works

- **Core pup** runs dogecoind with RPC enabled internally (no external access)
- **Core RPC pup** provides an authenticated proxy to Core's RPC
- External clients connect to Core RPC with your configured credentials
- Core RPC validates credentials and forwards requests to Core

## Setup

1. Install the **Dogecoin Core** pup first
2. Install this **Core RPC** pup
3. Go to **Providers** and link Core RPC's `core-rpc` dependency to your Core pup
4. Configure your RPC credentials in this pup's configuration

## Configuration

| Setting | Required | Description |
|---------|----------|-------------|
| RPC Username | Yes | Username for external RPC authentication |
| RPC Password | Yes | Password for external RPC authentication |

## Connecting

Once configured, connect to your Dogebox's RPC at:
```
http://YOUR_DOGEBOX_IP:22555
```

Use Basic Authentication with your configured username and password.

## Security Notes

- Always use strong, unique passwords for RPC access
- RPC access allows control over your node - only enable if needed
- Consider using Tailscale or similar for secure remote access instead of exposing RPC publicly
- The RPC port is exposed on your local network by default

