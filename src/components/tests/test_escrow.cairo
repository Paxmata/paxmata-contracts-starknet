use EscrowComponent::InternalTrait;
use paxmata::components::escrow::EscrowComponent;
use paxmata::test_mocks::escrow::MockEscrowContract;

pub type ComponentState = EscrowComponent::ComponentState<MockEscrowContract::ContractState>;

pub fn setup() -> ComponentState {
    EscrowComponent::component_state_for_testing()
}

#[test]
#[should_panic(expected: "Escrow component already initialized")]
fn test_initialize_panics_on_reinitialization() {
    let mut state = setup();
    let token = 'token'.try_into().unwrap();
    let donation_fee_bps = 50; // 0.5%

    state.initialize(token, donation_fee_bps);
    state.initialize(token, donation_fee_bps);
}

#[test]
#[should_panic(expected: "Token address cannot be zero")]
fn test_initialize_panics_on_zero_token_address() {
    let mut state = setup();
    let token = 0.try_into().unwrap();
    let donation_fee_bps = 50; // 0.5%

    state.initialize(token, donation_fee_bps);
}

#[test]
#[should_panic(expected: "Donation fee cannot exceed 10%")]
fn test_initialize_panics_on_excessive_donation_fee() {
    let mut state = setup();
    let token = 'token'.try_into().unwrap();
    let donation_fee_bps = 1_500; // 15%

    state.initialize(token, donation_fee_bps);
}

#[test]
fn test_initialize() {
    let mut state = setup();
    let token = 'token'.try_into().unwrap();
    let donation_fee_bps = 50; // 0.5%

    state.initialize(token, donation_fee_bps);

    assert_eq!(state.get_token_address(), token);
    assert_eq!(state.get_donation_fee_bps(), donation_fee_bps);
    assert!(state.initialized());
}

#[test]
#[should_panic(expected: "Escrow component not initialized")]
fn test_next_phase_panics_if_not_initialized() {
    let mut state = setup();
    state.next_phase();
}

fn setup_and_initialize() -> ComponentState {
    let mut state = setup();
    let token = 'token'.try_into().unwrap();
    state.initialize(token, 50); // 0.5% fee
    state
}

#[test]
#[should_panic(expected: "Already in final phase")]
fn test_next_phase_panics_if_already_in_final_phase() {
    let mut state = setup_and_initialize();
    state.next_phase(); // Move to Payment
    state.next_phase(); // Move to Refund
    state.next_phase(); // Should panic
}

#[test]
fn test_next_phase_transitions_correctly() {
    let mut state = setup_and_initialize();
    assert_eq!(state.get_escrow_phase(), EscrowComponent::EscrowPhase::Donate);
    state.next_phase();
    assert_eq!(state.get_escrow_phase(), EscrowComponent::EscrowPhase::Payment);
    state.next_phase();
    assert_eq!(state.get_escrow_phase(), EscrowComponent::EscrowPhase::Refund);
}

#[test]
#[should_panic(expected: "Escrow component not initialized")]
fn test_donate_panics_if_not_initialized() {
    let mut state = setup();
    let donor = 'donor'.try_into().unwrap();
    let fee_recipient = 'fee_recipient'.try_into().unwrap();
    state.donate(donor, 100, fee_recipient);
}

#[test]
#[should_panic(expected: "Donations are locked")]
fn test_donate_panics_if_not_in_donate_phase() {
    let mut state = setup_and_initialize();
    let donor = 'donor'.try_into().unwrap();
    let fee_recipient = 'fee_recipient'.try_into().unwrap();
    state.next_phase(); // Move to Payment phase
    state.donate(donor, 100, fee_recipient);
}

#[test]
#[should_panic(expected: "Donation amount must be greater than zero")]
fn test_donate_panics_on_zero_amount() {
    let mut state = setup_and_initialize();
    let donor = 'donor'.try_into().unwrap();
    let fee_recipient = 'fee_recipient'.try_into().unwrap();
    state.donate(donor, 0, fee_recipient);
}


#[test]
#[should_panic(expected: "Donor address cannot be zero")]
fn test_donate_panics_on_zero_donor_address() {
    let mut state = setup_and_initialize();
    let donor = 0.try_into().unwrap();
    let fee_recipient = 'fee_recipient'.try_into().unwrap();
    state.donate(donor, 100, fee_recipient);
}

#[test]
#[should_panic(expected: "Fee recipient address cannot be zero")]
fn test_donate_panics_on_zero_fee_recipient() {
    let mut state = setup_and_initialize();
    let donor = 'donor'.try_into().unwrap();
    let fee_recipient = 0.try_into().unwrap();
    state.donate(donor, 100, fee_recipient);
}

fn setup_in_payment_phase() -> ComponentState {
    let mut state = setup_and_initialize();
    state.next_phase();
    state
}

fn setup_in_refund_phase() -> ComponentState {
    let mut state = setup_in_payment_phase();
    state.next_phase();
    state
}

#[test]
#[should_panic(expected: "Escrow component not initialized")]
fn test_allocate_panics_if_not_initialized() {
    let mut state = setup();
    state.allocate(100);
}

#[test]
#[should_panic(expected: "Allocation is locked")]
fn test_allocate_panics_if_in_donate_phase() {
    let mut state = setup_and_initialize();
    state.allocate(100);
}

#[test]
#[should_panic(expected: "Allocation is locked")]
fn test_allocate_panics_if_in_refund_phase() {
    let mut state = setup_in_refund_phase();
    state.allocate(100);
}

#[test]
#[should_panic(expected: "Allocation amount must be greater than zero")]
fn test_allocate_panics_if_zero_amount() {
    let mut state = setup_in_payment_phase();
    state.allocate(0);
}

#[test]
#[should_panic(expected: "Not enough unallocated funds")]
fn test_allocate_panics_if_insufficient_unallocated() {
    let mut state = setup_in_payment_phase();
    state.allocate(1); // unallocated is 0
}

#[test]
#[should_panic(expected: "Escrow component not initialized")]
fn test_unallocate_panics_if_not_initialized() {
    let mut state = setup();
    state.unallocate(100);
}

#[test]
#[should_panic(expected: "Unallocation is locked")]
fn test_unallocate_panics_if_in_donate_phase() {
    let mut state = setup_and_initialize();
    state.unallocate(100);
}

#[test]
#[should_panic(expected: "Unallocation is locked")]
fn test_unallocate_panics_if_in_refund_phase() {
    let mut state = setup_in_refund_phase();
    state.unallocate(100);
}

#[test]
#[should_panic(expected: "Unallocation amount must be greater than zero")]
fn test_unallocate_panics_if_zero_amount() {
    let mut state = setup_in_payment_phase();
    state.unallocate(0);
}

#[test]
#[should_panic(expected: "Not enough allocated funds")]
fn test_unallocate_panics_if_insufficient_allocated() {
    let mut state = setup_in_payment_phase();
    state.unallocate(1); // allocated is 0
}

#[test]
#[should_panic(expected: "Escrow component not initialized")]
fn test_pay_panics_if_not_initialized() {
    let mut state = setup();
    let recipient = 'recipient'.try_into().unwrap();
    state.pay(recipient, 100);
}

#[test]
#[should_panic(expected: "Payments are locked")]
fn test_pay_panics_if_in_donate_phase() {
    let mut state = setup_and_initialize();
    let recipient = 'recipient'.try_into().unwrap();
    state.pay(recipient, 100);
}

#[test]
#[should_panic(expected: "Payments are locked")]
fn test_pay_panics_if_in_refund_phase() {
    let mut state = setup_in_refund_phase();
    let recipient = 'recipient'.try_into().unwrap();
    state.pay(recipient, 100);
}

#[test]
#[should_panic(expected: "Payment amount must be greater than zero")]
fn test_pay_panics_if_zero_amount() {
    let mut state = setup_in_payment_phase();
    let recipient = 'recipient'.try_into().unwrap();
    state.pay(recipient, 0);
}

#[test]
#[should_panic(expected: "Recipient address cannot be zero")]
fn test_pay_panics_if_zero_recipient() {
    let mut state = setup_in_payment_phase();
    let recipient = 0.try_into().unwrap();
    state.pay(recipient, 100);
}

#[test]
#[should_panic(expected: "Not enough allocated funds")]
fn test_pay_panics_if_insufficient_allocated() {
    let mut state = setup_in_payment_phase();
    let recipient = 'recipient'.try_into().unwrap();
    state.pay(recipient, 100); // allocated is 0
}

#[test]
#[should_panic(expected: "Escrow component not initialized")]
fn test_refund_panics_if_not_initialized() {
    let mut state = setup();
    let donor = 'donor'.try_into().unwrap();
    state.refund(donor);
}

#[test]
#[should_panic(expected: "Refunds are locked")]
fn test_refund_panics_if_in_donate_phase() {
    let mut state = setup_and_initialize();
    let donor = 'donor'.try_into().unwrap();
    state.refund(donor);
}

#[test]
#[should_panic(expected: "Refunds are locked")]
fn test_refund_panics_if_in_payment_phase() {
    let mut state = setup_in_payment_phase();
    let donor = 'donor'.try_into().unwrap();
    state.refund(donor);
}

#[test]
#[should_panic(expected: "Donor address cannot be zero")]
fn test_refund_panics_if_zero_donor() {
    let mut state = setup_in_refund_phase();
    let donor = 0.try_into().unwrap();
    state.refund(donor);
}

#[test]
#[should_panic(expected: "No deposit to withdraw")]
fn test_refund_panics_if_no_deposit() {
    let mut state = setup_in_refund_phase();
    let donor = 'donor'.try_into().unwrap();
    state.refund(donor); // donor has no deposit
}

