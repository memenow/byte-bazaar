/// Main entry point for the Byte Bazaar package.
/// Initializes all modules and distributes initial capabilities.
module byte_bazaar::entry {
    use sui::object::{Self, UID};
    use sui::package;
    use sui::transfer;
    use sui::tx_context::TxContext;

    // === Capability Structs ===
    public struct GovCap has key, store { id: UID }
    public struct UploaderCap has key, store { id: UID }
    public struct LabelerCap has key, store { id: UID }
    public struct ValidatorCap has key, store { id: UID }

    // === One-Time Witness for Init ===
    public struct ENTRY has drop {}

    // === Init Function ===
    fun init(otw: ENTRY, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        
        // Create and transfer all core capabilities to the deployer.
        transfer::public_transfer(GovCap { id: object::new(ctx) }, sender);
        transfer::public_transfer(UploaderCap { id: object::new(ctx) }, sender);
        transfer::public_transfer(LabelerCap { id: object::new(ctx) }, sender);
        transfer::public_transfer(ValidatorCap { id: object::new(ctx) }, sender);

        // Create and share the publisher object needed for transfer policies.
        let publisher = package::claim(otw, ctx);
        transfer::public_share_object(publisher);
    }

    // === Test Functions ===
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        let otw = ENTRY {};
        init(otw, ctx);
    }
}
