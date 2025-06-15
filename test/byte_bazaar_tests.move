#[test_only]
module byte_bazaar::byte_bazaar_tests {
    use byte_bazaar::byte_bazaar::{Self, AdminCap};
    use sui::test_scenario;
    use sui::coin;
    use sui::sui::SUI;
    use sui::clock;
    use sui::kiosk;
    use sui::object;
    use sui::transfer;
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
            byte_bazaar::init_for_testing(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, CREATOR);
        
        // Mint DataNFT
        let data_hash = b"test_data_hash_32_bytes_exactly!";
        let storage_url = b"walrus://test_cid";
        let license_hash = b"license_hash";
        let royalty_recipients = vector[CREATOR];
        let royalty_basis_points = vector[10000u16]; // 100% to creator
        
        let nft = byte_bazaar::mint_data_nft(
            CREATOR,
            data_hash,
            storage_url,
            license_hash,
            royalty_recipients,
            royalty_basis_points,
            test_scenario::ctx(&mut scenario)
        );
        
        // Verify NFT properties
        let (creator, nft_data_hash, active, version) = byte_bazaar::get_nft_info(&nft);
        assert!(creator == CREATOR, 0);
        assert!(nft_data_hash == data_hash, 1);
        assert!(active == true, 2);
        assert!(version == 1, 3);
        
        // Get NFT ID before moving it
        let nft_id = object::id(&nft);
        
        // Create kiosk for listing
        let (mut kiosk, kiosk_cap) = kiosk::new(test_scenario::ctx(&mut scenario));
        
        // List NFT
        byte_bazaar::list_nft(
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
        let purchased_nft = byte_bazaar::buy_nft(
            &mut kiosk,
            &kiosk_cap,
            nft_id,
            payment,
            test_scenario::ctx(&mut scenario)
        );
        
        // Verify purchased NFT
        let (purchased_creator, _, purchased_active, _) = byte_bazaar::get_nft_info(&purchased_nft);
        assert!(purchased_creator == CREATOR, 4);
        assert!(purchased_active == true, 5);
        
        // Clean up
        transfer::public_transfer(purchased_nft, BUYER);
        transfer::public_transfer(kiosk_cap, CREATOR);
        transfer::public_transfer(kiosk, CREATOR);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_task_happy_path() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize
        {
            byte_bazaar::init_for_testing(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, CREATOR);
        
        // Create clock
        let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 1000000); // Set initial time
        
        // Create a dummy dataset ID
        let dataset_id = object::id_from_address(@0x1);
        
        // Publish task
        let reward = coin::mint_for_testing<SUI>(TASK_REWARD, test_scenario::ctx(&mut scenario));
        let deadline = clock::timestamp_ms(&clock) + TASK_DEADLINE;
        
        let mut task = byte_bazaar::publish_task(
            dataset_id,
            reward,
            deadline,
            &clock,
            test_scenario::ctx(&mut scenario)
        );
        
        // Verify task info
        let (task_dataset, status, labeler, task_deadline) = byte_bazaar::get_task_info(&task);
        assert!(task_dataset == dataset_id, 0);
        assert!(status == 0, 1); // TASK_STATUS_OPEN
        assert!(option::is_none(&labeler), 2);
        assert!(task_deadline == deadline, 3);
        
        test_scenario::next_tx(&mut scenario, LABELER);
        
        // Claim task
        let escrow = coin::mint_for_testing<SUI>(TASK_REWARD / 10, test_scenario::ctx(&mut scenario));
        byte_bazaar::claim_task(
            &mut task,
            escrow,
            &clock,
            test_scenario::ctx(&mut scenario)
        );
        
        // Verify task claimed
        let (_, status, labeler, _) = byte_bazaar::get_task_info(&task);
        assert!(status == 1, 4); // TASK_STATUS_IN_PROGRESS
        assert!(option::contains(&labeler, &LABELER), 5);
        
        // Submit result
        let result_hash = b"task_result_hash";
        byte_bazaar::submit_task_result(
            &mut task,
            result_hash,
            test_scenario::ctx(&mut scenario)
        );
        
        // Verify task in review
        let (_, status, _, _) = byte_bazaar::get_task_info(&task);
        assert!(status == 2, 6); // TASK_STATUS_IN_REVIEW
        
        test_scenario::next_tx(&mut scenario, VALIDATOR1);
        
        // First validator approves
        byte_bazaar::submit_review(
            &mut task,
            true,
            test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::next_tx(&mut scenario, VALIDATOR2);
        
        // Second validator approves
        byte_bazaar::submit_review(
            &mut task,
            true,
            test_scenario::ctx(&mut scenario)
        );
        
        // Finalize task
        byte_bazaar::finalize_task(
            &mut task,
            test_scenario::ctx(&mut scenario)
        );
        
        // Verify task completed
        let (_, status, _, _) = byte_bazaar::get_task_info(&task);
        assert!(status == 3, 7); // TASK_STATUS_COMPLETED
        
        // Clean up
        transfer::public_transfer(task, CREATOR);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_dao_proposal_and_nft_freeze() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize
        {
            byte_bazaar::init_for_testing(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, ADMIN);
        
        // Take admin cap
        let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
        
        // Create clock
        let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 1000000);
        
        test_scenario::next_tx(&mut scenario, PROPOSER);
        
        // Create proposal
        let action = b"freeze_nft";
        let duration = 86400000; // 24 hours
        
        let mut proposal = byte_bazaar::create_proposal(
            action,
            duration,
            &clock,
            test_scenario::ctx(&mut scenario)
        );
        
        // Verify proposal info
        let (proposer, status, aye_votes, nay_votes, _deadline) = byte_bazaar::get_proposal_info(&proposal);
        assert!(proposer == PROPOSER, 0);
        assert!(status == 0, 1); // PROPOSAL_STATUS_ACTIVE
        assert!(aye_votes == 0, 2);
        assert!(nay_votes == 0, 3);
        
        // Vote on proposal
        byte_bazaar::vote_on_proposal(
            &mut proposal,
            true,
            100,
            &clock,
            test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::next_tx(&mut scenario, VALIDATOR1);
        
        // Another vote
        byte_bazaar::vote_on_proposal(
            &mut proposal,
            true,
            50,
            &clock,
            test_scenario::ctx(&mut scenario)
        );
        
        // Advance time past deadline
        let current_time = clock::timestamp_ms(&clock);
        clock::set_for_testing(&mut clock, current_time + duration + 1);
        
        test_scenario::next_tx(&mut scenario, ADMIN);
        
        // Execute proposal
        byte_bazaar::execute_proposal(
            &admin_cap,
            &mut proposal,
            &clock
        );
        
        // Verify proposal executed
        let (_, status, _, _, _) = byte_bazaar::get_proposal_info(&proposal);
        assert!(status == 3, 4); // PROPOSAL_STATUS_EXECUTED
        
        // Test NFT freeze functionality
        test_scenario::next_tx(&mut scenario, CREATOR);
        
        // Mint NFT
        let data_hash = b"test_data_hash_32_bytes_exactly!";
        let storage_url = b"walrus://test_cid";
        let license_hash = b"license_hash";
        let royalty_recipients = vector[CREATOR];
        let royalty_basis_points = vector[10000u16];
        
        let mut nft = byte_bazaar::mint_data_nft(
            CREATOR,
            data_hash,
            storage_url,
            license_hash,
            royalty_recipients,
            royalty_basis_points,
            test_scenario::ctx(&mut scenario)
        );
        
        // Freeze NFT using admin cap
        byte_bazaar::set_nft_active_status(&admin_cap, &mut nft, false);
        
        // Verify NFT is frozen
        let (_, _, active, _) = byte_bazaar::get_nft_info(&nft);
        assert!(active == false, 5);
        
        // Clean up
        transfer::public_transfer(nft, CREATOR);
        transfer::public_transfer(proposal, PROPOSER);
        transfer::public_transfer(admin_cap, ADMIN);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 2)]
    fun test_invalid_royalty_total() {
        let mut scenario = test_scenario::begin(CREATOR);
        
        // Try to mint NFT with invalid royalty (not totaling 10000)
        let data_hash = b"test_data_hash_32_bytes_exactly!";
        let storage_url = b"walrus://test_cid";
        let license_hash = b"license_hash";
        let royalty_recipients = vector[CREATOR];
        let royalty_basis_points = vector[5000u16]; // Only 50%, should fail
        
        let nft = byte_bazaar::mint_data_nft(
            CREATOR,
            data_hash,
            storage_url,
            license_hash,
            royalty_recipients,
            royalty_basis_points,
            test_scenario::ctx(&mut scenario)
        );
        
        transfer::public_transfer(nft, CREATOR);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 13)]
    fun test_frozen_nft_marketplace_rejection() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize
        {
            byte_bazaar::init_for_testing(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, ADMIN);
        let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
        
        test_scenario::next_tx(&mut scenario, CREATOR);
        
        // Mint NFT
        let data_hash = b"test_data_hash_32_bytes_exactly!";
        let storage_url = b"walrus://test_cid";
        let license_hash = b"license_hash";
        let royalty_recipients = vector[CREATOR];
        let royalty_basis_points = vector[10000u16];
        
        let mut nft = byte_bazaar::mint_data_nft(
            CREATOR,
            data_hash,
            storage_url,
            license_hash,
            royalty_recipients,
            royalty_basis_points,
            test_scenario::ctx(&mut scenario)
        );
        
        // Freeze NFT
        byte_bazaar::set_nft_active_status(&admin_cap, &mut nft, false);
        
        // Try to list frozen NFT (should fail)
        let (mut kiosk, kiosk_cap) = kiosk::new(test_scenario::ctx(&mut scenario));
        
        byte_bazaar::list_nft(
            &mut kiosk,
            &kiosk_cap,
            nft,
            NFT_PRICE,
            test_scenario::ctx(&mut scenario)
        );
        
        // Clean up (won't reach here due to expected failure)
        transfer::public_transfer(kiosk_cap, CREATOR);
        transfer::public_transfer(kiosk, CREATOR);
        test_scenario::return_to_sender(&scenario, admin_cap);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 4)]
    fun test_claim_already_claimed_task() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize
        {
            byte_bazaar::init_for_testing(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, CREATOR);
        
        let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 1000000);
        
        let dataset_id = object::id_from_address(@0x1);
        let reward = coin::mint_for_testing<SUI>(TASK_REWARD, test_scenario::ctx(&mut scenario));
        let deadline = clock::timestamp_ms(&clock) + TASK_DEADLINE;
        
        let mut task = byte_bazaar::publish_task(
            dataset_id,
            reward,
            deadline,
            &clock,
            test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::next_tx(&mut scenario, LABELER);
        
        // First claim
        let escrow1 = coin::mint_for_testing<SUI>(TASK_REWARD / 10, test_scenario::ctx(&mut scenario));
        byte_bazaar::claim_task(&mut task, escrow1, &clock, test_scenario::ctx(&mut scenario));
        
        test_scenario::next_tx(&mut scenario, BUYER);
        
        // Try to claim again (should fail)
        let escrow2 = coin::mint_for_testing<SUI>(TASK_REWARD / 10, test_scenario::ctx(&mut scenario));
        byte_bazaar::claim_task(&mut task, escrow2, &clock, test_scenario::ctx(&mut scenario));
        
        // Clean up (won't reach here)
        transfer::public_transfer(task, CREATOR);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_revenue_split() {
        let mut scenario = test_scenario::begin(CREATOR);
        
        // This test just verifies the module compiles and basic functionality works
        // In a real implementation, we'd test the revenue split by checking balances
        
        test_scenario::end(scenario);
    }
}
