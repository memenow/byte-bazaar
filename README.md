# Byte Bazaar

A decentralized data marketplace built on Sui blockchain, enabling secure data trading, labeling tasks, and community governance.

## Overview

Byte Bazaar is a comprehensive platform that combines NFT-based data assets, marketplace functionality, task management, and DAO governance. It provides a complete ecosystem for data creators, labelers, validators, and consumers.

## Architecture

### Core Modules

```
byte_bazaar/
├── sources/
│   ├── entry.move              # Main entry point and capability management
│   ├── nft.move                # DataNFT implementation with royalties
│   ├── market.move             # Marketplace for trading DataNFTs
│   ├── task.move               # Data labeling task management
│   ├── dao.move                # Decentralized governance system
│   ├── revenue.move            # Revenue distribution logic
│   └── lib.move                # Shared utilities and types
└── tests/
    └── byte_bazaar_tests.move  # Comprehensive test suite
```

## Features

### 🎨 DataNFT System

- **Unique Data Assets**: Each dataset is represented as a unique NFT with metadata
- **Royalty System**: 5% global royalty on secondary sales
- **Transfer Policy**: Automated royalty collection via Sui's Kiosk system
- **Versioning**: Support for dataset updates with version tracking
- **Walrus Integration**: Storage tickets for decentralized data storage

### 🏪 Marketplace

- **Kiosk Integration**: Built on Sui's standard Kiosk framework
- **Automated Royalties**: Seamless royalty distribution on trades
- **Freeze Protection**: Prevents trading of frozen/disputed assets
- **Event Tracking**: Comprehensive marketplace event logging

### 📋 Task Management

- **Data Labeling**: Crowdsourced data annotation system
- **Golden Samples**: Quality control through reference data
- **Multi-Validator Consensus**: Democratic validation process
- **Escrow System**: Secure payment handling with dispute resolution
- **Deadline Management**: Time-bound task completion

### 🏛️ DAO Governance

- **Proposal System**: Community-driven decision making
- **Voting Mechanism**: Weighted voting with configurable parameters
- **Asset Management**: Freeze/unfreeze NFTs through governance
- **Upgrade Authority**: Controlled smart contract upgrades
- **Execution Framework**: Automated proposal execution

### 💰 Revenue Distribution

- **Multi-Recipient Royalties**: Flexible revenue sharing
- **Basis Points System**: Precise percentage allocations
- **Automatic Distribution**: Seamless payment splitting

## Capabilities & Permissions

The system uses capability-based access control:

- **`GovCap`**: DAO governance operations
- **`UploaderCap`**: Data upload and NFT minting
- **`LabelerCap`**: Task claiming and submission
- **`ValidatorCap`**: Task validation and review

## Getting Started

### Prerequisites

- [Sui CLI](https://docs.sui.io/build/install) installed
- Sui wallet configured
- Basic understanding of Move programming

### Installation

1. Clone the repository:

```bash
git clone https://github.com/memenow/byte-bazaar.git
cd byte-bazaar
```

2. Build the project:

```bash
sui move build
```

3. Run tests:

```bash
sui move test
```

### Deployment

1. Publish the package:

```bash
sui client publish --gas-budget 100000000
```

2. Note the package ID and update your configuration accordingly.

## Usage Examples

### Minting a DataNFT

```move
// Mint a new DataNFT with royalty information
let (nft, policy) = nft::mint_data_nft(
    &uploader_cap,
    &publisher,
    creator_address,
    data_hash,
    storage_url,
    license_hash,
    royalty_recipients,
    royalty_basis_points,
    ctx
);
```

### Creating a Labeling Task

```move
// Publish a new data labeling task
let task = task::publish_task(
    &uploader_cap,
    dataset_id,
    reward_coin,
    deadline,
    gold_hash, // Optional golden sample
    &clock,
    ctx
);
```

### DAO Proposal

```move
// Create a governance proposal
let action = dao::new_freeze_nft_action(nft_id, true);
let proposal = dao::create_proposal(
    &gov_cap,
    action,
    duration,
    &clock,
    ctx
);
```

## API Reference

### DataNFT Functions

- `mint_data_nft()` - Create new data NFT
- `update_data_nft()` - Update NFT metadata
- `pay_royalty_and_confirm()` - Handle royalty payments

### Marketplace Functions

- `list_nft()` - List NFT for sale
- `buy_nft()` - Purchase listed NFT

### Task Functions

- `publish_task()` - Create labeling task
- `claim_task()` - Claim task for completion
- `submit_task_result()` - Submit completed work
- `submit_review()` - Validate submitted work
- `finalize_task()` - Complete task and distribute rewards

### DAO Functions

- `create_proposal()` - Submit governance proposal
- `vote_on_proposal()` - Cast vote on proposal
- `tally_proposal()` - Count votes after deadline
- `execute_*_proposal()` - Execute approved proposals

## Events

The system emits comprehensive events for off-chain monitoring:

- **DataNFT Events**: `DataNFTMintedEvent`, `DataNFTUpdatedEvent`, `StorageTicketEvent`
- **Marketplace Events**: `NFTListedEvent`, `NFTPurchasedEvent`
- **Task Events**: `TaskPublishedEvent`, `TaskClaimedEvent`, `TaskCompletedEvent`
- **DAO Events**: `ProposalCreatedEvent`, `ProposalExecutedEvent`

## Security Considerations

- **Capability-based Access**: All sensitive operations require appropriate capabilities
- **Consensus Mechanisms**: Multi-validator approval for task completion
- **Escrow Protection**: Funds held securely until task completion
- **Upgrade Controls**: DAO-governed smart contract upgrades
- **Royalty Enforcement**: Automatic royalty collection prevents circumvention

## Testing

The project includes comprehensive tests covering:

- NFT minting and trading workflows
- Task lifecycle management
- DAO governance processes
- Error conditions and edge cases
- Royalty calculation accuracy

Run tests with:

```bash
sui move test
```

## License

This project is licensed under the Apache 2.0 License - see the [LICENSE](LICENSE) file for details.
