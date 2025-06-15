#[test_only]
module byte_bazaar::byte_bazaar_tests {
    use byte_bazaar::nft::{Self, DataNFT};
    use byte_bazaar::market;
    use byte_bazaar::task::{Self, Task};
    use byte_bazaar::dao::{Self, Proposal, FreezeNFTAction};
    use byte_bazaar::entry::{Self, UploaderCap, LabelerCap, ValidatorCap, GovCap};
    use sui::test_scenario::{Self, Scenario};
    use sui::coin;
    use sui::sui::SUI;
    use sui::clock;
    use sui::kiosk;
    use sui::object;
    use sui::transfer;
    use sui::package;
    use std::option;

    // Test addresses
    const ADMIN: address = @0x1;
    const CREATOR: address = @0x2;
    const BUYER: address = @0x3;
    const LABELER: address = @0x4;
    const VALIDATOR1: address = @0x5;
    const VALIDATOR2: address = @0x6;
    const PROPOSER: address = @0x7;

    // Test constants
    const NFT_PRICE: u64 = 100000000; // 0.1 SUI
    const TASK_REWARD: u64 = 50000000; // 0.05 SUI
    const TASK_DEADLINE: u64 = 86400000; // 24 hours in ms

    #[test]
    fun test_mint_and_list_and_buy_nft() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize the module
        {
            entry::init_for_testing(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, CREATOR);
        
        // Take capabilities
        let uploader_cap = test_scenario::take_from_sender<UploaderCap>(&scenario);
        let publisher = test_scenario::take_shared<package::Publisher>(&scenario);
        
        // Mint DataNFT
        let data_hash = b"test_data_hash_32_bytes_exactly!";
        let storage_url = b"walrus://test_cid";
        let license_hash = b"license_hash";
        let royalty_recipients = vector[CREATOR];
        let royalty_basis_points = vector[10000u16]; // 100% to creator
        
        let (nft, policy) = nft::mint_data_nft(
            &uploader_cap,
            &publisher,
            CREATOR,
            data_hash,
            storage_url,
            license_hash,
            royalty_recipients,
            royalty_basis_points,
            test_scenario::ctx(&mut scenario)
        );
        
        // Verify NFT properties
        assert!(nft::creator(&nft) == CREATOR, 0);
        assert!(nft::is_active(&nft) == true, 1);
        
        // Get NFT ID before moving it
        let nft_id = nft::id(&nft);
        
        // Create kiosk for listing
        let (mut kiosk, kiosk_cap) = kiosk::new(test_scenario::ctx(&mut scenario));
        
        // List NFT
        market::list_nft(
            &mut kiosk,
            &kiosk_cap,
            nft,
            NFT_PRICE,
            test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::next_tx(&mut scenario, BUYER);
        
        // Create payment coin
        let payment = coin::mint_for_testing<SUI>(NFT_PRICE, test_scenario::ctx(&mut scenario));
        
        // Buy NFT
        let purchased_nft = market::buy_nft(
            &mut kiosk,
            &kiosk_cap,
            nft_id,
            payment,
            test_scenario::ctx(&mut scenario)
        );
        
        // Verify purchased NFT
        assert!(nft::creator(&purchased_nft) == CREATOR, 2);
        assert!(nft::is_active(&purchased_nft) == true, 3);
        
        // Clean up
        transfer::public_transfer(purchased_nft, BUYER);
        transfer::public_transfer(kiosk_cap, CREATOR);
        transfer::public_share_object(kiosk);
        transfer::public_share_object(policy);
        test_scenario::return_to_sender(&scenario, uploader_cap);
        test_scenario::return_shared(publisher);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_task_happy_path() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize
        {
            entry::init_for_testing(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, CREATOR);
        
        // Take capabilities
        let uploader_cap = test_scenario::take_from_sender<UploaderCap>(&scenario);
        
        // Create clock
        let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 1000000); // Set initial time
        
        // Create a dummy dataset ID
        let dataset_id = object::id_from_address(@0x1);
        
        // Publish task
        let reward = coin::mint_for_testing<SUI>(TASK_REWARD, test_scenario::ctx(&mut scenario));
        let deadline = clock::timestamp_ms(&clock) + TASK_DEADLINE;
        
        let mut task = task::publish_task(
            &uploader_cap,
            dataset_id,
            reward,
            deadline,
            option::none(),
            &clock,
            test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::next_tx(&mut scenario, LABELER);
        
        // Take labeler capability
        let labeler_cap = test_scenario::take_from_sender<LabelerCap>(&scenario);
        
        // Claim task
        let escrow = coin::mint_for_testing<SUI>(TASK_REWARD / 10, test_scenario::ctx(&mut scenario));
        task::claim_task(
            &labeler_cap,
            &mut task,
            escrow,
            &clock,
            test_scenario::ctx(&mut scenario)
        );
        
        // Submit result
        let result_hash = b"task_result_hash";
        task::submit_task_result(
            &mut task,
            result_hash,
            test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::next_tx(&mut scenario, VALIDATOR1);
        
        // Take validator capability
        let validator_cap1 = test_scenario::take_from_sender<ValidatorCap>(&scenario);
        
        // First validator approves
        task::submit_review(
            &validator_cap1,
            &mut task,
            true,
            test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::next_tx(&mut scenario, VALIDATOR2);
        
        // Take validator capability
        let validator_cap2 = test_scenario::take_from_sender<ValidatorCap>(&scenario);
        
        // Second validator approves
        task::submit_review(
            &validator_cap2,
            &mut task,
            true,
            test_scenario::ctx(&mut scenario)
        );
        
        // Finalize task
        task::finalize_task(
            &mut task,
            test_scenario::ctx(&mut scenario)
        );
        
        // Clean up
        transfer::public_transfer(task, CREATOR);
        test_scenario::return_to_sender(&scenario, uploader_cap);
        test_scenario::return_to_sender(&scenario, labeler_cap);
        test_scenario::return_to_sender(&scenario, validator_cap1);
        test_scenario::return_to_sender(&scenario, validator_cap2);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_dao_proposal_and_nft_freeze() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize
        {
            entry::init_for_testing(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, ADMIN);
        
        // Take capabilities
        let gov_cap = test_scenario::take_from_sender<GovCap>(&scenario);
        let uploader_cap = test_scenario::take_from_sender<UploaderCap>(&scenario);
        let publisher = test_scenario::take_shared<package::Publisher>(&scenario);
        
        // Create clock
        let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 1000000);
        
        // Mint NFT first
        let data_hash = b"test_data_hash_32_bytes_exactly!";
        let storage_url = b"walrus://test_cid";
        let license_hash = b"license_hash";
        let royalty_recipients = vector[ADMIN];
        let royalty_basis_points = vector[10000u16];
        
        let (mut nft, policy) = nft::mint_data_nft(
            &uploader_cap,
            &publisher,
            ADMIN,
            data_hash,
            storage_url,
            license_hash,
            royalty_recipients,
            royalty_basis_points,
            test_scenario::ctx(&mut scenario)
        );
        
        let nft_id = nft::id(&nft);
        
        test_scenario::next_tx(&mut scenario, PROPOSER);
        
        // Create freeze proposal
        let action = dao::new_freeze_nft_action(nft_id, false); // unfreeze action
        let duration = 86400000; // 24 hours
        
        let mut proposal = dao::create_proposal(
            &gov_cap,
            action,
            duration,
            &clock,
            test_scenario::ctx(&mut scenario)
        );
        
        // Vote on proposal
        dao::vote_on_proposal(
            &mut proposal,
            true,
            100,
            &clock,
            test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::next_tx(&mut scenario, VALIDATOR1);
        
        // Another vote
        dao::vote_on_proposal(
            &mut proposal,
            true,
            50,
            &clock,
            test_scenario::ctx(&mut scenario)
        );
        
        // Advance time past deadline
        let current_time = clock::timestamp_ms(&clock);
        clock::set_for_testing(&mut clock, current_time + duration + 1);
        
        // Tally proposal
        dao::tally_proposal(&mut proposal, &clock);
        
        test_scenario::next_tx(&mut scenario, ADMIN);
        
        // Execute proposal
        dao::execute_freeze_nft_proposal(
            &gov_cap,
            &mut proposal,
            &mut nft
        );
        
        // Verify NFT status
        assert!(nft::is_active(&nft) == false, 0);
        
        // Clean up
        transfer::public_transfer(nft, ADMIN);
        transfer::public_transfer(proposal, PROPOSER);
        transfer::public_share_object(policy);
        test_scenario::return_to_sender(&scenario, gov_cap);
        test_scenario::return_to_sender(&scenario, uploader_cap);
        test_scenario::return_shared(publisher);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 2)]
    fun test_invalid_royalty_total() {
        let mut scenario = test_scenario::begin(CREATOR);
        
        // Initialize
        {
            entry::init_for_testing(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, CREATOR);
        
        // Take capabilities
        let uploader_cap = test_scenario::take_from_sender<UploaderCap>(&scenario);
        let publisher = test_scenario::take_shared<package::Publisher>(&scenario);
        
        // Try to mint NFT with invalid royalty (not totaling 10000)
        let data_hash = b"test_data_hash_32_bytes_exactly!";
        let storage_url = b"walrus://test_cid";
        let license_hash = b"license_hash";
        let royalty_recipients = vector[CREATOR];
        let royalty_basis_points = vector[5000u16]; // Only 50%, should fail
        
        let (nft, policy) = nft::mint_data_nft(
            &uploader_cap,
            &publisher,
            CREATOR,
            data_hash,
            storage_url,
            license_hash,
            royalty_recipients,
            royalty_basis_points,
            test_scenario::ctx(&mut scenario)
        );
        
        transfer::public_transfer(nft, CREATOR);
        transfer::public_share_object(policy);
        test_scenario::return_to_sender(&scenario, uploader_cap);
        test_scenario::return_shared(publisher);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 13)]
    fun test_frozen_nft_marketplace_rejection() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize
        {
            entry::init_for_testing(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, ADMIN);
        
        // Take capabilities
        let gov_cap = test_scenario::take_from_sender<GovCap>(&scenario);
        let uploader_cap = test_scenario::take_from_sender<UploaderCap>(&scenario);
        let publisher = test_scenario::take_shared<package::Publisher>(&scenario);
        
        test_scenario::next_tx(&mut scenario, CREATOR);
        
        // Mint NFT
        let data_hash = b"test_data_hash_32_bytes_exactly!";
        let storage_url = b"walrus://test_cid";
        let license_hash = b"license_hash";
        let royalty_recipients = vector[CREATOR];
        let royalty_basis_points = vector[10000u16];
        
        let (mut nft, policy) = nft::mint_data_nft(
            &uploader_cap,
            &publisher,
            CREATOR,
            data_hash,
            storage_url,
            license_hash,
            royalty_recipients,
            royalty_basis_points,
            test_scenario::ctx(&mut scenario)
        );
        
        // Freeze NFT
        nft::update_active_status(&gov_cap, &mut nft, false);
        
        // Try to list frozen NFT (should fail)
        let (mut kiosk, kiosk_cap) = kiosk::new(test_scenario::ctx(&mut scenario));
        
        market::list_nft(
            &mut kiosk,
            &kiosk_cap,
            nft,
            NFT_PRICE,
            test_scenario::ctx(&mut scenario)
        );
        
        // Clean up (won't reach here due to expected failure)
        transfer::public_transfer(kiosk_cap, CREATOR);
        transfer::public_share_object(kiosk);
        transfer::public_share_object(policy);
        test_scenario::return_to_sender(&scenario, gov_cap);
        test_scenario::return_to_sender(&scenario, uploader_cap);
        test_scenario::return_shared(publisher);
        test_scenario::end(scenario);
    }
}
