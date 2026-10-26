use starknet::ContractAddress;

#[derive(Drop, Serde)]
pub struct EscrowSummary {
    pub total_donations: u256,
    pub unallocated: u256,
    pub allocated: u256,
    pub paid_out: u256,
}

#[starknet::interface]
pub trait IEscrow<TContractState> {
    fn get_escrow_summary(self: @TContractState) -> EscrowSummary;
    fn get_donation(self: @TContractState, donor: ContractAddress) -> u256;
    fn donation_fee_bps(self: @TContractState) -> u16;
    fn token(self: @TContractState) -> ContractAddress;
}

#[starknet::component]
pub mod EscrowComponent {
    use starknet::get_caller_address;
use core::num::traits::Zero;
    use openzeppelin::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_contract_address};
    use super::EscrowSummary;

    #[derive(Drop, Debug, PartialEq, starknet::Store)]
    pub enum EscrowPhase {
        #[default]
        Donate,
        Payment,
        Refund,
    }

    #[storage]
    pub struct Storage {
        Escrow_donation_fee_bps: u16,
        Escrow_total_donations: u256,
        Escrow_unallocated: u256,
        Escrow_allocated: u256,
        Escrow_paid_out: u256,
        Escrow_token: ContractAddress,
        Escrow_donations: Map<ContractAddress, u256>,
        Escrow_phase: EscrowPhase,
        Escrow_initialized: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        Donate: Donate,
        Payment: Payment,
        Refund: Refund,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Donate {
        #[key]
        pub donor: ContractAddress,
        pub net_amount: u256,
        pub fee: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Refund {
        #[key]
        pub donor: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Payment {
        #[key]
        pub recipient: ContractAddress,
        pub amount: u256,
    }

    #[embeddable_as(EscrowImpl)]
    impl IEscrow<
        TContractState, +HasComponent<TContractState>,
    > of super::IEscrow<ComponentState<TContractState>> {
        fn get_escrow_summary(self: @ComponentState<TContractState>) -> EscrowSummary {
            EscrowSummary {
                total_donations: self.Escrow_total_donations.read(),
                unallocated: self.Escrow_unallocated.read(),
                allocated: self.Escrow_allocated.read(),
                paid_out: self.Escrow_paid_out.read(),
            }
        }

        fn get_donation(self: @ComponentState<TContractState>, donor: ContractAddress) -> u256 {
            self.Escrow_donations.entry(donor).read()
        }

        fn donation_fee_bps(self: @ComponentState<TContractState>) -> u16 {
            self.Escrow_donation_fee_bps.read()
        }

        fn token(self: @ComponentState<TContractState>) -> ContractAddress {
            self.Escrow_token.read()
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        fn initialize(
            ref self: ComponentState<TContractState>, token: ContractAddress, donation_fee_bps: u16,
        ) {
            assert!(!self.Escrow_initialized.read(), "Escrow component already initialized");
            assert!(!token.is_zero(), "Token address cannot be zero");
            assert!(donation_fee_bps <= 1_000, "Donation fee cannot exceed 10%");
            self.Escrow_token.write(token);
            self.Escrow_donation_fee_bps.write(donation_fee_bps);
            self.Escrow_initialized.write(true);
        }

        fn initialized(self: @ComponentState<TContractState>) -> bool {
            self.Escrow_initialized.read()
        }

        fn get_escrow_phase(self: @ComponentState<TContractState>) -> EscrowPhase {
            self.Escrow_phase.read()
        }

        fn get_donation_fee_bps(self: @ComponentState<TContractState>) -> u16 {
            self.Escrow_donation_fee_bps.read()
        }

        fn get_token_address(self: @ComponentState<TContractState>) -> ContractAddress {
            self.Escrow_token.read()
        }

        fn next_phase(ref self: ComponentState<TContractState>) {
            self.assert_initialized();
            let current_phase = self.Escrow_phase.read();
            assert!(current_phase != EscrowPhase::Refund, "Already in final phase");
            if (current_phase == EscrowPhase::Donate) {
                self.Escrow_phase.write(EscrowPhase::Payment);
            } else if (current_phase == EscrowPhase::Payment) {
                assert!(
                    self.Escrow_allocated.read() == 0,
                    "Cannot move to refund phase with allocated funds",
                );
                self.Escrow_phase.write(EscrowPhase::Refund);
            }
        }

        fn donate(
            ref self: ComponentState<TContractState>,
            donor: ContractAddress,
            amount: u128,
            fee_recipient: ContractAddress,
        ) {
            self.assert_initialized();
            assert!(self.Escrow_phase.read() == EscrowPhase::Donate, "Donations are locked");
            assert!(amount > 0, "Donation amount must be greater than zero");
            assert!(!donor.is_zero(), "Donor address cannot be zero");
            assert!(!fee_recipient.is_zero(), "Fee recipient address cannot be zero");
            let (net_amount, fee) = self.calculate_fee_split(amount);
            let total_donations = self.Escrow_total_donations.read() + net_amount;
            let unallocated = self.Escrow_unallocated.read() + net_amount;
            let donation = self.Escrow_donations.entry(donor).read() + net_amount;
            self.Escrow_total_donations.write(total_donations);
            self.Escrow_unallocated.write(unallocated);
            self.Escrow_donations.entry(donor).write(donation);
            let token = IERC20Dispatcher { contract_address: self.Escrow_token.read() };
            // Use caller for transfers to prevent spoofing and allow donations on behalf
            // of an address
            let caller = get_caller_address();
            if (fee > 0) {
                token.transfer_from(caller, fee_recipient, fee);
            }
            token.transfer_from(caller, get_contract_address(), net_amount);
            self.emit(Donate { donor, net_amount, fee });
        }

        fn allocate(ref self: ComponentState<TContractState>, amount: u256) {
            self.assert_initialized();
            assert!(self.Escrow_phase.read() == EscrowPhase::Payment, "Allocation is locked");
            assert!(amount > 0, "Allocation amount must be greater than zero");
            let unallocated = self.Escrow_unallocated.read();
            assert!(amount <= unallocated, "Not enough unallocated funds");
            self.Escrow_unallocated.write(unallocated - amount);
            self.Escrow_allocated.write(self.Escrow_allocated.read() + amount);
        }

        fn unallocate(ref self: ComponentState<TContractState>, amount: u256) {
            self.assert_initialized();
            assert!(self.Escrow_phase.read() == EscrowPhase::Payment, "Unallocation is locked");
            assert!(amount > 0, "Unallocation amount must be greater than zero");
            let allocated = self.Escrow_allocated.read();
            assert!(amount <= allocated, "Not enough allocated funds");
            self.Escrow_allocated.write(allocated - amount);
            self.Escrow_unallocated.write(self.Escrow_unallocated.read() + amount);
        }

        fn pay(ref self: ComponentState<TContractState>, recipient: ContractAddress, amount: u256) {
            self.assert_initialized();
            assert!(self.Escrow_phase.read() == EscrowPhase::Payment, "Payments are locked");
            assert!(amount > 0, "Payment amount must be greater than zero");
            assert!(!recipient.is_zero(), "Recipient address cannot be zero");
            let allocated = self.Escrow_allocated.read();
            assert!(amount <= allocated, "Not enough allocated funds");
            self.Escrow_allocated.write(allocated - amount);
            self.Escrow_paid_out.write(self.Escrow_paid_out.read() + amount);
            let token = IERC20Dispatcher { contract_address: self.Escrow_token.read() };
            token.transfer(recipient, amount);
            self.emit(Payment { recipient, amount });
        }

        fn refund(ref self: ComponentState<TContractState>, donor: ContractAddress) {
            self.assert_initialized();
            assert!(self.Escrow_phase.read() == EscrowPhase::Refund, "Refunds are locked");
            assert!(!donor.is_zero(), "Donor address cannot be zero");
            let deposit = self.Escrow_donations.entry(donor).read();
            assert!(deposit > 0, "No deposit to withdraw");
            let total_donations = self.Escrow_total_donations.read();
            let paid_out = self.Escrow_paid_out.read();
            let remaining_deposit = deposit * (total_donations - paid_out) / total_donations;
            let unallocated = self.Escrow_unallocated.read();
            self.Escrow_donations.entry(donor).write(0);
            if (remaining_deposit > 0) {
                self.Escrow_unallocated.write(unallocated - remaining_deposit);
                let token = IERC20Dispatcher { contract_address: self.Escrow_token.read() };
                token.transfer(donor, remaining_deposit);
                self.emit(Refund { donor, amount: remaining_deposit });
            }
        }

        fn calculate_fee_split(
            self: @ComponentState<TContractState>, amount: u128,
        ) -> (u256, u256) {
            let fee: u256 = amount.into() * self.Escrow_donation_fee_bps.read().into() / 10_000;
            let net_amount: u256 = amount.into() - fee;
            (net_amount, fee)
        }

        fn assert_initialized(self: @ComponentState<TContractState>) {
            assert!(self.Escrow_initialized.read(), "Escrow component not initialized");
        }
    }
}
