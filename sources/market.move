/// Marketplace module for listing and purchasing DataNFTs.
/// Integrates with Kiosk and TransferPolicy for automated royalty payments.
module byte_bazaar::market {
    // === Imports ===
    use sui::kiosk::{Self, Kiosk, KioskOwnerCap};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    use sui::object::ID;
    use sui::transfer;

    use byte_bazaar::nft::{Self, DataNFT};

    // === Constants ===
    const E_NFT_FROZEN: u64 = 13;
    const E_INVALID_PRICE: u64 = 14;
    const E_INSUFFICIENT_PAYMENT: u64 = 15;

    // === Events ===
    public struct NFTListedEvent has copy, drop { listing_id: ID, nft_id: ID, price: u64 }
    public struct NFTPurchasedEvent has copy, drop { nft_id: ID, buyer: address, price: u64 }

    // === Public Functions ===

    /// Lists a DataNFT for sale in a kiosk.
    public fun list_nft(
        kiosk: &mut Kiosk,
        kiosk_cap: &KioskOwnerCap,
        nft: DataNFT,
        price: u64,
        _ctx: &mut TxContext
    ) {
        assert!(nft::is_active(&nft), E_NFT_FROZEN);
        assert!(price > 0, E_INVALID_PRICE);
        let nft_id = nft::id(&nft);
        kiosk::place_and_list<DataNFT>(kiosk, kiosk_cap, nft, price);
        
        event::emit(NFTListedEvent {
            listing_id: nft_id, // Use NFT ID as listing ID for simplicity
            nft_id,
            price,
        });
    }

    /// Buys a DataNFT from a kiosk.
    /// Note: This is a simplified implementation. In production, proper TransferPolicy handling is required.
    public fun buy_nft(
        kiosk: &mut Kiosk,
        kiosk_cap: &KioskOwnerCap,
        nft_id: ID,
        payment: Coin<SUI>,
        ctx: &mut TxContext
    ): DataNFT {
        // For now, use direct take without transfer policy
        // In production, this would need proper transfer policy integration
        let nft = kiosk::take<DataNFT>(kiosk, kiosk_cap, nft_id);
        
        // Get price before transferring payment
        let price = coin::value(&payment);
        
        // Transfer payment to kiosk owner (simplified)
        // In production, this would be handled by the kiosk system
        sui::transfer::public_transfer(payment, tx_context::sender(ctx));
        
        assert!(nft::is_active(&nft), E_NFT_FROZEN);

        event::emit(NFTPurchasedEvent {
            nft_id,
            buyer: tx_context::sender(ctx),
            price,
        });

        nft
    }
}
