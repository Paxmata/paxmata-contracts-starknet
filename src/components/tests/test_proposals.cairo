use ProposalsComponent::InternalTrait;
use paxmata::components::proposals::{
    IProposals, MilestoneComplete, MilestoneCreate, MilestoneDelete, MilestoneLinkChild,
    MilestoneMetadataUpdate, MilestoneUnlinkChild, ProposalData, ProposalStatus, ProposalsComponent,
    Proposer,
};
use paxmata::test_mocks::proposals::MockProposalsContract;
use snforge_std::{EventSpyAssertionsTrait, spy_events, start_cheat_block_timestamp_global, test_address};
use starknet::get_block_timestamp;

type ComponentState = ProposalsComponent::ComponentState<MockProposalsContract::ContractState>;

fn setup() -> ComponentState {
    ProposalsComponent::component_state_for_testing()
}

fn create_default_proposal(ref state: ComponentState) -> u64 {
    state.create_proposal(Proposer::Owner, ProposalData::ProjectComplete)
}

#[test]
#[should_panic(expected: "Cannot create proposal with None data")]
fn test_create_proposal_panics_if_none_data() {
    let mut state: ComponentState = setup();
    state.create_proposal(Proposer::Owner, ProposalData::None);
}

#[test]
fn test_create_proposal_returns_sequential_ids() {
    let mut state: ComponentState = setup();
    let id1 = state.create_proposal(Proposer::Owner, ProposalData::ProjectComplete);
    let id2 = state.create_proposal(Proposer::Developer, ProposalData::ProjectComplete);
    assert_eq!(id1, 1);
    assert_eq!(id2, 2);
}

#[test]
fn test_total_pending_is_zero_initially() {
    let state: ComponentState = setup();
    assert_eq!(state.total_pending(), 0);
}

#[test]
fn test_create_proposal_increments_total_pending() {
    let mut state: ComponentState = setup();
    state.create_proposal(Proposer::Owner, ProposalData::ProjectComplete);
    assert_eq!(state.total_pending(), 1);
}

#[test]
fn test_create_multiple_proposals_increments_total_pending_for_each() {
    let mut state: ComponentState = setup();
    state.create_proposal(Proposer::Owner, ProposalData::ProjectComplete);
    state.create_proposal(Proposer::Developer, ProposalData::ProjectComplete);
    assert_eq!(state.total_pending(), 2);
}

#[test]
fn test_create_proposal_status_is_pending() {
    let mut state: ComponentState = setup();
    let id = create_default_proposal(ref state);
    let proposal = state.get_proposal(id).unwrap();
    assert_eq!(proposal.status, ProposalStatus::Pending);
}

#[test]
fn test_create_proposal_stores_owner_proposer() {
    let mut state: ComponentState = setup();
    let id = state.create_proposal(Proposer::Owner, ProposalData::ProjectComplete);
    let proposal = state.get_proposal(id).unwrap();
    match proposal.proposer {
        Proposer::Owner => {},
        _ => panic!("Expected Owner proposer"),
    }
}

#[test]
fn test_create_proposal_stores_developer_proposer() {
    let mut state: ComponentState = setup();
    let id = state.create_proposal(Proposer::Developer, ProposalData::ProjectComplete);
    let proposal = state.get_proposal(id).unwrap();
    match proposal.proposer {
        Proposer::Developer => {},
        _ => panic!("Expected Developer proposer"),
    }
}

#[test]
fn test_create_proposal_stores_project_complete_data() {
    let mut state: ComponentState = setup();
    let id = state.create_proposal(Proposer::Owner, ProposalData::ProjectComplete);
    let proposal = state.get_proposal(id).unwrap();
    match proposal.data {
        ProposalData::ProjectComplete => {},
        _ => panic!("Expected ProjectComplete data"),
    }
}

#[test]
fn test_create_proposal_stores_milestone_create_data() {
    let mut state: ComponentState = setup();
    let data = ProposalData::MilestoneCreate(
        MilestoneCreate {
            title: "New Milestone",
            description: "A new milestone",
            payment: 500,
            deadline: 9999999,
            recipient: 'recipient'.try_into().unwrap(),
        },
    );
    let id = state.create_proposal(Proposer::Owner, data);
    let proposal = state.get_proposal(id).unwrap();
    match proposal.data {
        ProposalData::MilestoneCreate(m) => {
            assert_eq!(m.title, "New Milestone");
            assert_eq!(m.description, "A new milestone");
            assert_eq!(m.payment, 500);
            assert_eq!(m.deadline, 9999999);
            assert_eq!(m.recipient, 'recipient'.try_into().unwrap());
        },
        _ => panic!("Expected MilestoneCreate data"),
    }
}

#[test]
fn test_create_proposal_stores_milestone_metadata_update_data() {
    let mut state: ComponentState = setup();
    let data = ProposalData::MilestoneMetadataUpdate(
        MilestoneMetadataUpdate {
            milestone_id: 3,
            new_title: "Updated",
            new_description: "Updated desc",
            new_payment: 200,
            new_deadline: 8888888,
            new_recipient: 'new_recipient'.try_into().unwrap(),
        },
    );
    let id = state.create_proposal(Proposer::Developer, data);
    let proposal = state.get_proposal(id).unwrap();
    match proposal.data {
        ProposalData::MilestoneMetadataUpdate(m) => {
            assert_eq!(m.milestone_id, 3);
            assert_eq!(m.new_title, "Updated");
            assert_eq!(m.new_payment, 200);
        },
        _ => panic!("Expected MilestoneMetadataUpdate data"),
    }
}

#[test]
fn test_create_proposal_stores_milestone_complete_data() {
    let mut state: ComponentState = setup();
    let data = ProposalData::MilestoneComplete(
        MilestoneComplete { milestone_id: 7, proof_uri: "ipfs://proof" },
    );
    let id = state.create_proposal(Proposer::Owner, data);
    let proposal = state.get_proposal(id).unwrap();
    match proposal.data {
        ProposalData::MilestoneComplete(m) => {
            assert_eq!(m.milestone_id, 7);
            assert_eq!(m.proof_uri, "ipfs://proof");
        },
        _ => panic!("Expected MilestoneComplete data"),
    }
}

#[test]
fn test_create_proposal_stores_milestone_link_child_data() {
    let mut state: ComponentState = setup();
    let data = ProposalData::MilestoneLinkChild(MilestoneLinkChild { parent_id: 1, child_id: 2 });
    let id = state.create_proposal(Proposer::Developer, data);
    let proposal = state.get_proposal(id).unwrap();
    match proposal.data {
        ProposalData::MilestoneLinkChild(m) => {
            assert_eq!(m.parent_id, 1);
            assert_eq!(m.child_id, 2);
        },
        _ => panic!("Expected MilestoneLinkChild data"),
    }
}

#[test]
fn test_create_proposal_stores_milestone_unlink_child_data() {
    let mut state: ComponentState = setup();
    let data = ProposalData::MilestoneUnlinkChild(
        MilestoneUnlinkChild { parent_id: 4, child_id: 5 },
    );
    let id = state.create_proposal(Proposer::Owner, data);
    let proposal = state.get_proposal(id).unwrap();
    match proposal.data {
        ProposalData::MilestoneUnlinkChild(m) => {
            assert_eq!(m.parent_id, 4);
            assert_eq!(m.child_id, 5);
        },
        _ => panic!("Expected MilestoneUnlinkChild data"),
    }
}

#[test]
fn test_create_proposal_stores_milestone_delete_data() {
    let mut state: ComponentState = setup();
    let data = ProposalData::MilestoneDelete(MilestoneDelete { milestone_id: 9 });
    let id = state.create_proposal(Proposer::Developer, data);
    let proposal = state.get_proposal(id).unwrap();
    match proposal.data {
        ProposalData::MilestoneDelete(m) => assert_eq!(m.milestone_id, 9),
        _ => panic!("Expected MilestoneDelete data"),
    }
}

#[test]
fn test_create_proposal_emits_event_project_complete() {
    let mut state: ComponentState = setup();
    let mut spy = spy_events();
    let expected_event = ProposalsComponent::Event::ProposalCreated(
        ProposalsComponent::ProposalCreated {
            proposal_id: 1, proposer: Proposer::Owner, data: ProposalData::ProjectComplete,
        },
    );
    state.create_proposal(Proposer::Owner, ProposalData::ProjectComplete);
    spy.assert_emitted(@array![(test_address(), expected_event)]);
}

#[test]
fn test_get_proposal_returns_none_for_nonexistent() {
    let state: ComponentState = setup();
    assert_eq!(state.get_proposal(999).is_none(), true);
}

#[test]
fn test_get_proposal_returns_none_for_zero_id() {
    let state: ComponentState = setup();
    assert_eq!(state.get_proposal(0).is_none(), true);
}

#[test]
fn test_get_proposal_returns_some_for_existing() {
    let mut state: ComponentState = setup();
    let id = create_default_proposal(ref state);
    assert_eq!(state.get_proposal(id).is_some(), true);
}

#[test]
fn test_get_proposal_returns_none_after_all_consumed() {
    let mut state: ComponentState = setup();
    create_default_proposal(ref state);
    // ID 2 was never created
    assert_eq!(state.get_proposal(2).is_none(), true);
}

#[test]
#[should_panic(expected: "Proposal does not exist")]
fn test_update_proposal_status_panics_if_not_exists() {
    let mut state: ComponentState = setup();
    state.update_proposal_status(999, ProposalStatus::Approved);
}

#[test]
#[should_panic(expected: "Proposal does not exist")]
fn test_update_proposal_status_panics_for_zero_id() {
    let mut state: ComponentState = setup();
    state.update_proposal_status(0, ProposalStatus::Approved);
}

#[test]
#[should_panic(expected: "Cannot update proposal to Pending status")]
fn test_update_proposal_status_panics_if_target_is_pending() {
    let mut state: ComponentState = setup();
    let id = create_default_proposal(ref state);
    state.update_proposal_status(id, ProposalStatus::Pending);
}

#[test]
#[should_panic(expected: "Proposal is not pending")]
fn test_update_proposal_status_panics_if_already_approved() {
    let mut state: ComponentState = setup();
    let id = create_default_proposal(ref state);
    state.update_proposal_status(id, ProposalStatus::Approved);
    state.update_proposal_status(id, ProposalStatus::Rejected);
}

#[test]
#[should_panic(expected: "Proposal is not pending")]
fn test_update_proposal_status_panics_if_already_rejected() {
    let mut state: ComponentState = setup();
    let id = create_default_proposal(ref state);
    state.update_proposal_status(id, ProposalStatus::Rejected);
    state.update_proposal_status(id, ProposalStatus::Approved);
}

#[test]
#[should_panic(expected: "Proposal is not pending")]
fn test_update_proposal_status_panics_if_already_cancelled() {
    let mut state: ComponentState = setup();
    let id = create_default_proposal(ref state);
    state.update_proposal_status(id, ProposalStatus::Cancelled);
    state.update_proposal_status(id, ProposalStatus::Approved);
}

#[test]
fn test_update_proposal_status_to_approved() {
    let mut state: ComponentState = setup();
    let id = create_default_proposal(ref state);
    state.update_proposal_status(id, ProposalStatus::Approved);
    assert_eq!(state.get_proposal(id).unwrap().status, ProposalStatus::Approved);
}

#[test]
fn test_update_proposal_status_to_approved_decrements_total_pending() {
    let mut state: ComponentState = setup();
    let id = create_default_proposal(ref state);
    state.update_proposal_status(id, ProposalStatus::Approved);
    assert_eq!(state.total_pending(), 0);
}

#[test]
fn test_update_proposal_status_to_rejected() {
    let mut state: ComponentState = setup();
    let id = create_default_proposal(ref state);
    state.update_proposal_status(id, ProposalStatus::Rejected);
    assert_eq!(state.get_proposal(id).unwrap().status, ProposalStatus::Rejected);
}

#[test]
fn test_update_proposal_status_to_rejected_decrements_total_pending() {
    let mut state: ComponentState = setup();
    let id = create_default_proposal(ref state);
    state.update_proposal_status(id, ProposalStatus::Rejected);
    assert_eq!(state.total_pending(), 0);
}

#[test]
fn test_update_proposal_status_to_cancelled() {
    let mut state: ComponentState = setup();
    let id = create_default_proposal(ref state);
    state.update_proposal_status(id, ProposalStatus::Cancelled);
    assert_eq!(state.get_proposal(id).unwrap().status, ProposalStatus::Cancelled);
}

#[test]
fn test_update_proposal_status_to_cancelled_decrements_total_pending() {
    let mut state: ComponentState = setup();
    let id = create_default_proposal(ref state);
    state.update_proposal_status(id, ProposalStatus::Cancelled);
    assert_eq!(state.total_pending(), 0);
}

#[test]
fn test_update_proposal_status_does_not_affect_other_proposals() {
    let mut state: ComponentState = setup();
    let id1 = create_default_proposal(ref state);
    let id2 = create_default_proposal(ref state);
    state.update_proposal_status(id1, ProposalStatus::Approved);
    assert_eq!(state.get_proposal(id2).unwrap().status, ProposalStatus::Pending);
}

#[test]
fn test_update_proposal_status_only_decrements_total_pending_for_updated_proposal() {
    let mut state: ComponentState = setup();
    let id1 = create_default_proposal(ref state);
    create_default_proposal(ref state);
    state.update_proposal_status(id1, ProposalStatus::Approved);
    assert_eq!(state.total_pending(), 1);
}

#[test]
fn test_update_proposal_status_emits_accepted_event() {
    let mut state: ComponentState = setup();
    let id = create_default_proposal(ref state);
    let mut spy = spy_events();
    let expected_event = ProposalsComponent::Event::ProposalAccepted(
        ProposalsComponent::ProposalAccepted { proposal_id: id },
    );
    state.update_proposal_status(id, ProposalStatus::Approved);
    spy.assert_emitted(@array![(test_address(), expected_event)]);
}

#[test]
fn test_update_proposal_status_emits_rejected_event() {
    let mut state: ComponentState = setup();
    let id = create_default_proposal(ref state);
    let mut spy = spy_events();
    let expected_event = ProposalsComponent::Event::ProposalRejected(
        ProposalsComponent::ProposalRejected { proposal_id: id },
    );
    state.update_proposal_status(id, ProposalStatus::Rejected);
    spy.assert_emitted(@array![(test_address(), expected_event)]);
}

#[test]
fn test_update_proposal_status_emits_cancelled_event() {
    let mut state: ComponentState = setup();
    let id = create_default_proposal(ref state);
    let mut spy = spy_events();
    let expected_event = ProposalsComponent::Event::ProposalCancelled(
        ProposalsComponent::ProposalCancelled { proposal_id: id },
    );
    state.update_proposal_status(id, ProposalStatus::Cancelled);
    spy.assert_emitted(@array![(test_address(), expected_event)]);
}

#[test]
fn test_proposal_data_preserved_after_approval() {
    let mut state: ComponentState = setup();
    let data = ProposalData::MilestoneDelete(MilestoneDelete { milestone_id: 42 });
    let id = state.create_proposal(Proposer::Developer, data);
    state.update_proposal_status(id, ProposalStatus::Approved);
    let proposal = state.get_proposal(id).unwrap();
    match proposal.data {
        ProposalData::MilestoneDelete(m) => assert_eq!(m.milestone_id, 42),
        _ => panic!("Expected MilestoneDelete data"),
    }
}

#[test]
fn test_proposer_preserved_after_status_update() {
    let mut state: ComponentState = setup();
    let id = state.create_proposal(Proposer::Developer, ProposalData::ProjectComplete);
    state.update_proposal_status(id, ProposalStatus::Rejected);
    let proposal = state.get_proposal(id).unwrap();
    match proposal.proposer {
        Proposer::Developer => {},
        _ => panic!("Expected Developer proposer"),
    }
}

// ===== created_at Tests =====

#[test]
fn test_create_proposal_stores_created_at_matching_block_timestamp() {
    let mut state: ComponentState = setup();
    let expected_ts: u64 = 500000;
    start_cheat_block_timestamp_global(expected_ts);
    let id = state.create_proposal(Proposer::Owner, ProposalData::ProjectComplete);
    let proposal = state.get_proposal(id).unwrap();
    assert_eq!(proposal.created_at, expected_ts);
}

#[test]
fn test_create_proposal_stores_created_at_zero_when_no_timestamp_set() {
    let mut state: ComponentState = setup();
    let id = state.create_proposal(Proposer::Owner, ProposalData::ProjectComplete);
    let proposal = state.get_proposal(id).unwrap();
    assert_eq!(proposal.created_at, get_block_timestamp());
}

#[test]
fn test_create_multiple_proposals_each_stores_their_own_timestamp() {
    let mut state: ComponentState = setup();
    start_cheat_block_timestamp_global(1000);
    let id1 = state.create_proposal(Proposer::Owner, ProposalData::ProjectComplete);
    start_cheat_block_timestamp_global(2000);
    let id2 = state.create_proposal(Proposer::Developer, ProposalData::ProjectComplete);
    assert_eq!(state.get_proposal(id1).unwrap().created_at, 1000);
    assert_eq!(state.get_proposal(id2).unwrap().created_at, 2000);
}

#[test]
fn test_created_at_preserved_after_status_update() {
    let mut state: ComponentState = setup();
    start_cheat_block_timestamp_global(12345);
    let id = state.create_proposal(Proposer::Owner, ProposalData::ProjectComplete);
    state.update_proposal_status(id, ProposalStatus::Approved);
    let proposal = state.get_proposal(id).unwrap();
    assert_eq!(proposal.created_at, 12345);
}
