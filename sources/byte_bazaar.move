/// Byte Bazaar - Decentralized Data Marketplace
/// A comprehensive data marketplace with NFT minting, trading, task management, and DAO governance
module byte_bazaar::byte_bazaar {
    // === Imports ===
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::url::{Self, Url};
    use sui::event;
    use sui::clock::{Self, Clock};
    use sui::vec_map::{Self, VecMap};
    use sui::kiosk::{Self, Kiosk, KioskOwnerCap};
    use sui::transfer_policy::{Self, TransferPolicy, TransferPolicyCap};
    use std::vector;
    use std::option::{Self, Option};

    // === Error Constants ===
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_INVALID_ROYALTY: u64 = 2;
    const E_INVALID_STATUS: u64 = 3;
    const E_TASK_NOT_OPEN: u64 = 4;
    const E_TASK_NOT_IN_PROGRESS: u64 = 5;
    const E_TASK_NOT_IN_REVIEW: u64 = 6;
    const E_ALREADY_CLAIMED: u64 = 7;
    const E_INSUFFICIENT_ESCROW: u64 = 8;
    const E_DEADLINE_PASSED: u64 = 9;
    const E_INVALID_VALIDATOR: u64 = 10;
    const E_PROPOSAL_NOT_ACTIVE: u64 = 11;
    const E_PROPOSAL_EXPIRED: u64 = 12;
    const E_NFT_FROZEN: u64 = 13;
    const E_INVALID_PRICE: u64 = 14;
    const E_INSUFFICIENT_PAYMENT: u64 = 15;

    // === Status Constants ===
    const TASK_STATUS_OPEN: u8 = 0;
    const TASK_STATUS_IN_PROGRESS: u8 = 1;
    const TASK_STATUS_IN_REVIEW: u8 = 2;
    const TASK_STATUS_COMPLETED: u8 = 3;
    const TASK_STATUS_DISPUTED: u8 = 4;

    const PROPOSAL_STATUS_ACTIVE: u8 = 0;
    const PROPOSAL_STATUS_PASSED: u8 = 1;
    const PROPOSAL_STATUS_REJECTED: u8 = 2;
    const PROPOSAL_STATUS_EXECUTED: u8 = 3;

    // === Royalty Constants ===
    const BASIS_POINTS_TOTAL: u16 = 10000; // 100%
    const MIN_ESCROW_PERCENTAGE: u16 = 1000; // 10%

    // === Core Structs ===

    /// DataNFT represents a data asset NFT on-chain.
    /// 
    /// Fields:
    /// - `id`: Unique identifier.
    /// - `creator`: Address of the minter.
    /// - `data_hash`: SHA-256 hash of the asset.
    /// - `storage_url`: Off-chain storage reference (walrus://CID).
    /// - `license_hash`: Hash of license metadata.
    /// - `royalty`: Royalty distribution configuration.
    /// - `active`: Indicates if NFT can be traded.
    /// - `version`: Metadata version number.
    public struct DataNFT has key, store {
        id: UID,
        creator: address,
        data_hash: vector<u8>,
        storage_url: Url,
        license_hash: vector<u8>,
        royalty: vector<RoyaltyInfo>,
        active: bool,
        version: u64,
    }

    /// RoyaltyInfo defines revenue split for a recipient.
    ///
    /// Fields:
    /// - `recipient`: Address receiving royalties.
    /// - `basis_points`: Share out of 10000.
    public struct RoyaltyInfo has store, copy, drop {
        recipient: address,
        basis_points: u16,
    }

    /// Task tracks a data-labeling assignment.
    ///
    /// Fields:
    /// - `id`: Unique task ID.
    /// - `dataset`: ID of associated DataNFT.
    /// - `reward`: Primary reward coin.
    /// - `escrow`: Escrowed portion (10%).
    /// - `deadline`: Deadline timestamp (ms).
    /// - `labeler`: Optional address of claimant.
    /// - `validators`: Addresses who reviewed.
    /// - `pass_count`: Number of passes.
    /// - `status`: Current task stage.
    /// - `result_hash`: Hash of submitted result.
    public struct Task has key, store {
        id: UID,
        dataset: ID,
        reward: Coin<SUI>,
        escrow: Coin<SUI>,
        deadline: u64,
        labeler: Option<address>,
        validators: vector<address>,
        pass_count: u8,
        status: u8,
        result_hash: Option<vector<u8>>,
    }

    /// Listing tracks an NFT listed for sale.
    ///
    /// Fields:
    /// - `id`: Listing UID.
    /// - `nft_id`: Underlying NFT ID.
    /// - `seller`: Seller address.
    /// - `price`: Listing price in SUI.
    /// - `kiosk_id`: Kiosk object ID.
    public struct Listing has key {
        id: UID,
        nft_id: ID,
        seller: address,
        price: u64,
        kiosk_id: ID,
    }

    /// Proposal defines a DAO governance action.
    ///
    /// Fields:
    /// - `id`: Proposal UID.
    /// - `proposer`: Creator address.
    /// - `action`: Encoded action bytes.
    /// - `aye_votes`: Total supporting votes.
    /// - `nay_votes`: Total opposing votes.
    /// - `status`: Proposal lifecycle stage.
    /// - `deadline`: Voting deadline (ms).
    /// - `voters`: Map of addresses to vote support.
    public struct Proposal has key, store {
        id: UID,
        proposer: address,
        action: vector<u8>,
        aye_votes: u64,
        nay_votes: u64,
        status: u8,
        deadline: u64,
        voters: VecMap<address, bool>,
    }

    /// AdminCap grants DAO administrative rights.
    public struct AdminCap has key, store {
        id: UID,
    }

    /// MarketplaceCap grants marketplace management rights.
    public struct MarketplaceCap has key {
        id: UID,
    }

    // === Events ===

    /// Emitted when a DataNFT is minted.
    public struct DataNFTMinted has copy, drop {
        nft_id: ID,
        creator: address,
        data_hash: vector<u8>,
    }

    /// Emitted when DataNFT metadata is updated.
    public struct DataNFTUpdated has copy, drop {
        nft_id: ID,
        version: u64,
    }

    /// Emitted when a task is published.
    public struct TaskPublished has copy, drop {
        task_id: ID,
        dataset: ID,
        reward_amount: u64,
    }

    /// Emitted when a task is claimed.
    public struct TaskClaimed has copy, drop {
        task_id: ID,
        labeler: address,
    }

    /// Emitted when a task result is submitted.
    public struct TaskCompleted has copy, drop {
        task_id: ID,
        result_hash: vector<u8>,
    }

    /// Emitted when an NFT is listed.
    public struct NFTListed has copy, drop {
        listing_id: ID,
        nft_id: ID,
        price: u64,
    }

    /// Emitted when an NFT is purchased.
    public struct NFTPurchased has copy, drop {
        nft_id: ID,
        buyer: address,
        price: u64,
    }

    /// Emitted when a proposal is created.
    public struct ProposalCreated has copy, drop {
        proposal_id: ID,
        proposer: address,
    }

    /// Emitted when a proposal is executed.
    public struct ProposalExecuted has copy, drop {
        proposal_id: ID,
    }

    // === Init Function ===

    /// Initializes module: grants Admin and Marketplace capabilities.
    /// 
    /// @param ctx Transaction context.
    public fun init(ctx: &mut TxContext) {
        let admin_cap = AdminCap { id: object::new(ctx) };
        let marketplace_cap = MarketplaceCap { id: object::new(ctx) };
        transfer::transfer(admin_cap, tx_context::sender(ctx));
        transfer::transfer(marketplace_cap, tx_context::sender(ctx));
    }

    // === DataNFT Module Functions ===

    /// Mints a new DataNFT with royalty distribution.
    ///
    /// @param creator Address creating the NFT.
    /// @param data_hash SHA-256 asset hash.
    /// @param storage_url Off-chain storage reference bytes.
    /// @param license_hash License metadata hash.
    /// @param royalty_recipients List of royalty addresses.
    /// @param royalty_basis_points Corresponding basis points.
    /// @param ctx Transaction context.
    /// @return Newly minted DataNFT.
    /// @abort_E_INVALID_ROYALTY If totals do not equal 100%.
    public fun mint_data_nft(
        creator: address,
        data_hash: vector<u8>,
        storage_url: vector<u8>,
        license_hash: vector<u8>,
        royalty_recipients: vector<address>,
        royalty_basis_points: vector<u16>,
        ctx: &mut TxContext
    ): DataNFT {
        assert!(vector::length(&royalty_recipients) == vector::length(&royalty_basis_points), E_INVALID_ROYALTY);
        let mut total_royalty = 0u16;
        let mut royalty = vector::empty<RoyaltyInfo>();
        let mut i = 0;
        while (i < vector::length(&royalty_recipients)) {
            let basis_points = *vector::borrow(&royalty_basis_points, i);
            total_royalty = total_royalty + basis_points;
            vector::push_back(&mut royalty, RoyaltyInfo {
                recipient: *vector::borrow(&royalty_recipients, i),
                basis_points,
            });
            i = i + 1;
        };
        assert!(total_royalty == BASIS_POINTS_TOTAL, E_INVALID_ROYALTY);
        let nft = DataNFT {
            id: object::new(ctx),
            creator,
            data_hash,
            storage_url: url::new_unsafe_from_bytes(storage_url),
            license_hash,
            royalty,
            active: true,
            version: 1,
        };
        event::emit(DataNFTMinted {
            nft_id: object::uid_to_inner(&nft.id),
            creator,
            data_hash,
        });
        nft
    }

    /// Updates metadata of an existing DataNFT.
    ///
    /// @param nft Mutable reference to DataNFT.
    /// @param storage_url Optional new storage reference.
    /// @param license_hash Optional new license hash.
    /// @param ctx Transaction context.
    /// @abort_E_NOT_AUTHORIZED If caller is not creator.
    public fun update_data_nft(
        nft: &mut DataNFT,
        mut storage_url: Option<vector<u8>>,
        mut license_hash: Option<vector<u8>>,
        ctx: &mut TxContext
    ) {
        assert!(nft.creator == tx_context::sender(ctx), E_NOT_AUTHORIZED);
        if (option::is_some(&storage_url)) {
            nft.storage_url = url::new_unsafe_from_bytes(option::extract(&mut storage_url));
        };
        if (option::is_some(&license_hash)) {
            nft.license_hash = option::extract(&mut license_hash);
        };
        nft.version = nft.version + 1;
        event::emit(DataNFTUpdated {
            nft_id: object::uid_to_inner(&nft.id),
            version: nft.version,
        });
    }

    /// Toggles active status of a DataNFT.
    ///
    /// @param _ Admin capability reference.
    /// @param nft Mutable DataNFT reference.
    /// @param active New active flag.
    public fun set_nft_active_status(
        _: &AdminCap,
        nft: &mut DataNFT,
        active: bool
    ) {
        nft.active = active;
    }

    // === Marketplace Module Functions ===

    /// Lists a DataNFT for sale in a kiosk.
    ///
    /// @param kiosk Mutable kiosk reference.
    /// @param kiosk_cap Kiosk owner capability.
    /// @param nft DataNFT to list.
    /// @param price Sale price in SUI.
    /// @param ctx Transaction context.
    /// @abort_E_NFT_FROZEN If NFT is frozen.
    /// @abort_E_INVALID_PRICE If price is zero.
    public fun list_nft(
        kiosk: &mut Kiosk,
        kiosk_cap: &KioskOwnerCap,
        nft: DataNFT,
        price: u64,
        ctx: &mut TxContext
    ) {
        assert!(nft.active, E_NFT_FROZEN);
        assert!(price > 0, E_INVALID_PRICE);
        let nft_id = object::uid_to_inner(&nft.id);
        kiosk::place(kiosk, kiosk_cap, nft);
        kiosk::list<DataNFT>(kiosk, kiosk_cap, nft_id, price);
        event::emit(NFTListed {
            listing_id: nft_id,
            nft_id,
            price,
        });
    }

    /// Buys a DataNFT and distributes royalties.
    ///
    /// @param kiosk Mutable kiosk reference.
    /// @param kiosk_cap Kiosk owner capability.
    /// @param nft_id ID of NFT to purchase.
    /// @param payment Coin used for payment.
    /// @param ctx Transaction context.
    /// @return Purchased DataNFT.
    public fun buy_nft(
        kiosk: &mut Kiosk,
        kiosk_cap: &KioskOwnerCap,
        nft_id: ID,
        payment: Coin<SUI>,
        ctx: &mut TxContext
    ): DataNFT {
        let price = coin::value(&payment);
        let nft = kiosk::take<DataNFT>(kiosk, kiosk_cap, nft_id);
        assert!(nft.active, E_NFT_FROZEN);
        split_revenue(payment, &nft.royalty, ctx);
        event::emit(NFTPurchased {
            nft_id,
            buyer: tx_context::sender(ctx),
            price,
        });
        nft
    }

    // === Task Module Functions ===

    /// Publishes a new annotation task.
    ///
    /// @param dataset ID of DataNFT to label.
    /// @param reward Coin reward for labeler.
    /// @param deadline Task deadline timestamp.
    /// @param clock Clock reference for time checks.
    /// @param ctx Transaction context.
    /// @return New Task object.
    /// @abort_E_DEADLINE_PASSED If deadline is in the past.
    public fun publish_task(
        dataset: ID,
        mut reward: Coin<SUI>,
        deadline: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): Task {
        assert!(deadline > clock::timestamp_ms(clock), E_DEADLINE_PASSED);
        let reward_amount = coin::value(&reward);
        let escrow_amount = (reward_amount * (MIN_ESCROW_PERCENTAGE as u64)) / (BASIS_POINTS_TOTAL as u64);
        let escrow = coin::split(&mut reward, escrow_amount, ctx);
        let task = Task {
            id: object::new(ctx),
            dataset,
            reward,
            escrow,
            deadline,
            labeler: option::none(),
            validators: vector::empty(),
            pass_count: 0,
            status: TASK_STATUS_OPEN,
            result_hash: option::none(),
        };
        event::emit(TaskPublished {
            task_id: object::uid_to_inner(&task.id),
            dataset,
            reward_amount,
        });
        task
    }

    /// Claims an annotation task.
    ///
    /// @param task Mutable Task reference.
    /// @param escrow Coin covering required escrow.
    /// @param clock Clock reference for deadline check.
    /// @param ctx Transaction context.
    /// @abort_E_TASK_NOT_OPEN If not open.
    /// @abort_E_INSUFFICIENT_ESCROW If escrow insufficient.
    public fun claim_task(
        task: &mut Task,
        escrow: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(task.status == TASK_STATUS_OPEN, E_TASK_NOT_OPEN);
        assert!(clock::timestamp_ms(clock) < task.deadline, E_DEADLINE_PASSED);
        assert!(option::is_none(&task.labeler), E_ALREADY_CLAIMED);
        let escrow_amount = coin::value(&escrow);
        let required_escrow = coin::value(&task.escrow);
        assert!(escrow_amount >= required_escrow, E_INSUFFICIENT_ESCROW);
        coin::join(&mut task.escrow, escrow);
        task.labeler = option::some(tx_context::sender(ctx));
        task.status = TASK_STATUS_IN_PROGRESS;
        event::emit(TaskClaimed {
            task_id: object::uid_to_inner(&task.id),
            labeler: tx_context::sender(ctx),
        });
    }

    /// Submits labeling result for review.
    ///
    /// @param task Mutable Task reference.
    /// @param result_hash Hash of labeling output.
    /// @param ctx Transaction context.
    /// @abort_E_TASK_NOT_IN_PROGRESS If not in progress.
    /// @abort_E_NOT_AUTHORIZED If caller not labeler.
    public fun submit_task_result(
        task: &mut Task,
        result_hash: vector<u8>,
        ctx: &mut TxContext
    ) {
        assert!(task.status == TASK_STATUS_IN_PROGRESS, E_TASK_NOT_IN_PROGRESS);
        assert!(option::contains(&task.labeler, &tx_context::sender(ctx)), E_NOT_AUTHORIZED);
        task.result_hash = option::some(result_hash);
        task.status = TASK_STATUS_IN_REVIEW;
        event::emit(TaskCompleted {
            task_id: object::uid_to_inner(&task.id),
            result_hash,
        });
    }

    /// Records a validation review.
    ///
    /// @param task Mutable Task reference.
    /// @param pass True if review passed.
    /// @param ctx Transaction context.
    /// @abort_E_TASK_NOT_IN_REVIEW If review not open.
    /// @abort_E_INVALID_VALIDATOR If duplicate review.
    public fun submit_review(
        task: &mut Task,
        pass: bool,
        ctx: &mut TxContext
    ) {
        assert!(task.status == TASK_STATUS_IN_REVIEW, E_TASK_NOT_IN_REVIEW);
        let validator = tx_context::sender(ctx);
        assert!(!vector::contains(&task.validators, &validator), E_INVALID_VALIDATOR);
        vector::push_back(&mut task.validators, validator);
        if (pass) {
            task.pass_count = task.pass_count + 1;
        };
    }

    /// Finalizes task: distributes reward or disputes.
    ///
    /// @param task Mutable Task reference.
    /// @param ctx Transaction context.
    public fun finalize_task(
        task: &mut Task,
        ctx: &mut TxContext
    ) {
        assert!(task.status == TASK_STATUS_IN_REVIEW, E_TASK_NOT_IN_REVIEW);
        let total_validators = vector::length(&task.validators);
        if (total_validators >= 2 && task.pass_count >= 2) {
            task.status = TASK_STATUS_COMPLETED;
            if (option::is_some(&task.labeler)) {
                let labeler = *option::borrow(&task.labeler);
                let reward_amount = coin::value(&task.reward);
                let escrow_amount = coin::value(&task.escrow);
                let reward = coin::split(&mut task.reward, reward_amount, ctx);
                let escrow = coin::split(&mut task.escrow, escrow_amount, ctx);
                transfer::public_transfer(reward, labeler);
                transfer::public_transfer(escrow, labeler);
            };
        } else if (total_validators >= 2) {
            task.status = TASK_STATUS_DISPUTED;
        };
    }

    // === Revenue Module Functions ===

    /// Splits payment into royalty shares.
    ///
    /// @param payment Full payment coin.
    /// @param royalty Reference to royalty vector.
    /// @param ctx Transaction context.
    fn split_revenue(
        payment: Coin<SUI>,
        royalty: &vector<RoyaltyInfo>,
        ctx: &mut TxContext
    ) {
        let total_amount = coin::value(&payment);
        let mut remaining = payment;
        let mut i = 0;
        while (i < vector::length(royalty)) {
            let info = vector::borrow(royalty, i);
            let amount = (total_amount * (info.basis_points as u64)) / (BASIS_POINTS_TOTAL as u64);
            if (amount > 0 && coin::value(&remaining) >= amount) {
                let part = coin::split(&mut remaining, amount, ctx);
                transfer::public_transfer(part, info.recipient);
            };
            i = i + 1;
        };
        if (coin::value(&remaining) > 0 && vector::length(royalty) > 0) {
            let first = vector::borrow(royalty, 0);
            transfer::public_transfer(remaining, first.recipient);
        } else {
            coin::destroy_zero(remaining);
        };
    }

    // === DAO Module Functions ===

    /// Creates a new governance proposal.
    ///
    /// @param action Encoded action bytes.
    /// @param duration Voting duration in ms.
    /// @param clock Clock reference.
    /// @param ctx Transaction context.
    /// @return New Proposal object.
    public fun create_proposal(
        action: vector<u8>,
        duration: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): Proposal {
        let proposal = Proposal {
            id: object::new(ctx),
            proposer: tx_context::sender(ctx),
            action,
            aye_votes: 0,
            nay_votes: 0,
            status: PROPOSAL_STATUS_ACTIVE,
            deadline: clock::timestamp_ms(clock) + duration,
            voters: vec_map::empty(),
        };
        event::emit(ProposalCreated {
            proposal_id: object::uid_to_inner(&proposal.id),
            proposer: tx_context::sender(ctx),
        });
        proposal
    }

    /// Casts a vote on a proposal.
    ///
    /// @param proposal Mutable Proposal reference.
    /// @param support True to vote aye.
    /// @param voting_power Weight of vote.
    /// @param clock Clock reference.
    /// @param ctx Transaction context.
    public fun vote_on_proposal(
        proposal: &mut Proposal,
        support: bool,
        voting_power: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(proposal.status == PROPOSAL_STATUS_ACTIVE, E_PROPOSAL_NOT_ACTIVE);
        assert!(clock::timestamp_ms(clock) < proposal.deadline, E_PROPOSAL_EXPIRED);
        let voter = tx_context::sender(ctx);
        assert!(!vec_map::contains(&proposal.voters, &voter), E_INVALID_VALIDATOR);
        vec_map::insert(&mut proposal.voters, voter, support);
        if (support) {
            proposal.aye_votes = proposal.aye_votes + voting_power;
        } else {
            proposal.nay_votes = proposal.nay_votes + voting_power;
        };
    }

    /// Executes a passed proposal.
    ///
    /// @param _ Admin capability reference.
    /// @param proposal Mutable Proposal reference.
    /// @param clock Clock reference.
    public fun execute_proposal(
        _: &AdminCap,
        proposal: &mut Proposal,
        clock: &Clock
    ) {
        assert!(proposal.status == PROPOSAL_STATUS_ACTIVE, E_PROPOSAL_NOT_ACTIVE);
        assert!(clock::timestamp_ms(clock) >= proposal.deadline, E_PROPOSAL_EXPIRED);
        if (proposal.aye_votes > proposal.nay_votes) {
            proposal.status = PROPOSAL_STATUS_PASSED;
        } else {
            proposal.status = PROPOSAL_STATUS_REJECTED;
        };
        if (proposal.status == PROPOSAL_STATUS_PASSED) {
            proposal.status = PROPOSAL_STATUS_EXECUTED;
            event::emit(ProposalExecuted {
                proposal_id: object::uid_to_inner(&proposal.id),
            });
        };
    }

    // === Getter Functions ===

    /// Returns core DataNFT metadata.
    public fun get_nft_info(nft: &DataNFT): (address, vector<u8>, bool, u64) {
        (nft.creator, nft.data_hash, nft.active, nft.version)
    }

    /// Returns summary of a task.
    public fun get_task_info(task: &Task): (ID, u8, Option<address>, u64) {
        (task.dataset, task.status, task.labeler, task.deadline)
    }

    /// Returns summary of a proposal.
    public fun get_proposal_info(proposal: &Proposal): (address, u8, u64, u64, u64) {
        (proposal.proposer, proposal.status, proposal.aye_votes, proposal.nay_votes, proposal.deadline)
    }

    // === Test-only Functions ===

    /// Initializes module for testing.
    ///
    /// @param ctx Transaction context.
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}
