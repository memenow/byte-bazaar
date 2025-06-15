/// Module for managing the DataNFT lifecycle, including minting and metadata updates.
/// Implements a global transfer policy for royalties.
module byte_bazaar::nft {
    // === Imports ===
    use sui::object::{Self, UID, ID};
    use sui::package::{Self, Publisher};
    use sui::tx_context::{Self, TxContext};
    use sui::url::{Self, Url};
    use sui::event;
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::transfer_policy::{Self, TransferPolicy, TransferRequest, TransferPolicyCap};
    use std::vector;
    use std::option::{Self, Option};

    use byte_bazaar::lib::{Self, RoyaltyInfo};
    use byte_bazaar::entry::{UploaderCap, GovCap};
    use byte_bazaar::revenue;

    // === Constants ===
    const E_INVALID_ROYALTY: u64 = 2;
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_INSUFFICIENT_PAYMENT: u64 = 15;
    const BASIS_POINTS_TOTAL: u16 = 10000;
    const GLOBAL_ROYALTY_BPS: u16 = 500; // 5%

    // === Events ===
    public struct DataNFTMintedEvent has copy, drop { nft_id: ID, creator: address, data_hash: vector<u8> }
    public struct DataNFTUpdatedEvent has copy, drop { nft_id: ID, version: u64 }
    public struct StorageTicketEvent has copy, drop { nft_id: ID, storage_url: Url, version: u64 }

    // === Structs ===

    /// DataNFT represents a data asset NFT on-chain.
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

    // === Public Functions ===

    /// Mints a new DataNFT with royalty distribution and attaches a transfer policy.
    public fun mint_data_nft(
        _: &UploaderCap,
        publisher: &Publisher,
        creator: address,
        data_hash: vector<u8>,
        storage_url: vector<u8>,
        license_hash: vector<u8>,
        royalty_recipients: vector<address>,
        royalty_basis_points: vector<u16>,
        ctx: &mut TxContext
    ): (DataNFT, TransferPolicy<DataNFT>) {
        assert!(vector::length(&royalty_recipients) == vector::length(&royalty_basis_points), E_INVALID_ROYALTY);
        let mut total_royalty = 0u16;
        let mut royalty = vector::empty<RoyaltyInfo>();
        let mut i = 0;
        while (i < vector::length(&royalty_recipients)) {
            let basis_points = *vector::borrow(&royalty_basis_points, i);
            total_royalty = total_royalty + basis_points;
            vector::push_back(&mut royalty, lib::new_royalty_info(
                *vector::borrow(&royalty_recipients, i),
                basis_points,
            ));
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

        event::emit(DataNFTMintedEvent {
            nft_id: object::uid_to_inner(&nft.id),
            creator,
            data_hash,
        });

        event::emit(StorageTicketEvent {
            nft_id: object::uid_to_inner(&nft.id),
            storage_url: nft.storage_url,
            version: nft.version,
        });

        // Create and share the transfer policy
        let (policy, cap) = transfer_policy::new<DataNFT>(publisher, ctx);
        transfer::public_transfer(cap, tx_context::sender(ctx)); // Transfer cap to creator

        (nft, policy)
    }

    /// Updates metadata of an existing DataNFT.
    public fun update_data_nft(
        nft: &mut DataNFT,
        storage_url_opt: Option<vector<u8>>,
        license_hash_opt: Option<vector<u8>>,
        ctx: &mut TxContext
    ) {
        assert!(nft.creator == tx_context::sender(ctx), E_NOT_AUTHORIZED);
        if (option::is_some(&storage_url_opt)) {
            nft.storage_url = url::new_unsafe_from_bytes(option::destroy_some(storage_url_opt));
        };
        if (option::is_some(&license_hash_opt)) {
            nft.license_hash = option::destroy_some(license_hash_opt);
        };
        nft.version = nft.version + 1;

        event::emit(DataNFTUpdatedEvent {
            nft_id: object::uid_to_inner(&nft.id),
            version: nft.version,
        });

        event::emit(StorageTicketEvent {
            nft_id: object::uid_to_inner(&nft.id),
            storage_url: nft.storage_url,
            version: nft.version,
        });
    }

    /// Processes royalty payment and confirms the transfer request.
    public fun pay_royalty_and_confirm(
        _policy: &TransferPolicy<DataNFT>,
        mut request: TransferRequest<DataNFT>,
        mut payment: Coin<SUI>,
        ctx: &mut TxContext
    ): TransferRequest<DataNFT> {
        let price = transfer_policy::paid(&request);
        let royalty_amount = (price * (GLOBAL_ROYALTY_BPS as u64)) / (BASIS_POINTS_TOTAL as u64);
        
        assert!(coin::value(&payment) >= royalty_amount, E_INSUFFICIENT_PAYMENT);
        
        if (royalty_amount > 0) {
            let royalty_coin = coin::split(&mut payment, royalty_amount, ctx);
            // Split royalty among recipients - simplified implementation
            // In production, this would access the NFT's royalty info
            transfer::public_transfer(royalty_coin, tx_context::sender(ctx)); // Placeholder
        };
        
        // Return remaining payment to buyer
        transfer::public_transfer(payment, tx_context::sender(ctx));
        
        // Add receipt to confirm rule compliance
        transfer_policy::add_receipt<DataNFT, RoyaltyRule>(RoyaltyRule {}, &mut request);
        request
    }

    // === Rule Struct ===
    public struct RoyaltyRule has drop {}

    // === Package-Private Functions ===

    /// Toggles active status of a DataNFT. Only callable by the DAO module.
    public(package) fun update_active_status(
        _: &GovCap,
        nft: &mut DataNFT,
        active: bool
    ) {
        nft.active = active;
    }

    // === Getters ===

    public fun id(nft: &DataNFT): ID { object::uid_to_inner(&nft.id) }
    public fun creator(nft: &DataNFT): address { nft.creator }
    public fun is_active(nft: &DataNFT): bool { nft.active }
    public fun royalty(nft: &DataNFT): &vector<RoyaltyInfo> { &nft.royalty }
    public fun royalty_mut(nft: &mut DataNFT): &mut vector<RoyaltyInfo> { &mut nft.royalty }
}
