<div align="center">
  <p>Indexer</p>
</div>

This pup runs the Dogecoin Indexer service against a linked Dogecoin Core pup.

## What it does

- consumes `core-rpc` and `core-zmq`
- stores its local index in managed Postgres data under `/storage/postgres`
- maintains an optional cached balances table for faster balance lookups
- exposes only the Indexer HTTP API to other pups
- reports Core connection status, indexed height, and Core height as pup stats

