/// Shared library for the Byte Bazaar project.
/// Contains common, cross-module struct definitions.
module byte_bazaar::lib {
    use sui::object::UID;

    // === Core Structs ===

    /// RoyaltyInfo defines revenue split for a recipient.
    public struct RoyaltyInfo has store, copy, drop {
        recipient: address,
        basis_points: u16,
    }

    // === Getters for RoyaltyInfo ===
    public fun recipient(info: &RoyaltyInfo): address { info.recipient }
    public fun basis_points(info: &RoyaltyInfo): u16 { info.basis_points }

    // === Constructor for RoyaltyInfo ===
    public fun new_royalty_info(recipient: address, basis_points: u16): RoyaltyInfo {
        RoyaltyInfo {
            recipient,
            basis_points,
        }
    }

    // NOTE: The native sui::package::UpgradeCap is used for upgrades.
    // This struct is kept here as a reference but the real one will be used.
    // public struct UpgradeCap has key, store { id: UID }

}
