# ByteBazaar

ByteBazaar is a decentralized “Data App Store” built on the Sui blockchain. It mints Data NFTs for large-volume data assets (video, images, text, model weights, etc.), enabling on-chain proof of ownership and marketplace trading. Move smart contracts power real-time royalty splitting, annotation-task bounties, and DAO governance. Off-chain storage uses Walrus to fragment and store raw assets (20 GB+).

---

## Table of Contents

- [Features](#features)  
- [Architecture](#architecture)  
- [Getting Started](#getting-started)  
- [Project Layout](#project-layout)  
- [Move Modules & APIs](#move-modules--apis)  
- [Development & Testing](#development--testing)  
- [Contributing](#contributing)  
- [License](#license)  

---

## Features

- **DataNFT**  
  - Mint, update, and freeze/unfreeze on-chain data assets  
  - Store metadata, SHA-256 hash, storage URL, license hash, versioning  
  - Manage royalty recipients and basis points  
- **Marketplace**  
  - List and purchase DataNFTs via Sui kiosks  
  - Automated royalty revenue splitting per NFT configuration  
- **Annotation Tasks**  
  - Publish labeling tasks with SUI rewards and escrow  
  - Claim tasks, submit results, review and finalize outcomes  
  - On-chain events for task lifecycle  
- **DAO Governance**  
  - Create, vote on, and execute governance proposals  
  - Track aye/nay votes, enforce deadlines, emit events  
- **Admin & Marketplace Capabilities**  
  - AdminCap for DAO operations  
  - MarketplaceCap for listing and trading operations  

---

## Architecture

```
+----------------+      +----------------+      +----------------+
|   DataNFT      |<---->| Marketplace    |<---->|   Revenue      |
|  (NFT Module)  |      |    Module      |      |  Module        |
+----------------+      +----------------+      +----------------+
         ^                        |                     |
         |                        v                     v
    Royalty Split            Task Module           DAO Module
         |                        |                     |
         +--- Smart Contract Layer (Move on Sui) -----+
                         |
                   Off-chain Storage
                    (Walrus IPFS)
```

- **On-chain**: Move smart contracts in `sources/byte_bazaar.move`.  
- **Off-chain**: Walrus fragments raw files for decentralized storage.  

---

## Getting Started

### Prerequisites

- [Sui CLI & SDK](https://docs.sui.io/)  
- Rust toolchain (for Move framework)  
- Node.js (optional, for wallet integrations)

### Build & Publish

```bash
# Build Move modules
sui move build

# Run unit tests
sui move test
```

### Deploying to Testnet

```bash
# Publish package on Sui testnet
sui client publish --gas-budget 1000000
```

Capture the on-chain package ID and update your front-end or client.

---

## Project Layout

```text
├── Move.toml               # Package manifest
├── sources/
│   └── byte_bazaar.move    # Move module implementation
├── test/
│   └── byte_bazaar_tests.move  # Unit tests
├── LICENSE                 # Apache License 2.0
└── README.md               # Project documentation
```

---

## Move Modules & APIs

- **`init(&mut TxContext)`**  
  Initialize admin and marketplace capabilities.

- **DataNFT API**  
  - `mint_data_nft(...) → DataNFT`  
  - `update_data_nft(&mut DataNFT, ...)`  
  - `set_nft_active_status(&AdminCap, &mut DataNFT, bool)`

- **Marketplace API**  
  - `list_nft(&mut Kiosk, &KioskOwnerCap, DataNFT, u64, &mut TxContext)`  
  - `buy_nft(&mut Kiosk, &KioskOwnerCap, ID, Coin<SUI>, &mut TxContext) → DataNFT`

- **Task API**  
  - `publish_task(ID, Coin<SUI>, u64, &Clock, &mut TxContext) → Task`  
  - `claim_task(&mut Task, Coin<SUI>, &Clock, &mut TxContext)`  
  - `submit_task_result(&mut Task, vector<u8>, &mut TxContext)`  
  - `submit_review(&mut Task, bool, &mut TxContext)`  
  - `finalize_task(&mut Task, &mut TxContext)`

- **DAO API**  
  - `create_proposal(vector<u8>, u64, &Clock, &mut TxContext) → Proposal`  
  - `vote_on_proposal(&mut Proposal, bool, u64, &Clock, &mut TxContext)`  
  - `execute_proposal(&AdminCap, &mut Proposal, &Clock)`

Refer to `sources/byte_bazaar.move` for full signatures and error codes.

---

## Development & Testing

- **Unit Tests**: Defined in `test/byte_bazaar_tests.move`.  
- **Code Coverage**: Extend existing tests to cover edge cases.  
- **Linting**: Follow Sui Move style guidelines.  

---

## License

This project is licensed under the **Apache License 2.0**. See [LICENSE](LICENSE) for details.
