# Paxmata Starknet contracts

Cairo smart contracts and tests for Paxmata.

## Requirements

- Scarb 2.13.1
- Starknet Foundry 0.54.1

## Build and test

```sh
scarb build
scarb test
```

`src/` contains the contracts, components, and test mocks. `tests/` contains integration tests; component tests are in `src/components/tests/`.

Deployment accounts, credentials, RPC configuration, and build outputs are intentionally excluded. Signing keys in tests are deterministic test fixtures only.
