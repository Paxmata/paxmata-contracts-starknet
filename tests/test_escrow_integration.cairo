use crate::helpers::deploy_token;
use EscrowComponent::InternalTrait;
use openzeppelin::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use paxmata::components::escrow::{EscrowComponent, IEscrow};
use paxmata::test_mocks::escrow::MockEscrowContract;
use snforge_std::{
    EventSpyAssertionsTrait, spy_events, start_cheat_caller_address, stop_cheat_caller_address,
    test_address,
};
use starknet::get_contract_address;
use crate::helpers::addr;
use super::helpers::{
    approve_tokens, transfer_tokens,
};

const DEFAULT_TOKEN_SUPPLY: u256 = 1_000_000;
const DEFAULT_DONATION_FEE_BPS: u16 = 300; // 3%

fn setup() -> (MockEscrowContract::ContractState, IERC20Dispatcher) {
    let token = deploy_token(
        "Test Token",
        "TTK",
        DEFAULT_TOKEN_SUPPLY,
        addr('world'),
    );
    let mut state = MockEscrowContract::contract_state_for_testing();
    state.escrow.initialize(token.contract_address, DEFAULT_DONATION_FEE_BPS); // 3% fee
    (state, token)
}

fn calculate_fee_split(amount: u128, fee_bps: u16) -> (u256, u256) {
    let fee = amount.into() * fee_bps.into() / 10_000;
    let net_amount = amount.into() - fee;
    (net_amount, fee)
}

#[test]
#[should_panic(expected: "Cannot move to refund phase with allocated funds")]
fn test_next_phase_panics_if_allocated_funds() {
    let (mut state, token) = setup();
    let WORLD = addr('world');
    let DONOR = addr('donor');
    let amount = 100;
    transfer_tokens(token, WORLD, DONOR, DEFAULT_TOKEN_SUPPLY);
    approve_tokens(token, DONOR, test_address(), amount.into());
    start_cheat_caller_address(test_address(), DONOR);
    state.escrow.donate(DONOR, amount, addr('treasury'));
    stop_cheat_caller_address(test_address());
    state.escrow.next_phase();
    let (net_amount, _) = calculate_fee_split(amount, DEFAULT_DONATION_FEE_BPS);
    state.escrow.allocate(net_amount);
    state.escrow.next_phase();
}

#[test]
fn test_donate_increases_total_donations() {
    let (mut state, token) = setup();
    let WORLD = addr('world');
    let DONOR = addr('donor');
    let amount = 100;
    transfer_tokens(token, WORLD, DONOR, DEFAULT_TOKEN_SUPPLY);
    approve_tokens(token, DONOR, test_address(), amount.into() * 2);
    start_cheat_caller_address(test_address(), DONOR);
    state.escrow.donate(DONOR, amount, addr('treasury'));
    let (net_amount, _) = calculate_fee_split(amount, DEFAULT_DONATION_FEE_BPS);
    let summary = state.get_escrow_summary();
    assert_eq!(summary.total_donations, net_amount);
    state.escrow.donate(DONOR, amount, addr('treasury'));
    stop_cheat_caller_address(test_address());
    let summary = state.get_escrow_summary();
    assert_eq!(summary.total_donations, net_amount * 2);
}

#[test]
fn test_donate_increases_unallocated() {
    let (mut state, token) = setup();
    let WORLD = addr('world');
    let DONOR = addr('donor');
    let amount = 100;
    transfer_tokens(token, WORLD, DONOR, DEFAULT_TOKEN_SUPPLY);
    approve_tokens(token, DONOR, test_address(), amount.into() * 2);
    let (net_amount, _) = calculate_fee_split(amount, DEFAULT_DONATION_FEE_BPS);
    start_cheat_caller_address(test_address(), DONOR);
    state.escrow.donate(DONOR, amount, addr('treasury'));
    let summary = state.get_escrow_summary();
    assert_eq!(summary.unallocated, net_amount);
    state.escrow.donate(DONOR, amount, addr('treasury'));
    stop_cheat_caller_address(test_address());
    let summary = state.get_escrow_summary();
    assert_eq!(summary.unallocated, net_amount * 2);
}

#[test]
fn test_donate_increases_donor_donation() {
    let (mut state, token) = setup();
    let WORLD = addr('world');
    let DONOR = addr('donor');
    let amount = 100;
    transfer_tokens(token, WORLD, DONOR, DEFAULT_TOKEN_SUPPLY);
    approve_tokens(token, DONOR, test_address(), amount.into() * 2);
    let (net_amount, _) = calculate_fee_split(amount, DEFAULT_DONATION_FEE_BPS);
    start_cheat_caller_address(test_address(), DONOR);
    state.escrow.donate(DONOR, amount, addr('treasury'));
    assert_eq!(state.get_donation(DONOR), net_amount);
    state.escrow.donate(DONOR, amount, addr('treasury'));
    assert_eq!(state.get_donation(DONOR), net_amount * 2);
    stop_cheat_caller_address(test_address());
}

#[test]
fn test_donate_transfers_fee() {
    let (mut state, token) = setup();
    let WORLD = addr('world');
    let DONOR = addr('donor');
    let TREASURY = addr('treasury');
    let amount = 100;
    transfer_tokens(token, WORLD, DONOR, DEFAULT_TOKEN_SUPPLY);
    approve_tokens(token, DONOR, test_address(), amount.into());
    start_cheat_caller_address(test_address(), DONOR);
    let (_, fee) = calculate_fee_split(amount, DEFAULT_DONATION_FEE_BPS);
    state.escrow.donate(DONOR, amount, TREASURY);
    stop_cheat_caller_address(test_address());
    let treasury_balance = token.balance_of(TREASURY);
    assert_eq!(treasury_balance, fee);
}

#[test]
fn test_donate_transfers_net_amount() {
    let (mut state, token) = setup();
    let WORLD = addr('world');
    let DONOR = addr('donor');
    let amount = 100;
    transfer_tokens(token, WORLD, DONOR, DEFAULT_TOKEN_SUPPLY);
    approve_tokens(token, DONOR, test_address(), amount.into());
    let (net_amount, _) = calculate_fee_split(amount, DEFAULT_DONATION_FEE_BPS);
    start_cheat_caller_address(test_address(), DONOR);
    state.escrow.donate(DONOR, amount, addr('treasury'));
    stop_cheat_caller_address(test_address());
    let contract_balance = token.balance_of(get_contract_address());
    assert_eq!(contract_balance, net_amount);
}

#[test]
fn test_donate_emits_donation_event() {
    let (mut state, token) = setup();
    let WORLD = addr('world');
    let DONOR = addr('donor');
    let amount = 100;
    transfer_tokens(token, WORLD, DONOR, DEFAULT_TOKEN_SUPPLY);
    approve_tokens(token, DONOR, test_address(), amount.into());
    let mut spy = spy_events();
    let (net_amount, fee) = calculate_fee_split(amount, DEFAULT_DONATION_FEE_BPS);
    start_cheat_caller_address(test_address(), DONOR);
    state.escrow.donate(DONOR, amount, addr('treasury'));
    stop_cheat_caller_address(test_address());
    let expected_event = EscrowComponent::Event::Donate(
        EscrowComponent::Donate { donor: DONOR, net_amount, fee },
    );
    spy.assert_emitted(@array![(test_address(), expected_event)]);
}

#[test]
fn test_donate_with_zero_fee_transfers_full_amount_to_contract() {
    let token = deploy_token(
        "Test Token",
        "TTK",
        DEFAULT_TOKEN_SUPPLY,
        addr('world'),
    );
    let mut state = MockEscrowContract::contract_state_for_testing();
    state.escrow.initialize(token.contract_address, 0); // 0% fee
    let WORLD = addr('world');
    let DONOR = addr('donor');
    let TREASURY = addr('treasury');
    let amount = 100;
    transfer_tokens(token, WORLD, DONOR, DEFAULT_TOKEN_SUPPLY);
    approve_tokens(token, DONOR, test_address(), amount.into());
    start_cheat_caller_address(test_address(), DONOR);
    state.escrow.donate(DONOR, amount, TREASURY);
    stop_cheat_caller_address(test_address());
    assert_eq!(token.balance_of(get_contract_address()), amount.into());
    assert_eq!(token.balance_of(TREASURY), 0);
}

fn setup_in_payment_phase(
    amount: u128,
) -> (MockEscrowContract::ContractState, IERC20Dispatcher, u256) {
    let (mut state, token) = setup();
    let WORLD = addr('world');
    let DONOR = addr('donor');
    transfer_tokens(token, WORLD, DONOR, DEFAULT_TOKEN_SUPPLY);
    approve_tokens(token, DONOR, test_address(), amount.into());
    start_cheat_caller_address(test_address(), DONOR);
    state.escrow.donate(DONOR, amount, addr('treasury'));
    stop_cheat_caller_address(test_address());
    let (net_amount, _) = calculate_fee_split(amount, DEFAULT_DONATION_FEE_BPS);
    state.escrow.next_phase();
    (state, token, net_amount)
}

fn setup_in_payment_phase_with_allocation(
    amount: u128,
) -> (MockEscrowContract::ContractState, IERC20Dispatcher, u256) {
    let (mut state, token, net_amount) = setup_in_payment_phase(amount);
    state.escrow.allocate(net_amount);
    (state, token, net_amount)
}

fn setup_in_refund_phase(
    amount: u128,
) -> (MockEscrowContract::ContractState, IERC20Dispatcher, u256) {
    let (mut state, token, net_amount) = setup_in_payment_phase(amount);
    state.escrow.next_phase();
    (state, token, net_amount)
}

#[test]
fn test_allocate_decreases_unallocated() {
    let amount = 1000;
    let (mut state, _, net_amount) = setup_in_payment_phase(amount);
    let allocate_amount = net_amount / 2;
    state.escrow.allocate(allocate_amount);
    let summary = state.get_escrow_summary();
    assert_eq!(summary.unallocated, net_amount - allocate_amount);
}

#[test]
fn test_allocate_increases_allocated() {
    let amount = 1000;
    let (mut state, _, net_amount) = setup_in_payment_phase(amount);
    let allocate_amount = net_amount / 2;
    state.escrow.allocate(allocate_amount);
    let summary = state.get_escrow_summary();
    assert_eq!(summary.allocated, allocate_amount);
}

#[test]
fn test_unallocate_decreases_allocated() {
    let amount = 1000;
    let (mut state, _, net_amount) = setup_in_payment_phase_with_allocation(amount);
    let unallocate_amount = net_amount / 2;
    state.escrow.unallocate(unallocate_amount);
    let summary = state.get_escrow_summary();
    assert_eq!(summary.allocated, net_amount - unallocate_amount);
}

#[test]
fn test_unallocate_increases_unallocated() {
    let amount = 1000;
    let (mut state, _, net_amount) = setup_in_payment_phase_with_allocation(amount);
    let unallocate_amount = net_amount / 2;
    state.escrow.unallocate(unallocate_amount);
    let summary = state.get_escrow_summary();
    assert_eq!(summary.unallocated, unallocate_amount);
}

#[test]
fn test_pay_decreases_allocated() {
    let amount = 1000;
    let (mut state, _, net_amount) = setup_in_payment_phase_with_allocation(amount);
    let pay_amount = net_amount / 2;
    let recipient = addr('recipient');
    state.escrow.pay(recipient, pay_amount);
    let summary = state.get_escrow_summary();
    assert_eq!(summary.allocated, net_amount - pay_amount);
}

#[test]
fn test_pay_increases_paid_out() {
    let amount = 1000;
    let (mut state, _, net_amount) = setup_in_payment_phase_with_allocation(amount);
    let pay_amount = net_amount / 2;
    let recipient = addr('recipient');
    state.escrow.pay(recipient, pay_amount);
    let summary = state.get_escrow_summary();
    assert_eq!(summary.paid_out, pay_amount);
}

#[test]
fn test_pay_transfers_tokens() {
    let amount = 1000;
    let (mut state, token, net_amount) = setup_in_payment_phase_with_allocation(amount);
    let pay_amount = net_amount / 2;
    let recipient = addr('recipient');
    state.escrow.pay(recipient, pay_amount);
    assert_eq!(token.balance_of(recipient), pay_amount);
}

#[test]
fn test_pay_emits_payment_event() {
    let amount = 1000;
    let (mut state, _, net_amount) = setup_in_payment_phase_with_allocation(amount);
    let pay_amount = net_amount / 2;
    let recipient = addr('recipient');
    let mut spy = spy_events();
    state.escrow.pay(recipient, pay_amount);
    let expected_event = EscrowComponent::Event::Payment(
        EscrowComponent::Payment { recipient, amount: pay_amount },
    );
    spy.assert_emitted(@array![(test_address(), expected_event)]);
}

#[test]
fn test_refund_zeroes_donor_donation() {
    let amount = 1000;
    let (mut state, _, _) = setup_in_refund_phase(amount);
    let DONOR = addr('donor');
    state.escrow.refund(DONOR);
    assert_eq!(state.get_donation(DONOR), 0);
}

#[test]
fn test_refund_decreases_unallocated() {
    let amount = 1000;
    let (mut state, _, _) = setup_in_refund_phase(amount);
    let DONOR = addr('donor');
    state.escrow.refund(DONOR);
    let summary = state.get_escrow_summary();
    assert_eq!(summary.unallocated, 0);
}

#[test]
fn test_refund_transfers_tokens_to_donor() {
    let amount = 1000;
    let (mut state, token, net_amount) = setup_in_refund_phase(amount);
    let DONOR = addr('donor');
    let donor_balance_before = token.balance_of(DONOR);
    state.escrow.refund(DONOR);
    assert_eq!(token.balance_of(DONOR), donor_balance_before + net_amount);
}

#[test]
fn test_refund_emits_refund_event() {
    let amount = 1000;
    let (mut state, _, net_amount) = setup_in_refund_phase(amount);
    let DONOR = addr('donor');
    let mut spy = spy_events();
    state.escrow.refund(DONOR);
    let expected_event = EscrowComponent::Event::Refund(
        EscrowComponent::Refund { donor: DONOR, amount: net_amount },
    );
    spy.assert_emitted(@array![(test_address(), expected_event)]);
}

#[test]
fn test_refund_with_partial_payout_gives_proportional_amount() {
    // Donate, go to payment, allocate all, pay half, unallocate remainder, go to refund
    // Donor should receive back the proportion of funds not paid out
    let amount = 1000;
    let (mut state, token, net_amount) = setup_in_payment_phase(amount);
    let pay_amount = net_amount / 2;
    let recipient = addr('recipient');
    let DONOR = addr('donor');

    state.escrow.allocate(net_amount);
    state.escrow.pay(recipient, pay_amount);
    state.escrow.unallocate(net_amount - pay_amount);
    state.escrow.next_phase(); // Payment → Refund

    // remaining_deposit = deposit * (total_donations - paid_out) / total_donations
    //                   = net_amount * (net_amount - pay_amount) / net_amount
    //                   = net_amount - pay_amount
    let expected_refund = net_amount - pay_amount;
    let donor_balance_before = token.balance_of(DONOR);
    state.escrow.refund(DONOR);
    assert_eq!(token.balance_of(DONOR), donor_balance_before + expected_refund);
}
