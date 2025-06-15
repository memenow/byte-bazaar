/// DAO and governance module.
/// Handles proposals, voting, and execution of administrative actions.
module byte_bazaar::dao {
    // === Imports ===
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::clock::{Self, Clock};
    use sui::event;
    use sui::vec_map::{Self, VecMap};
    use sui::package::{Self, UpgradeCap, UpgradeTicket, UpgradeReceipt};
    use sui::transfer;

    use byte_bazaar::entry::GovCap;
    use byte_bazaar::nft::{Self, DataNFT};

    // === Constants ===
    const E_PROPOSAL_NOT_ACTIVE: u64 = 11;
    const E_PROPOSAL_EXPIRED: u64 = 12;
    const E_INVALID_VALIDATOR: u64 = 10;
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_PROPOSAL_ALREADY_EXECUTED: u64 = 19;

    const PROPOSAL_STATUS_ACTIVE: u8 = 0;
    const PROPOSAL_STATUS_PASSED: u8 = 1;
    const PROPOSAL_STATUS_REJECTED: u8 = 2;
    const PROPOSAL_STATUS_EXECUTED: u8 = 3;

    // === Events ===
    public struct ProposalCreatedEvent has copy, drop { proposal_id: ID, proposer: address }
    public struct ProposalExecutedEvent has copy, drop { proposal_id: ID }

    // === Structs ===

    /// Proposal defines a DAO governance action.
    public struct Proposal<T: store> has key, store {
        id: UID,
        proposer: address,
        action: T,
        aye_votes: u64,
        nay_votes: u64,
        status: u8,
        deadline: u64,
        voters: VecMap<address, bool>,
    }

    // Action structs
    public struct FreezeNFTAction has store { nft_id: ID, freeze: bool }
    public struct UpgradeAction has store { digest: vector<u8> }

    // === Action Constructors ===
    public fun new_freeze_nft_action(nft_id: ID, freeze: bool): FreezeNFTAction {
        FreezeNFTAction { nft_id, freeze }
    }

    public fun new_upgrade_action(digest: vector<u8>): UpgradeAction {
        UpgradeAction { digest }
    }

    // === Public Functions ===

    /// Creates a new governance proposal.
    public fun create_proposal<T: store>(
        _: &GovCap,
        action: T,
        duration: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): Proposal<T> {
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
        event::emit(ProposalCreatedEvent {
            proposal_id: object::uid_to_inner(&proposal.id),
            proposer: tx_context::sender(ctx),
        });
        proposal
    }

    /// Casts a vote on a proposal.
    public fun vote_on_proposal<T: store>(
        proposal: &mut Proposal<T>,
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

    /// Tally a proposal after its deadline has passed.
    public fun tally_proposal<T: store>(proposal: &mut Proposal<T>, clock: &Clock) {
        assert!(proposal.status == PROPOSAL_STATUS_ACTIVE, E_PROPOSAL_NOT_ACTIVE);
        assert!(clock::timestamp_ms(clock) >= proposal.deadline, E_PROPOSAL_EXPIRED);
        if (proposal.aye_votes > proposal.nay_votes) {
            proposal.status = PROPOSAL_STATUS_PASSED;
        } else {
            proposal.status = PROPOSAL_STATUS_REJECTED;
        }
    }

    // --- Proposal Execution Functions ---

    public fun execute_freeze_nft_proposal(
        gov_cap: &GovCap,
        proposal: &mut Proposal<FreezeNFTAction>,
        nft: &mut DataNFT
    ) {
        assert!(proposal.status == PROPOSAL_STATUS_PASSED, E_PROPOSAL_NOT_ACTIVE);
        assert!(nft::id(nft) == proposal.action.nft_id, E_NOT_AUTHORIZED);
        nft::update_active_status(gov_cap, nft, proposal.action.freeze);
        proposal.status = PROPOSAL_STATUS_EXECUTED;
        event::emit(ProposalExecutedEvent { proposal_id: object::uid_to_inner(&proposal.id) });
    }

    public fun execute_upgrade_proposal(
        _: &GovCap,
        proposal: &mut Proposal<UpgradeAction>,
        cap: &mut UpgradeCap,
        receipt: UpgradeReceipt
    ) {
        assert!(proposal.status == PROPOSAL_STATUS_PASSED, E_PROPOSAL_NOT_ACTIVE);
        package::commit_upgrade(cap, receipt);
        proposal.status = PROPOSAL_STATUS_EXECUTED;
        event::emit(ProposalExecutedEvent { proposal_id: object::uid_to_inner(&proposal.id) });
    }

    /// Authorizes a contract upgrade and returns the ticket.
    public fun authorize_upgrade(
        _: &GovCap,
        cap: &mut UpgradeCap,
        policy: u8,
        digest: vector<u8>
    ): UpgradeTicket {
        package::authorize_upgrade(cap, policy, digest)
    }

    /// Publishes an upgrade package through DAO governance.
    public fun publish_upgrade_package(
        _: &GovCap,
        cap: &mut UpgradeCap,
        _modules: vector<vector<u8>>,
        _deps: vector<ID>,
        _ctx: &mut TxContext
    ): UpgradeTicket {
        // This is a simplified implementation
        // In practice, this would involve more complex upgrade logic
        package::authorize_upgrade(cap, 0, b"upgrade_digest")
    }
}
