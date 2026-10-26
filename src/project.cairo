use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use paxmata::components::proposals::ProposalData;
use starknet::ContractAddress;

const QUOTE_MESSAGE_TYPE_HASH: felt252 =
    0xd1de85460e90100c5c245fff488c86d4c794dc887beec464e9f927f7001c67;

#[derive(Copy, Drop, Hash)]
pub struct QuoteMessage {
    pub developer: ContractAddress,
    pub project: ContractAddress,
    pub amount: u256,
    pub nonce: felt252,
    pub expiry: u64,
}

pub impl StructHashImpl of StructHash<QuoteMessage> {
    fn hash_struct(self: @QuoteMessage) -> felt252 {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(QUOTE_MESSAGE_TYPE_HASH).update_with(*self).finalize()
    }
}

#[derive(Drop, Serde, starknet::Store)]
pub struct OwnerReview {
    pub technical_skills: u8,
    pub timeliness: u8,
    pub teamwork: u8,
    pub communication: u8,
    pub overall: u8,
    pub comments: ByteArray,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct DeveloperReview {
    pub project_clarity: u8,
    pub teamwork: u8,
    pub communication: u8,
    pub overall: u8,
    pub comments: ByteArray,
}

#[starknet::interface]
pub trait IPaxmataProject<TState> {
    fn quote(
        ref self: TState, amount: u256, nonce: felt252, expiry: u64, signature: Array<felt252>,
    );
    fn accept_quote(
        ref self: TState, developer: ContractAddress, amount: u256, donation_deadline: u64,
    );
    fn donate(ref self: TState, amount: u128, donor: ContractAddress);
    fn close_donations(ref self: TState);
    fn create_proposal(ref self: TState, data: ProposalData);
    fn approve_proposal(ref self: TState, id: u64);
    fn reject_proposal(ref self: TState, id: u64);
    fn cancel_proposal(ref self: TState, id: u64);
    fn review_as_owner(ref self: TState, review: OwnerReview);
    fn review_as_developer(ref self: TState, review: DeveloperReview);
    fn terminate(ref self: TState);
    fn refund(ref self: TState);

    // Read-only
    fn engagement_fee(self: @TState) -> u256;
    fn completion_bonus_bps(self: @TState) -> u16;
    fn completion_bonus(self: @TState) -> u256;
    fn donation_goal(self: @TState) -> u256;
    fn donation_deadline(self: @TState) -> u64;
    fn factory(self: @TState) -> ContractAddress;
    fn get_quote(self: @TState, developer: ContractAddress) -> u256;
    fn pending_proposals(self: @TState) -> u64;
    fn owner_review(self: @TState) -> Option<OwnerReview>;
    fn developer_review(self: @TState) -> Option<DeveloperReview>;
}

#[starknet::contract]
pub mod PaxmataProject {
    use core::num::traits::Zero;
    use openzeppelin::interfaces::accounts::{ISRC6Dispatcher, ISRC6DispatcherTrait};
    use openzeppelin::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::utils::cryptography::nonces::NoncesComponent;
    use openzeppelin::utils::snip12::{OffchainMessageHash, SNIP12Metadata};
    use paxmata::components::access::AccessComponent;
    use paxmata::components::escrow::EscrowComponent;
    use paxmata::components::milestones::{MilestoneMetadata, MilestonesComponent};
    use paxmata::components::phases::{Phase, PhasesComponent};
    use paxmata::components::proposals::{ProposalStatus, ProposalsComponent, Proposer};
    use paxmata::factory::{IPaxmataFactoryDispatcher, IPaxmataFactoryDispatcherTrait};
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{get_block_number, get_block_timestamp, get_caller_address, get_contract_address};
    use super::*;

    const MIN_FUNDRAISING_DURATION: u64 = 3600;
    const MIN_PROPOSAL_NOTICE_PERIOD: u64 = 1209600; // 14 days

    component!(path: NoncesComponent, storage: nonces, event: NoncesEvent);
    #[abi(embed_v0)]
    impl NoncesImpl = NoncesComponent::NoncesImpl<ContractState>;
    impl NoncesInternalImpl = NoncesComponent::InternalImpl<ContractState>;

    component!(path: AccessComponent, storage: access, event: AccessEvent);
    #[abi(embed_v0)]
    impl AccessImpl = AccessComponent::AccessImpl<ContractState>;
    impl AccessInternalImpl = AccessComponent::InternalImpl<ContractState>;

    component!(path: EscrowComponent, storage: escrow, event: EscrowEvent);
    #[abi(embed_v0)]
    impl EscrowImpl = EscrowComponent::EscrowImpl<ContractState>;
    impl EscrowInternalImpl = EscrowComponent::InternalImpl<ContractState>;

    component!(path: MilestonesComponent, storage: milestones, event: MilestonesEvent);
    #[abi(embed_v0)]
    impl MilestonesImpl = MilestonesComponent::MilestonesImpl<ContractState>;
    impl MilestonesInternalImpl = MilestonesComponent::InternalImpl<ContractState>;

    component!(path: PhasesComponent, storage: phases, event: PhasesEvent);
    #[abi(embed_v0)]
    impl PhasesImpl = PhasesComponent::PhasesImpl<ContractState>;
    impl PhasesInternalImpl = PhasesComponent::InternalImpl<ContractState>;

    component!(path: ProposalsComponent, storage: proposals, event: ProposalsEvent);
    #[abi(embed_v0)]
    impl ProposalsImpl = ProposalsComponent::ProposalsImpl<ContractState>;
    impl ProposalsInternalImpl = ProposalsComponent::InternalImpl<ContractState>;

    #[storage]
    pub struct Storage {
        engagement_fee: u256,
        completion_bonus_bps: u16,
        completion_bonus: u256,
        donation_goal: u256,
        donation_deadline: u64,
        factory: ContractAddress,
        quotes: Map<ContractAddress, u256>,
        owner_review: Option<OwnerReview>,
        developer_review: Option<DeveloperReview>,
        #[substorage(v0)]
        nonces: NoncesComponent::Storage,
        #[substorage(v0)]
        access: AccessComponent::Storage,
        #[substorage(v0)]
        escrow: EscrowComponent::Storage,
        #[substorage(v0)]
        milestones: MilestonesComponent::Storage,
        #[substorage(v0)]
        phases: PhasesComponent::Storage,
        #[substorage(v0)]
        proposals: ProposalsComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        QuotePlaced: QuotePlaced,
        QuoteAccepted: QuoteAccepted,
        ProjectCompleted: ProjectCompleted,
        ProjectTerminated: ProjectTerminated,
        #[flat]
        NoncesEvent: NoncesComponent::Event,
        #[flat]
        AccessEvent: AccessComponent::Event,
        #[flat]
        EscrowEvent: EscrowComponent::Event,
        #[flat]
        MilestonesEvent: MilestonesComponent::Event,
        #[flat]
        PhasesEvent: PhasesComponent::Event,
        #[flat]
        ProposalsEvent: ProposalsComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    pub struct QuotePlaced {
        #[key]
        pub developer: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct QuoteAccepted {
        #[key]
        pub developer: ContractAddress,
        pub amount: u256,
        pub donation_deadline: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ProjectCompleted {
        #[key]
        pub block: u64,
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ProjectTerminated {
        #[key]
        pub caller: ContractAddress,
        #[key]
        pub block: u64,
        pub timestamp: u64,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        factory: ContractAddress,
        owner: ContractAddress,
        token: ContractAddress,
        engagement_fee: u256,
        donation_fee_bps: u16,
        completion_bonus_bps: u16,
    ) {
        self.factory.write(factory);
        self.access.initialize(owner);
        self.escrow.initialize(token, donation_fee_bps);
        self.engagement_fee.write(engagement_fee);
        assert!(completion_bonus_bps <= 10_000, "Completion bonus cannot exceed 100%");
        self.completion_bonus_bps.write(completion_bonus_bps);
    }

    pub impl SNIP12MetadataImpl of SNIP12Metadata {
        fn name() -> felt252 {
            'PaxmataProject'
        }
        fn version() -> felt252 {
            'v1'
        }
    }

    #[abi(embed_v0)]
    impl IPaxmataProjectImpl of IPaxmataProject<ContractState> {
        fn quote(
            ref self: ContractState,
            amount: u256,
            nonce: felt252,
            expiry: u64,
            signature: Array<felt252>,
        ) {
            self.phases.assert_current_phase(Phase::Quoting);
            assert!(amount > 0, "Quote amount must be greater than zero");
            let caller = get_caller_address();
            assert!(caller != self.access.owner(), "Owner cannot place a quote");
            self.nonces.use_checked_nonce(caller, nonce);
            self.assert_valid_signature(caller, amount, nonce, expiry, signature);

            let current_quote = self.quotes.entry(caller).read();
            self.quotes.entry(caller).write(amount);

            // developers are charged an engagement fee on their first quote for a project
            let engagement_fee = self.engagement_fee.read();
            if (current_quote == 0 && engagement_fee > 0) {
                let paxmata_treasury = self.treasury();
                let token = IERC20Dispatcher { contract_address: self.escrow.token() };
                token.transfer_from(caller, paxmata_treasury, engagement_fee);
            }

            self.emit(QuotePlaced { developer: caller, amount });
        }

        fn accept_quote(
            ref self: ContractState,
            developer: ContractAddress,
            amount: u256,
            donation_deadline: u64,
        ) {
            self.phases.assert_current_phase(Phase::Quoting);
            self.access.assert_only_owner();
            assert!(amount > 0, "Amount must be greater than zero");
            let current_quote = self.quotes.entry(developer).read();
            assert!(current_quote == amount, "Quote does not match the developer's current quote");
            let timestamp = get_block_timestamp();
            assert!(
                donation_deadline > timestamp + MIN_FUNDRAISING_DURATION,
                "Donation deadline must be greater than current time + minimum fundraising duration",
            );

            self.access.set_developer(developer);
            self.donation_goal.write(amount);
            self.donation_deadline.write(donation_deadline);
            self.phases.change_phase(Phase::Fundraising);

            self.emit(QuoteAccepted { developer, amount, donation_deadline });
        }

        fn donate(ref self: ContractState, amount: u128, donor: ContractAddress) {
            self.phases.assert_current_phase(Phase::Fundraising);
            self.escrow.donate(donor, amount, self.treasury());
        }

        fn close_donations(ref self: ContractState) {
            // Intentionally allow anyone to call this function to prevent blocking
            self.phases.assert_current_phase(Phase::Fundraising);
            let total_donations = self.escrow.get_escrow_summary().total_donations;
            let donation_goal = self.donation_goal.read();
            let owner_fully_funded = get_caller_address() == self.access.owner()
                && total_donations >= donation_goal;
            assert!(
                get_block_timestamp() >= self.donation_deadline.read() || owner_fully_funded,
                "Donation deadline has not been reached and the project is not fully owner-funded",
            );

            self.escrow.next_phase();
            if (total_donations >= donation_goal) {
                let completion_bonus = (total_donations * self.completion_bonus_bps.read().into())
                    / 10_000;
                self.completion_bonus.write(completion_bonus);
                if (completion_bonus > 0) {
                    self.escrow.allocate(completion_bonus);
                }
                self.phases.change_phase(Phase::Development);
            } else {
                self.escrow.next_phase();
                self.phases.change_phase(Phase::Closed);
            }
        }

        fn create_proposal(ref self: ContractState, data: ProposalData) {
            self.access.assert_only_owner_or_developer();
            self.assert_either_phase(Phase::Development, Phase::ProposalPending);
            self.assert_proposal_executable(@data);

            let proposer = if get_caller_address() == self.access.owner() {
                Proposer::Owner
            } else {
                Proposer::Developer
            };

            self.proposals.create_proposal(proposer, data);
            self.phases.change_phase(Phase::ProposalPending);
        }

        fn approve_proposal(ref self: ContractState, id: u64) {
            self.access.assert_only_owner_or_developer();
            self.phases.assert_current_phase(Phase::ProposalPending);
            assert!(self.proposals.exists(id), "Proposal does not exist");
            let proposal = self.proposals.get_proposal(id).unwrap();
            let approver = if get_caller_address() == self.access.owner() {
                Proposer::Owner
            } else {
                Proposer::Developer
            };
            
            let timestamp = get_block_timestamp();
            assert!(
                proposal.proposer != approver || proposal.created_at + MIN_PROPOSAL_NOTICE_PERIOD <= timestamp,
                "Proposer cannot approve their own proposal until the notice period has passed",
            )

            self.proposals.update_proposal_status(id, ProposalStatus::Approved);
            if (self.proposals.total_pending() == 0) {
                self.phases.change_phase(Phase::Development);
            }

            match @proposal.data {
                ProposalData::None => panic!("Invalid proposal type: None"),
                ProposalData::MilestoneCreate(data) => {
                    let payment = *data.payment;
                    let metadata = MilestoneMetadata {
                        title: data.title.clone(),
                        description: data.description.clone(),
                        payment: payment,
                        deadline: *data.deadline,
                        recipient: *data.recipient,
                    };
                    if payment > 0 {
                        self.escrow.allocate(payment);
                    }
                    self.milestones.create(metadata);
                },
                ProposalData::MilestoneMetadataUpdate(data) => {
                    let old_payment = self
                        .milestones
                        .get_milestone(*data.milestone_id)
                        .unwrap()
                        .payment;
                    let new_payment = *data.new_payment;
                    let metadata = MilestoneMetadata {
                        title: data.new_title.clone(),
                        description: data.new_description.clone(),
                        payment: new_payment,
                        deadline: *data.new_deadline,
                        recipient: *data.new_recipient,
                    };
                    self.milestones.update_metadata(*data.milestone_id, metadata);
                    if (new_payment > old_payment) {
                        self.escrow.allocate(new_payment - old_payment);
                    } else if (new_payment < old_payment) {
                        self.escrow.unallocate(old_payment - new_payment);
                    }
                },
                ProposalData::MilestoneComplete(data) => {
                    let milestone = self.milestones.get_milestone(*data.milestone_id).unwrap();
                    if (milestone.payment > 0) {
                        assert!(data.proof_uri != @"", "Proof URI is required for paid milestones");
                    }
                    self.milestones.complete(*data.milestone_id);
                    
                    if (milestone.payment > 0) {
                        self.escrow.pay(milestone.recipient, milestone.payment);
                    }
                },
                ProposalData::MilestoneLinkChild(data) => {
                    self.milestones.link_child(*data.parent_id, *data.child_id);
                },
                ProposalData::MilestoneUnlinkChild(data) => {
                    self.milestones.unlink_child(*data.parent_id, *data.child_id);
                },
                ProposalData::MilestoneDelete(data) => {
                    let milestone = self.milestones.get_milestone(*data.milestone_id).unwrap();
                    if (milestone.payment > 0) {
                        self.escrow.unallocate(milestone.payment);
                    }
                    self.milestones.delete(*data.milestone_id);
                },
                ProposalData::ProjectComplete => {
                    assert!(self.milestones.all_completed(), "All milestones must be completed");
                    assert!(self.owner_review.is_some(), "Owner review missing");
                    assert!(self.developer_review.is_some(), "Developer review missing");
                    let completion_bonus = self.completion_bonus.read();
                    if completion_bonus > 0 {
                        self.escrow.pay(self.access.developer(), completion_bonus);
                    }
                    let allocated = self.escrow.get_escrow_summary().allocated;
                    assert!(
                        allocated == 0, "All funds must be paid out before completing the project",
                    );
                    self.escrow.next_phase();
                    self.phases.change_phase(Phase::Closed);
                    let event = ProjectCompleted {
                        block: get_block_number(), timestamp: get_block_timestamp(),
                    };
                    self.emit(event);
                },
            }
        }

        fn reject_proposal(ref self: ContractState, id: u64) {
            self.access.assert_only_owner_or_developer();
            self.phases.assert_current_phase(Phase::ProposalPending);
            assert!(self.proposals.exists(id), "Proposal does not exist");
            let proposal = self.proposals.get_proposal(id).unwrap();
            let rejector = if get_caller_address() == self.access.owner() {
                Proposer::Owner
            } else {
                Proposer::Developer
            };
            assert!(proposal.proposer != rejector, "Caller cannot reject their own proposal");

            self.proposals.update_proposal_status(id, ProposalStatus::Rejected);
            if (self.proposals.total_pending() == 0) {
                self.phases.change_phase(Phase::Development);
            }
        }

        fn cancel_proposal(ref self: ContractState, id: u64) {
            self.access.assert_only_owner_or_developer();
            self.phases.assert_current_phase(Phase::ProposalPending);
            assert!(self.proposals.exists(id), "Proposal does not exist");
            let proposal = self.proposals.get_proposal(id).unwrap();
            let caller = get_caller_address();
            let proposer = if caller == self.access.owner() {
                Proposer::Owner
            } else {
                Proposer::Developer
            };
            assert!(proposal.proposer == proposer, "Caller can only cancel their own proposal");

            self.proposals.update_proposal_status(id, ProposalStatus::Cancelled);
            if (self.proposals.total_pending() == 0) {
                self.phases.change_phase(Phase::Development);
            }
        }

        fn review_as_owner(ref self: ContractState, review: OwnerReview) {
            self.access.assert_only_owner();
            assert!(self.owner_review.read().is_none(), "Owner has already submitted a review");
            self.assert_either_phase(Phase::Development, Phase::ProposalPending);
            self.assert_valid_score(review.technical_skills);
            self.assert_valid_score(review.timeliness);
            self.assert_valid_score(review.teamwork);
            self.assert_valid_score(review.communication);
            self.assert_valid_score(review.overall);
            self.owner_review.write(Some(review));
        }

        fn review_as_developer(ref self: ContractState, review: DeveloperReview) {
            self.access.assert_only_developer();
            assert!(
                self.developer_review.read().is_none(), "Developer has already submitted a review",
            );
            self.assert_either_phase(Phase::Development, Phase::ProposalPending);
            self.assert_valid_score(review.project_clarity);
            self.assert_valid_score(review.teamwork);
            self.assert_valid_score(review.communication);
            self.assert_valid_score(review.overall);
            self.developer_review.write(Some(review));
        }

        fn terminate(ref self: ContractState) {
            self.assert_either_phase(Phase::Development, Phase::ProposalPending);
            self.access.assert_only_owner_or_developer();
            let allocated = self.escrow.get_escrow_summary().allocated;
            if (allocated > 0) {
                self.escrow.unallocate(allocated);
            }
            self.escrow.next_phase();
            self.phases.change_phase(Phase::Closed);
            let event = ProjectTerminated {
                caller: get_caller_address(),
                block: get_block_number(),
                timestamp: get_block_timestamp(),
            };
            self.emit(event);
        }

        fn refund(ref self: ContractState) {
            self.phases.assert_current_phase(Phase::Closed);
            self.escrow.refund(get_caller_address());
        }

        // Read-only functions
        fn engagement_fee(self: @ContractState) -> u256 {
            self.engagement_fee.read()
        }

        fn completion_bonus_bps(self: @ContractState) -> u16 {
            self.completion_bonus_bps.read()
        }

        fn completion_bonus(self: @ContractState) -> u256 {
            self.completion_bonus.read()
        }

        fn donation_goal(self: @ContractState) -> u256 {
            self.donation_goal.read()
        }

        fn donation_deadline(self: @ContractState) -> u64 {
            self.donation_deadline.read()
        }

        fn factory(self: @ContractState) -> ContractAddress {
            self.factory.read()
        }

        fn get_quote(self: @ContractState, developer: ContractAddress) -> u256 {
            self.quotes.entry(developer).read()
        }

        fn pending_proposals(self: @ContractState) -> u64 {
            self.proposals.total_pending()
        }

        fn owner_review(self: @ContractState) -> Option<OwnerReview> {
            self.owner_review.read()
        }

        fn developer_review(self: @ContractState) -> Option<DeveloperReview> {
            self.developer_review.read()
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn treasury(self: @ContractState) -> ContractAddress {
            let factory_dispatcher = IPaxmataFactoryDispatcher {
                contract_address: self.factory.read(),
            };
            factory_dispatcher.treasury()
        }

        fn assert_valid_signature(
            self: @ContractState,
            developer: ContractAddress,
            amount: u256,
            nonce: felt252,
            expiry: u64,
            signature: Array<felt252>,
        ) {
            let block_timestamp = get_block_timestamp();
            assert!(expiry > block_timestamp, "Signature has expired");

            let signer = IPaxmataFactoryDispatcher { contract_address: self.factory() }.signer();
            let project = get_contract_address();
            let message = QuoteMessage { developer, project, amount, nonce, expiry };
            let hash = message.get_message_hash(signer);
            let is_valid_signature_felt = ISRC6Dispatcher { contract_address: signer }
                .is_valid_signature(hash, signature);
            // Check either 'VALID' or true for backwards compatibility
            let is_valid_signature = is_valid_signature_felt == starknet::VALIDATED
                || is_valid_signature_felt == 1;
            assert!(is_valid_signature, "Invalid signature");
        }

        fn assert_either_phase(self: @ContractState, phase1: Phase, phase2: Phase) {
            let current_phase = self.phases.current_phase();
            assert!(
                current_phase == phase1 || current_phase == phase2,
                "Expected phase: {} or {}, but current phase is: {}",
                phase1,
                phase2,
                current_phase,
            );
        }

        fn assert_valid_score(self: @ContractState, score: u8) {
            assert!(score <= 10, "Score must be between 0 and 10");
        }

        // Rejects proposals that could never be approved. A proposal that only fails when it is
        // executed in `approve_proposal` still gets stored, and it blocks the project until the
        // counterparty rejects it. These checks mirror the execution-time asserts (which stay in
        // place as defence in depth) so the transaction reverts before anything is stored.
        fn assert_proposal_executable(self: @ContractState, data: @ProposalData) {
            match data {
                ProposalData::MilestoneCreate(data) => {
                    assert!(
                        !data.recipient.is_zero(), "Milestone recipient cannot be the zero address",
                    );
                    assert!(
                        *data.deadline > get_block_timestamp(),
                        "Milestone deadline must be in the future",
                    );
                },
                ProposalData::MilestoneMetadataUpdate(data) => {
                    assert!(
                        !data.new_recipient.is_zero(),
                        "Milestone recipient cannot be the zero address",
                    );
                    assert!(
                        *data.new_deadline > get_block_timestamp(),
                        "Milestone deadline must be in the future",
                    );
                },
                ProposalData::MilestoneComplete(data) => {
                    if let Some(milestone) = self.milestones.get_milestone(*data.milestone_id) {
                        if milestone.payment > 0 {
                            assert!(
                                data.proof_uri != @"", "Proof URI is required for paid milestones",
                            );
                        }
                    }
                },
                _ => {},
            }
        }
    }

    #[cfg(test)]
    mod constructor_tests {
        use starknet::ContractAddress;
        use super::{constructor, contract_state_for_testing};

        fn address(value: felt252) -> ContractAddress {
            value.try_into().unwrap()
        }

        #[test]
        #[should_panic(expected: "Completion bonus cannot exceed 100%")]
        fn test_constructor_panics_if_completion_bonus_exceeds_max() {
            let mut state = contract_state_for_testing();
            constructor(
                ref state, address('factory'), address('owner'), address('token'), 100, 300, 10_001,
            );
        }
    }
}
