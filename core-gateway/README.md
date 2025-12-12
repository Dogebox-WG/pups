<div align="center">
  <img src="./logo.png" alt="Dogebox Logo with down arrow"/>
  <p>Dogecoin Core Gateway</p>
</div>

This pup exposes your Dogecoin Core node's RPC and ZMQ interfaces externally via a proxy.

- **Dependencies**: Requires a Dogecoin Core pup linked as the `core-rpc` and `core-zmq` provider.
- **Config**: Set your RPC authentication credentials.
- **Access**: Once running, RPC is available on port `22555` and ZMQ on port `28332` on your Dogebox host.

## Features

## Setup

1. Install the **Dogecoin Core** pup first
2. Install this **Dogecoin Core Gateway** pup
3. Go to **Providers** and link Dogecoin Core Gateway's dependencies to your Core pup:
   - `core-rpc` for RPC access
   - `core-zmq` for ZMQ access
4. Configure RPC credentials

## Configuration

| Setting | Required | Description |
|---------|----------|-------------|
| RPC Username | Yes | Username for external RPC authentication |
| RPC Password | Yes | Password for external RPC authentication |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 22555 | TCP/HTTP | Dogecoin Core RPC |
| 28332 | TCP | Dogecoin Core ZMQ |

## Security Notes

- Always use strong, unique passwords for RPC access
- RPC access allows control over your node
- ZMQ is read-only but exposes blockchain data in real-time
- Consider using Tailscale or similar for secure remote access instead of exposing ports publicly
- Both ports are exposed on your local network by default when enabled

### Example RPC test

```bash
curl --user "<your-username>:<your-password>" \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"1.0","id":"test","method":"getblockcount","params":[]}' \
  http://<dogebox-host-ip>:22555/
```
