/// Module for handling revenue distribution.
/// This logic is called by both direct market sales and transfer policy royalties.
module byte_bazaar::revenue {
    // === Imports ===
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context::TxContext;
    use std::vector;

    use byte_bazaar::lib::{Self, RoyaltyInfo};

    // === Constants ===
    const BASIS_POINTS_TOTAL: u16 = 10000; // 100%

    // === Package-Private Functions ===

    /// Splits royalty payments from a given Coin.
    /// Returns the remaining Coin, which represents the seller's proceeds.
    public(package) fun split_revenue(
        mut payment: Coin<SUI>,
        royalty: &vector<RoyaltyInfo>,
        ctx: &mut TxContext
    ): Coin<SUI> {
        let total_amount = coin::value(&payment);
        let mut i = 0;
        while (i < vector::length(royalty)) {
            let info = vector::borrow(royalty, i);
            // Royalty is calculated on the original price, not the remaining amount.
            let amount = (total_amount * (lib::basis_points(info) as u64)) / (BASIS_POINTS_TOTAL as u64);
            if (amount > 0 && coin::value(&payment) >= amount) {
                let part = coin::split(&mut payment, amount, ctx);
                transfer::public_transfer(part, lib::recipient(info));
            };
            i = i + 1;
        };
        
        // Return the remainder to the caller (market or transfer policy)
        // which is responsible for sending it to the seller.
        payment
    }
}
