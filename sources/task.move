/// Task management module for data labeling and validation.
/// Includes mechanisms for golden sample checks and multi-validator consensus.
module byte_bazaar::task {
    // === Imports ===
    use sui::object::{UID, ID};
    use sui::balance::{Self, Balance};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock::{Self, Clock};
    use sui::event;
    use std::vector;
    use std::option::{Self, Option};

    use byte_bazaar::entry::{UploaderCap, LabelerCap, ValidatorCap};

    // === Constants ===
    const E_DEADLINE_PASSED: u64 = 9;
    const E_INSUFFICIENT_ESCROW: u64 = 8;
    const E_TASK_NOT_OPEN: u64 = 4;
    const E_ALREADY_CLAIMED: u64 = 7;
    const E_TASK_NOT_IN_PROGRESS: u64 = 5;
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_INCORRECT_HASH: u64 = 16;
    const E_TASK_NOT_IN_REVIEW: u64 = 6;
    const E_INVALID_VALIDATOR: u64 = 10;
    const E_INSUFFICIENT_VOTES: u64 = 17;

    const TASK_STATUS_OPEN: u8 = 0;
    const TASK_STATUS_IN_PROGRESS: u8 = 1;
    const TASK_STATUS_IN_REVIEW: u8 = 2;
    const TASK_STATUS_COMPLETED: u8 = 3;
    const TASK_STATUS_DISPUTED: u8 = 4;

    const MIN_ESCROW_PERCENTAGE: u16 = 1000; // 10%
    const BASIS_POINTS_TOTAL: u16 = 10000; // 100%

    // === Events ===
    public struct TaskPublishedEvent has copy, drop { task_id: ID, dataset: ID, reward_amount: u64 }
    public struct TaskClaimedEvent has copy, drop { task_id: ID, labeler: address }
    public struct TaskCompletedEvent has copy, drop { task_id: ID, result_hash: vector<u8> }

    // === Structs ===

    /// Task tracks a data-labeling assignment.
    public struct Task has key, store {
        id: UID,
        publisher: address,
        dataset: ID,
        reward: Balance<SUI>,
        escrow: Balance<SUI>,
        deadline: u64,
        labeler: Option<address>,
        validators: vector<address>,
        pass_count: u8,
        status: u8,
        result_hash: Option<vector<u8>>,
        gold_hash: Option<vector<u8>>, // For golden sample check
    }

    // === Public Functions ===

    /// Publishes a new annotation task.
    public fun publish_task(
        _: &UploaderCap,
        dataset: ID,
        reward: Coin<SUI>,
        deadline: u64,
        gold_hash: Option<vector<u8>>,
        clock: &Clock,
        ctx: &mut TxContext
    ): Task {
        assert!(deadline > clock::timestamp_ms(clock), E_DEADLINE_PASSED);
        let reward_amount = coin::value(&reward);
        let escrow_amount = (reward_amount * (MIN_ESCROW_PERCENTAGE as u64)) / (BASIS_POINTS_TOTAL as u64);
        
        let mut reward_balance = coin::into_balance(reward);
        let escrow_balance = balance::split(&mut reward_balance, escrow_amount);
        
        let task = Task {
            id: object::new(ctx),
            publisher: tx_context::sender(ctx),
            dataset,
            reward: reward_balance,
            escrow: escrow_balance,
            deadline,
            labeler: option::none(),
            validators: vector::empty(),
            pass_count: 0,
            status: TASK_STATUS_OPEN,
            result_hash: option::none(),
            gold_hash,
        };

        event::emit(TaskPublishedEvent {
            task_id: object::uid_to_inner(&task.id),
            dataset,
            reward_amount,
        });
        task
    }

    /// Claims an annotation task.
    public fun claim_task(
        _: &LabelerCap,
        task: &mut Task,
        escrow: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(task.status == TASK_STATUS_OPEN, E_TASK_NOT_OPEN);
        assert!(clock::timestamp_ms(clock) < task.deadline, E_DEADLINE_PASSED);
        assert!(option::is_none(&task.labeler), E_ALREADY_CLAIMED);
        
        let required_escrow = balance::value(&task.escrow);
        assert!(coin::value(&escrow) >= required_escrow, E_INSUFFICIENT_ESCROW);
        balance::join(&mut task.escrow, coin::into_balance(escrow));
        
        task.labeler = option::some(tx_context::sender(ctx));
        task.status = TASK_STATUS_IN_PROGRESS;
        
        event::emit(TaskClaimedEvent {
            task_id: object::uid_to_inner(&task.id),
            labeler: tx_context::sender(ctx),
        });
    }

    /// Submits labeling result for review.
    public fun submit_task_result(
        task: &mut Task,
        result_hash: vector<u8>,
        ctx: &mut TxContext
    ) {
        assert!(task.status == TASK_STATUS_IN_PROGRESS, E_TASK_NOT_IN_PROGRESS);
        let sender = tx_context::sender(ctx);
        assert!(option::contains(&task.labeler, &sender), E_NOT_AUTHORIZED);

        if (option::is_some(&task.gold_hash)) {
            let gold_hash = option::borrow(&task.gold_hash);
            if (*gold_hash != result_hash) {
                task.status = TASK_STATUS_DISPUTED;
                // Escrow is confiscated and returned to the task publisher.
                let value = balance::value(&task.escrow);
                let confiscated_coin = coin::from_balance(balance::split(&mut task.escrow, value), ctx);
                transfer::public_transfer(confiscated_coin, task.publisher);
                assert!(false, E_INCORRECT_HASH);
            }
        };

        task.result_hash = option::some(result_hash);
        task.status = TASK_STATUS_IN_REVIEW;
        
        event::emit(TaskCompletedEvent {
            task_id: object::uid_to_inner(&task.id),
            result_hash,
        });
    }

    /// Records a validation review.
    public fun submit_review(
        _: &ValidatorCap,
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

    /// Finalizes task: distributes reward or disputes based on consensus.
    public fun finalize_task(
        task: &mut Task,
        ctx: &mut TxContext
    ) {
        assert!(task.status == TASK_STATUS_IN_REVIEW, E_TASK_NOT_IN_REVIEW);
        let total_validators = vector::length(&task.validators);
        assert!(total_validators > 0, E_INSUFFICIENT_VOTES);

        // Consensus: pass_count * 2 > total_validators
        if ((task.pass_count as u64) * 2 > (total_validators as u64)) {
            task.status = TASK_STATUS_COMPLETED;
            if (option::is_some(&task.labeler)) {
                let labeler = *option::borrow(&task.labeler);
                let reward_value = balance::value(&task.reward);
                let escrow_value = balance::value(&task.escrow);
                transfer::public_transfer(coin::from_balance(balance::split(&mut task.reward, reward_value), ctx), labeler);
                transfer::public_transfer(coin::from_balance(balance::split(&mut task.escrow, escrow_value), ctx), labeler);
            };
        } else {
            task.status = TASK_STATUS_DISPUTED;
            // In a disputed case, reward goes back to publisher. Escrow is handled by DAO.
            let reward_value = balance::value(&task.reward);
            transfer::public_transfer(coin::from_balance(balance::split(&mut task.reward, reward_value), ctx), task.publisher);
        };
    }
}
