use MilestonesComponent::InternalTrait;
use paxmata::components::milestones::{IMilestones, MilestoneMetadata, MilestonesComponent};
use paxmata::test_mocks::milestones::MockMilestonesContract;
use snforge_std::{
    EventSpyAssertionsTrait, spy_events, start_cheat_block_timestamp_global, test_address,
};
use starknet::get_block_timestamp;

type ComponentState = MilestonesComponent::ComponentState<MockMilestonesContract::ContractState>;

fn setup() -> ComponentState {
    MilestonesComponent::component_state_for_testing()
}

#[test]
fn test_initial() {
    let mut state: ComponentState = setup();
    assert_eq!(state.current_id(), 0);
}

#[test]
#[should_panic(expected: "Milestone recipient cannot be the zero address")]
fn test_create_panics_if_recipient_is_zero() {
    let mut state: ComponentState = setup();
    let metadata = MilestoneMetadata {
        title: "Test Milestone",
        description: "This is a test milestone",
        deadline: get_block_timestamp() + 1000,
        payment: 0,
        recipient: 0.try_into().unwrap(),
    };
    state.create(metadata);
}

#[test]
#[should_panic(expected: "Milestone deadline must be in the future")]
fn test_create_panics_if_deadline_in_past() {
    let mut state: ComponentState = setup();
    // Advance timestamp to prevent underflow
    start_cheat_block_timestamp_global(get_block_timestamp() + 1);
    let metadata = MilestoneMetadata {
        title: "Test Milestone",
        description: "This is a test milestone",
        deadline: get_block_timestamp() - 1,
        payment: 0,
        recipient: 'recipient'.try_into().unwrap(),
    };
    state.create(metadata);
}

#[test]
fn test_create_milestone_increments_id() {
    let mut state: ComponentState = setup();
    let metadata = MilestoneMetadata {
        title: "Test Milestone",
        description: "This is a test milestone",
        deadline: get_block_timestamp() + 1000,
        payment: 0,
        recipient: 'recipient'.try_into().unwrap(),
    };
    state.create(metadata);
    assert_eq!(state.current_id(), 1);
}

#[test]
fn test_create_stores_milestone_data() {
    let mut state: ComponentState = setup();
    let metadata = MilestoneMetadata {
        title: "Test Milestone",
        description: "This is a test milestone",
        deadline: get_block_timestamp() + 1000,
        payment: 0,
        recipient: 'recipient'.try_into().unwrap(),
    };
    state.create(metadata.clone());
    let stored = state.get_milestone(1);
    assert_eq!(stored.is_some(), true);
    let stored_metadata = stored.unwrap();
    assert_eq!(stored_metadata.title, metadata.title);
    assert_eq!(stored_metadata.description, metadata.description);
    assert_eq!(stored_metadata.deadline, metadata.deadline);
    assert_eq!(stored_metadata.payment, metadata.payment);
    assert_eq!(stored_metadata.recipient, metadata.recipient);
}

#[test]
fn test_create_emits_event() {
    let mut state: ComponentState = setup();
    let metadata = MilestoneMetadata {
        title: "Test Milestone",
        description: "This is a test milestone",
        deadline: get_block_timestamp() + 1000,
        payment: 0,
        recipient: 'recipient'.try_into().unwrap(),
    };
    let mut spy = spy_events();
    let expected_event = MilestonesComponent::Event::MilestoneCreated(
        MilestonesComponent::MilestoneCreated { id: 1, metadata: metadata.clone() },
    );
    state.create(metadata);
    spy.assert_emitted(@array![(test_address(), expected_event)]);
}

fn create_default_milestone(ref state: ComponentState) -> u64 {
    state
        .create(
            MilestoneMetadata {
                title: "Test Milestone",
                description: "This is a test milestone",
                deadline: get_block_timestamp() + 1000,
                payment: 100,
                recipient: 'recipient'.try_into().unwrap(),
            },
        )
}

#[test]
fn test_get_milestone_returns_none_for_nonexistent() {
    let state: ComponentState = setup();
    assert_eq!(state.get_milestone(999).is_none(), true);
}

#[test]
#[should_panic(expected: "Milestone does not exist")]
fn test_update_metadata_panics_if_not_exists() {
    let mut state: ComponentState = setup();
    state
        .update_metadata(
            999,
            MilestoneMetadata {
                title: "Updated",
                description: "Updated",
                deadline: get_block_timestamp() + 2000,
                payment: 200,
                recipient: 'recipient'.try_into().unwrap(),
            },
        );
}

#[test]
#[should_panic(expected: "Cannot update completed milestone")]
fn test_update_metadata_panics_if_completed() {
    let mut state: ComponentState = setup();
    let id = create_default_milestone(ref state);
    state.complete(id);
    state
        .update_metadata(
            id,
            MilestoneMetadata {
                title: "Updated",
                description: "Updated",
                deadline: get_block_timestamp() + 2000,
                payment: 200,
                recipient: 'recipient'.try_into().unwrap(),
            },
        );
}

#[test]
#[should_panic(expected: "Milestone recipient cannot be the zero address")]
fn test_update_metadata_panics_if_recipient_zero() {
    let mut state: ComponentState = setup();
    let id = create_default_milestone(ref state);
    state
        .update_metadata(
            id,
            MilestoneMetadata {
                title: "Updated",
                description: "Updated",
                deadline: get_block_timestamp() + 2000,
                payment: 200,
                recipient: 0.try_into().unwrap(),
            },
        );
}

#[test]
#[should_panic(expected: "Milestone deadline must be in the future")]
fn test_update_metadata_panics_if_deadline_past() {
    let mut state: ComponentState = setup();
    start_cheat_block_timestamp_global(get_block_timestamp() + 1);
    let id = create_default_milestone(ref state);
    state
        .update_metadata(
            id,
            MilestoneMetadata {
                title: "Updated",
                description: "Updated",
                deadline: get_block_timestamp() - 1,
                payment: 200,
                recipient: 'recipient'.try_into().unwrap(),
            },
        );
}

#[test]
fn test_update_metadata_updates_data() {
    let mut state: ComponentState = setup();
    let id = create_default_milestone(ref state);
    let new_metadata = MilestoneMetadata {
        title: "Updated Milestone",
        description: "Updated description",
        deadline: get_block_timestamp() + 2000,
        payment: 200,
        recipient: 'new_recipient'.try_into().unwrap(),
    };
    state.update_metadata(id, new_metadata.clone());
    let stored = state.get_milestone(id).unwrap();
    assert_eq!(stored.title, new_metadata.title);
    assert_eq!(stored.description, new_metadata.description);
    assert_eq!(stored.deadline, new_metadata.deadline);
    assert_eq!(stored.payment, new_metadata.payment);
    assert_eq!(stored.recipient, new_metadata.recipient);
}

#[test]
fn test_update_metadata_emits_event() {
    let mut state: ComponentState = setup();
    let old_metadata = MilestoneMetadata {
        title: "Test Milestone",
        description: "This is a test milestone",
        deadline: get_block_timestamp() + 1000,
        payment: 100,
        recipient: 'recipient'.try_into().unwrap(),
    };
    let id = state.create(old_metadata.clone());
    let new_metadata = MilestoneMetadata {
        title: "Updated Milestone",
        description: "Updated description",
        deadline: get_block_timestamp() + 2000,
        payment: 200,
        recipient: 'new_recipient'.try_into().unwrap(),
    };
    let mut spy = spy_events();
    let expected_event = MilestonesComponent::Event::MilestoneMetadataUpdated(
        MilestonesComponent::MilestoneMetadataUpdated {
            id, old_metadata, new_metadata: new_metadata.clone(),
        },
    );
    state.update_metadata(id, new_metadata);
    spy.assert_emitted(@array![(test_address(), expected_event)]);
}

#[test]
#[should_panic(expected: "Parent milestone does not exist")]
fn test_link_child_panics_if_parent_not_exists() {
    let mut state: ComponentState = setup();
    let child_id = create_default_milestone(ref state);
    state.link_child(999, child_id);
}

#[test]
#[should_panic(expected: "Child milestone does not exist")]
fn test_link_child_panics_if_child_not_exists() {
    let mut state: ComponentState = setup();
    let parent_id = create_default_milestone(ref state);
    state.link_child(parent_id, 999);
}

#[test]
#[should_panic(expected: "Cannot link to completed parent milestone")]
fn test_link_child_panics_if_parent_completed() {
    let mut state: ComponentState = setup();
    let parent_id = create_default_milestone(ref state);
    let child_id = create_default_milestone(ref state);
    state.complete(parent_id);
    state.link_child(parent_id, child_id);
}

#[test]
#[should_panic(expected: "Cannot link completed child milestone")]
fn test_link_child_panics_if_child_completed() {
    let mut state: ComponentState = setup();
    let parent_id = create_default_milestone(ref state);
    let child_id = create_default_milestone(ref state);
    state.complete(child_id);
    state.link_child(parent_id, child_id);
}

#[test]
#[should_panic(expected: "Parent milestone has maximum number of children")]
fn test_link_child_panics_if_max_children() {
    let mut state: ComponentState = setup();
    let parent_id = create_default_milestone(ref state);
    // MAX_CHILDREN = 10
    for _ in 0..10_u64 {
        let child_id = create_default_milestone(ref state);
        state.link_child(parent_id, child_id);
    }
    let extra_id = create_default_milestone(ref state);
    state.link_child(parent_id, extra_id);
}

#[test]
#[should_panic(expected: "Child milestone already has a parent")]
fn test_link_child_panics_if_child_already_has_parent() {
    let mut state: ComponentState = setup();
    let parent1_id = create_default_milestone(ref state);
    let parent2_id = create_default_milestone(ref state);
    let child_id = create_default_milestone(ref state);
    state.link_child(parent1_id, child_id);
    state.link_child(parent2_id, child_id);
}

#[test]
#[should_panic(expected: "Cannot create circular milestone hierarchy")]
fn test_link_child_panics_if_circular() {
    let mut state: ComponentState = setup();
    let m1_id = create_default_milestone(ref state);
    let m2_id = create_default_milestone(ref state);
    state.link_child(m1_id, m2_id);
    state.link_child(m2_id, m1_id);
}

#[test]
#[should_panic(expected: "Linking would exceed maximum milestone hierarchy depth")]
fn test_link_child_panics_if_exceeds_max_depth() {
    let mut state: ComponentState = setup();
    // MAX_DEPTH = 3: build chain m1 -> m2 -> m3 (m3 at depth 3)
    let m1_id = create_default_milestone(ref state);
    let m2_id = create_default_milestone(ref state);
    let m3_id = create_default_milestone(ref state);
    state.link_child(m1_id, m2_id);
    state.link_child(m2_id, m3_id);
    // depth(m3) + height(m4) = 3 + 1 = 4 > MAX_DEPTH
    let m4_id = create_default_milestone(ref state);
    state.link_child(m3_id, m4_id);
}

#[test]
fn test_link_child_stores_relationship() {
    let mut state: ComponentState = setup();
    let parent_id = create_default_milestone(ref state);
    let child_id = create_default_milestone(ref state);
    state.link_child(parent_id, child_id);
    let parent = state.get_milestone(parent_id).unwrap();
    let child = state.get_milestone(child_id).unwrap();
    assert_eq!(parent.children_ids.len(), 1);
    assert_eq!(*parent.children_ids.at(0), child_id);
    assert_eq!(child.parent_id, parent_id);
}

#[test]
fn test_link_child_accepts_subtree_at_max_depth() {
    let mut state: ComponentState = setup();
    let parent_id = create_default_milestone(ref state);
    let subtree_root_id = create_default_milestone(ref state);
    let subtree_child_id = create_default_milestone(ref state);

    state.link_child(subtree_root_id, subtree_child_id);
    state.link_child(parent_id, subtree_root_id);

    let parent = state.get_milestone(parent_id).unwrap();
    let subtree_root = state.get_milestone(subtree_root_id).unwrap();
    assert_eq!(*parent.children_ids.at(0), subtree_root_id);
    assert_eq!(subtree_root.parent_id, parent_id);
    assert_eq!(*subtree_root.children_ids.at(0), subtree_child_id);
}

#[test]
fn test_link_child_emits_event() {
    let mut state: ComponentState = setup();
    let parent_id = create_default_milestone(ref state);
    let child_id = create_default_milestone(ref state);
    let mut spy = spy_events();
    let expected_event = MilestonesComponent::Event::MilestoneChildLinked(
        MilestonesComponent::MilestoneChildLinked { parent_id, child_id },
    );
    state.link_child(parent_id, child_id);
    spy.assert_emitted(@array![(test_address(), expected_event)]);
}

#[test]
#[should_panic(expected: "Parent milestone does not exist")]
fn test_unlink_child_panics_if_parent_not_exists() {
    let mut state: ComponentState = setup();
    let child_id = create_default_milestone(ref state);
    state.unlink_child(999, child_id);
}

#[test]
#[should_panic(expected: "Child milestone does not exist")]
fn test_unlink_child_panics_if_child_not_exists() {
    let mut state: ComponentState = setup();
    let parent_id = create_default_milestone(ref state);
    state.unlink_child(parent_id, 999);
}

#[test]
#[should_panic(expected: "Cannot unlink from completed parent milestone")]
fn test_unlink_child_panics_if_parent_completed() {
    let mut state: ComponentState = setup();
    let parent_id = create_default_milestone(ref state);
    let child_id = create_default_milestone(ref state);
    state.link_child(parent_id, child_id);
    state.complete(child_id);
    state.complete(parent_id);
    state.unlink_child(parent_id, child_id);
}

#[test]
#[should_panic(expected: "Cannot unlink completed child milestone")]
fn test_unlink_child_panics_if_child_completed() {
    let mut state: ComponentState = setup();
    let parent_id = create_default_milestone(ref state);
    let child_id = create_default_milestone(ref state);
    state.link_child(parent_id, child_id);
    state.complete(child_id);
    state.unlink_child(parent_id, child_id);
}

#[test]
#[should_panic(expected: "Parent milestone does not contain this child")]
fn test_unlink_child_panics_if_not_child() {
    let mut state: ComponentState = setup();
    let parent_id = create_default_milestone(ref state);
    let child_id = create_default_milestone(ref state);
    state.unlink_child(parent_id, child_id);
}

#[test]
fn test_unlink_child_removes_relationship() {
    let mut state: ComponentState = setup();
    let parent_id = create_default_milestone(ref state);
    let child_id = create_default_milestone(ref state);
    state.link_child(parent_id, child_id);
    state.unlink_child(parent_id, child_id);
    let parent = state.get_milestone(parent_id).unwrap();
    let child = state.get_milestone(child_id).unwrap();
    assert_eq!(parent.children_ids.len(), 0);
    assert_eq!(child.parent_id, 0);
}

#[test]
fn test_unlink_child_replaces_removed_child_with_last_sibling() {
    let mut state: ComponentState = setup();
    let parent_id = create_default_milestone(ref state);
    let first_child_id = create_default_milestone(ref state);
    let last_child_id = create_default_milestone(ref state);
    state.link_child(parent_id, first_child_id);
    state.link_child(parent_id, last_child_id);

    state.unlink_child(parent_id, first_child_id);

    let parent = state.get_milestone(parent_id).unwrap();
    let first_child = state.get_milestone(first_child_id).unwrap();
    let last_child = state.get_milestone(last_child_id).unwrap();
    assert_eq!(parent.children_ids.len(), 1);
    assert_eq!(*parent.children_ids.at(0), last_child_id);
    assert_eq!(first_child.parent_id, 0);
    assert_eq!(last_child.parent_id, parent_id);
}

#[test]
fn test_unlink_last_child_preserves_earlier_sibling() {
    let mut state: ComponentState = setup();
    let parent_id = create_default_milestone(ref state);
    let first_child_id = create_default_milestone(ref state);
    let last_child_id = create_default_milestone(ref state);
    state.link_child(parent_id, first_child_id);
    state.link_child(parent_id, last_child_id);

    state.unlink_child(parent_id, last_child_id);

    let parent = state.get_milestone(parent_id).unwrap();
    let last_child = state.get_milestone(last_child_id).unwrap();
    assert_eq!(parent.children_ids.len(), 1);
    assert_eq!(*parent.children_ids.at(0), first_child_id);
    assert_eq!(last_child.parent_id, 0);
}

#[test]
fn test_unlink_child_emits_event() {
    let mut state: ComponentState = setup();
    let parent_id = create_default_milestone(ref state);
    let child_id = create_default_milestone(ref state);
    state.link_child(parent_id, child_id);
    let mut spy = spy_events();
    let expected_event = MilestonesComponent::Event::MilestoneChildUnlinked(
        MilestonesComponent::MilestoneChildUnlinked { parent_id, child_id },
    );
    state.unlink_child(parent_id, child_id);
    spy.assert_emitted(@array![(test_address(), expected_event)]);
}

#[test]
#[should_panic(expected: "Milestone does not exist")]
fn test_complete_panics_if_not_exists() {
    let mut state: ComponentState = setup();
    state.complete(999);
}

#[test]
#[should_panic(expected: "Milestone is already completed")]
fn test_complete_panics_if_already_completed() {
    let mut state: ComponentState = setup();
    let id = create_default_milestone(ref state);
    state.complete(id);
    state.complete(id);
}

#[test]
#[should_panic(expected: "Cannot complete milestone with incomplete children")]
fn test_complete_panics_if_incomplete_children() {
    let mut state: ComponentState = setup();
    let parent_id = create_default_milestone(ref state);
    let child_id = create_default_milestone(ref state);
    state.link_child(parent_id, child_id);
    state.complete(parent_id);
}

#[test]
#[should_panic(expected: "Cannot complete milestone past its deadline")]
fn test_complete_panics_if_past_deadline() {
    let mut state: ComponentState = setup();
    let id = state
        .create(
            MilestoneMetadata {
                title: "Test Milestone",
                description: "This is a test milestone",
                deadline: get_block_timestamp() + 100,
                payment: 100,
                recipient: 'recipient'.try_into().unwrap(),
            },
        );
    start_cheat_block_timestamp_global(get_block_timestamp() + 101);
    state.complete(id);
}

#[test]
fn test_complete_sets_completed_flag() {
    let mut state: ComponentState = setup();
    let id = create_default_milestone(ref state);
    state.complete(id);
    assert_eq!(state.get_milestone(id).unwrap().completed, true);
}

#[test]
fn test_complete_emits_event() {
    let mut state: ComponentState = setup();
    let id = create_default_milestone(ref state);
    let mut spy = spy_events();
    let expected_event = MilestonesComponent::Event::MilestoneCompleted(
        MilestonesComponent::MilestoneCompleted { id },
    );
    state.complete(id);
    spy.assert_emitted(@array![(test_address(), expected_event)]);
}

#[test]
#[should_panic(expected: "Milestone does not exist")]
fn test_delete_panics_if_not_exists() {
    let mut state: ComponentState = setup();
    state.delete(999);
}

#[test]
#[should_panic(expected: "Cannot delete completed milestone")]
fn test_delete_panics_if_completed() {
    let mut state: ComponentState = setup();
    let id = create_default_milestone(ref state);
    state.complete(id);
    state.delete(id);
}

#[test]
#[should_panic(expected: "Cannot delete milestone with completed children")]
fn test_delete_panics_if_has_completed_child() {
    let mut state: ComponentState = setup();
    let parent_id = create_default_milestone(ref state);
    let child_id = create_default_milestone(ref state);
    state.link_child(parent_id, child_id);
    state.complete(child_id);
    state.delete(parent_id);
}

#[test]
fn test_delete_clears_milestone() {
    let mut state: ComponentState = setup();
    let id = create_default_milestone(ref state);
    state.delete(id);
    assert_eq!(state.get_milestone(id).is_none(), true);
}

#[test]
fn test_delete_unlinks_from_parent() {
    let mut state: ComponentState = setup();
    let parent_id = create_default_milestone(ref state);
    let child_id = create_default_milestone(ref state);
    state.link_child(parent_id, child_id);
    state.delete(child_id);
    let parent = state.get_milestone(parent_id).unwrap();
    assert_eq!(parent.children_ids.len(), 0);
}

#[test]
fn test_delete_unlinks_children() {
    let mut state: ComponentState = setup();
    let parent_id = create_default_milestone(ref state);
    let child_id = create_default_milestone(ref state);
    state.link_child(parent_id, child_id);
    state.delete(parent_id);
    let child = state.get_milestone(child_id).unwrap();
    assert_eq!(child.parent_id, 0);
}

#[test]
fn test_delete_emits_event() {
    let mut state: ComponentState = setup();
    let id = create_default_milestone(ref state);
    let mut spy = spy_events();
    let expected_event = MilestonesComponent::Event::MilestoneDeleted(
        MilestonesComponent::MilestoneDeleted { id },
    );
    state.delete(id);
    spy.assert_emitted(@array![(test_address(), expected_event)]);
}
