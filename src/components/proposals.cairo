use starknet::ContractAddress;

#[derive(Copy, Drop, PartialEq, Serde, starknet::Store)]
pub enum Proposer {
    #[default]
    Owner,
    Developer,
}

#[derive(Clone, Drop, PartialEq, Serde, starknet::Store)]
pub struct MilestoneCreate {
    pub title: ByteArray,
    pub description: ByteArray,
    pub payment: u256,
    pub deadline: u64,
    pub recipient: ContractAddress,
}

#[derive(Clone, Drop, PartialEq, Serde, starknet::Store)]
pub struct MilestoneMetadataUpdate {
    pub milestone_id: u64,
    pub new_title: ByteArray,
    pub new_description: ByteArray,
    pub new_payment: u256,
    pub new_deadline: u64,
    pub new_recipient: ContractAddress,
}

#[derive(Clone, Drop, PartialEq, Serde, starknet::Store)]
pub struct MilestoneComplete {
    pub milestone_id: u64,
    pub proof_uri: ByteArray,
}

#[derive(Clone, Drop, PartialEq, Serde, starknet::Store)]
pub struct MilestoneLinkChild {
    pub parent_id: u64,
    pub child_id: u64,
}

#[derive(Clone, Drop, PartialEq, Serde, starknet::Store)]
pub struct MilestoneUnlinkChild {
    pub parent_id: u64,
    pub child_id: u64,
}

#[derive(Clone, Drop, PartialEq, Serde, starknet::Store)]
pub struct MilestoneDelete {
    pub milestone_id: u64,
}

#[derive(Clone, Drop, PartialEq, Serde, starknet::Store)]
pub enum ProposalData {
    #[default]
    None,
    MilestoneCreate: MilestoneCreate,
    MilestoneMetadataUpdate: MilestoneMetadataUpdate,
    MilestoneComplete: MilestoneComplete,
    MilestoneLinkChild: MilestoneLinkChild,
    MilestoneUnlinkChild: MilestoneUnlinkChild,
    MilestoneDelete: MilestoneDelete,
    ProjectComplete,
}

#[derive(Copy, Debug, Drop, PartialEq, Serde, starknet::Store)]
pub enum ProposalStatus {
    #[default]
    Pending,
    Approved,
    Rejected,
    Cancelled,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct Proposal {
    pub proposer: Proposer,
    pub data: ProposalData,
    pub status: ProposalStatus,
    pub created_at: u64,
}

#[starknet::interface]
pub trait IProposals<TContractState> {
    fn get_proposal(self: @TContractState, proposal_id: u64) -> Option<Proposal>;
}

#[starknet::component]
pub mod ProposalsComponent {
    use starknet::get_block_timestamp;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use super::{Proposal, ProposalData, ProposalStatus, Proposer};

    #[storage]
    pub struct Storage {
        Proposals_total_pending: u64,
        Proposals_current_proposal_id: u64,
        Proposals_proposals: Map<u64, Proposal>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        ProposalCreated: ProposalCreated,
        ProposalAccepted: ProposalAccepted,
        ProposalRejected: ProposalRejected,
        ProposalCancelled: ProposalCancelled,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ProposalCreated {
        #[key]
        pub proposal_id: u64,
        pub proposer: Proposer,
        pub data: ProposalData,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ProposalAccepted {
        #[key]
        pub proposal_id: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ProposalRejected {
        #[key]
        pub proposal_id: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ProposalCancelled {
        #[key]
        pub proposal_id: u64,
    }

    #[embeddable_as(ProposalsImpl)]
    impl Proposals<
        TContractState, +HasComponent<TContractState>,
    > of super::IProposals<ComponentState<TContractState>> {
        fn get_proposal(
            self: @ComponentState<TContractState>, proposal_id: u64,
        ) -> Option<Proposal> {
            if (!self.exists(proposal_id)) {
                return None;
            }
            Some(self.Proposals_proposals.entry(proposal_id).read())
        }
    }


    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        fn create_proposal(
            ref self: ComponentState<TContractState>, proposer: Proposer, data: ProposalData,
        ) -> u64 {
            assert!(data != ProposalData::None, "Cannot create proposal with None data");
            let proposal_id = self.Proposals_current_proposal_id.read() + 1;
            self.Proposals_current_proposal_id.write(proposal_id);
            let proposal = Proposal {
                proposer: proposer,
                data: data.clone(),
                status: ProposalStatus::Pending,
                created_at: get_block_timestamp(),
            };
            self.Proposals_proposals.entry(proposal_id).write(proposal);
            self.Proposals_total_pending.write(self.Proposals_total_pending.read() + 1);
            self.emit(ProposalCreated { proposal_id, proposer, data });
            proposal_id
        }

        fn update_proposal_status(
            ref self: ComponentState<TContractState>, proposal_id: u64, status: ProposalStatus,
        ) {
            assert!(self.exists(proposal_id), "Proposal does not exist");
            let proposal_entry = self.Proposals_proposals.entry(proposal_id);
            assert!(
                proposal_entry.status.read() == ProposalStatus::Pending, "Proposal is not pending",
            );
            assert!(status != ProposalStatus::Pending, "Cannot update proposal to Pending status");
            proposal_entry.status.write(status);
            self.Proposals_total_pending.write(self.Proposals_total_pending.read() - 1);
            match status {
                ProposalStatus::Approved => self.emit(ProposalAccepted { proposal_id }),
                ProposalStatus::Rejected => self.emit(ProposalRejected { proposal_id }),
                ProposalStatus::Cancelled => self.emit(ProposalCancelled { proposal_id }),
                ProposalStatus::Pending => {} // This case is already handled by the assert above
            }
        }

        fn exists(self: @ComponentState<TContractState>, proposal_id: u64) -> bool {
            proposal_id > 0 && proposal_id <= self.Proposals_current_proposal_id.read()
        }

        fn total_pending(self: @ComponentState<TContractState>) -> u64 {
            self.Proposals_total_pending.read()
        }
    }
}
