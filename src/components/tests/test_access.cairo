use AccessComponent::InternalTrait;
use paxmata::components::access::{AccessComponent, IAccess};
use paxmata::test_mocks::access::MockAccessContract;
use snforge_std::{EventSpyAssertionsTrait, spy_events, start_cheat_caller_address, test_address};

type ComponentState = AccessComponent::ComponentState<MockAccessContract::ContractState>;

fn setup() -> ComponentState {
    AccessComponent::component_state_for_testing()
}

#[test]
#[should_panic(expected: "Access component is already initialized")]
fn test_initialize_panics_on_reinitialization() {
    let mut state = setup();
    let owner = 'owner'.try_into().unwrap();
    state.initialize(owner);
    state.initialize(owner);
}

#[test]
#[should_panic(expected: "Owner address cannot be zero address")]
fn test_initialize_panics_on_zero_owner_address() {
    let mut state = setup();
    let owner = 0.try_into().unwrap();
    state.initialize(owner);
}

#[test]
fn test_initialize_sets_owner() {
    let mut state = setup();
    let owner = 'owner'.try_into().unwrap();
    state.initialize(owner);
    assert_eq!(state.owner(), owner);
}

#[test]
fn test_initialize_developer_is_zero_after_init() {
    let mut state = setup();
    let owner = 'owner'.try_into().unwrap();
    state.initialize(owner);
    let zero: starknet::ContractAddress = 0.try_into().unwrap();
    assert_eq!(state.developer(), zero);
}

#[test]
fn test_initialize_emits_owner_set_event() {
    let mut state = setup();
    let owner = 'owner'.try_into().unwrap();
    let mut spy = spy_events();
    state.initialize(owner);
    let expected_event = AccessComponent::Event::OwnerSet(AccessComponent::OwnerSet { owner });
    spy.assert_emitted(@array![(test_address(), expected_event)]);
}

fn setup_initialized() -> ComponentState {
    let mut state = setup();
    let owner = 'owner'.try_into().unwrap();
    state.initialize(owner);
    state
}

#[test]
#[should_panic(expected: "Access component is not initialized")]
fn test_set_developer_panics_if_not_initialized() {
    let mut state = setup();
    let developer = 'developer'.try_into().unwrap();
    state.set_developer(developer);
}

#[test]
#[should_panic(expected: "Developer address cannot be zero address")]
fn test_set_developer_panics_if_developer_is_zero() {
    let mut state = setup_initialized();
    let owner = 'owner'.try_into().unwrap();
    start_cheat_caller_address(test_address(), owner);
    let developer = 0.try_into().unwrap();
    state.set_developer(developer);
}

#[test]
#[should_panic(expected: "Caller is not the owner")]
fn test_set_developer_panics_if_caller_is_not_owner() {
    let mut state = setup_initialized();
    let not_owner = 'not_owner'.try_into().unwrap();
    start_cheat_caller_address(test_address(), not_owner);
    let developer = 'developer'.try_into().unwrap();
    state.set_developer(developer);
}

#[test]
#[should_panic(expected: "Developer is already set")]
fn test_set_developer_panics_if_developer_already_set() {
    let mut state = setup_initialized();
    let owner = 'owner'.try_into().unwrap();
    start_cheat_caller_address(test_address(), owner);
    let developer = 'developer'.try_into().unwrap();
    state.set_developer(developer);
    state.set_developer(developer);
}

#[test]
fn test_set_developer_sets_developer() {
    let mut state = setup_initialized();
    let owner = 'owner'.try_into().unwrap();
    start_cheat_caller_address(test_address(), owner);
    let developer = 'developer'.try_into().unwrap();
    state.set_developer(developer);
    assert_eq!(state.developer(), developer);
}

#[test]
fn test_set_developer_emits_developer_set_event() {
    let mut state = setup_initialized();
    let owner = 'owner'.try_into().unwrap();
    start_cheat_caller_address(test_address(), owner);
    let developer = 'developer'.try_into().unwrap();
    let mut spy = spy_events();
    state.set_developer(developer);
    let expected_event = AccessComponent::Event::DeveloperSet(
        AccessComponent::DeveloperSet { developer },
    );
    spy.assert_emitted(@array![(test_address(), expected_event)]);
}

#[test]
#[should_panic(expected: "Caller is not the owner")]
fn test_assert_only_owner_panics_if_not_owner() {
    let state = setup_initialized();
    let not_owner = 'not_owner'.try_into().unwrap();
    start_cheat_caller_address(test_address(), not_owner);
    state.assert_only_owner();
}

#[test]
fn test_assert_only_owner_passes_if_owner() {
    let state = setup_initialized();
    let owner = 'owner'.try_into().unwrap();
    start_cheat_caller_address(test_address(), owner);
    state.assert_only_owner();
}

#[test]
#[should_panic(expected: "Developer is not set")]
fn test_assert_only_developer_panics_if_developer_not_set() {
    let state = setup_initialized();
    state.assert_only_developer();
}

#[test]
#[should_panic(expected: "Caller is not the developer")]
fn test_assert_only_developer_panics_if_caller_not_developer() {
    let mut state = setup_initialized();
    let owner = 'owner'.try_into().unwrap();
    start_cheat_caller_address(test_address(), owner);
    let developer = 'developer'.try_into().unwrap();
    state.set_developer(developer);
    let not_developer = 'not_developer'.try_into().unwrap();
    start_cheat_caller_address(test_address(), not_developer);
    state.assert_only_developer();
}

#[test]
fn test_assert_only_developer_passes_if_developer() {
    let mut state = setup_initialized();
    let owner = 'owner'.try_into().unwrap();
    start_cheat_caller_address(test_address(), owner);
    let developer = 'developer'.try_into().unwrap();
    state.set_developer(developer);
    start_cheat_caller_address(test_address(), developer);
    state.assert_only_developer();
}

fn setup_with_developer() -> ComponentState {
    let mut state = setup_initialized();
    let owner = 'owner'.try_into().unwrap();
    start_cheat_caller_address(test_address(), owner);
    let developer = 'developer'.try_into().unwrap();
    state.set_developer(developer);
    state
}

#[test]
#[should_panic(expected: "Developer is not set")]
fn test_assert_only_owner_or_developer_panics_if_developer_not_set() {
    let state = setup_initialized();
    state.assert_only_owner_or_developer();
}

#[test]
#[should_panic(expected: "Caller is not the owner or developer")]
fn test_assert_only_owner_or_developer_panics_if_neither() {
    let state = setup_with_developer();
    let neither = 'neither'.try_into().unwrap();
    start_cheat_caller_address(test_address(), neither);
    state.assert_only_owner_or_developer();
}

#[test]
fn test_assert_only_owner_or_developer_passes_if_owner() {
    let state = setup_with_developer();
    let owner = 'owner'.try_into().unwrap();
    start_cheat_caller_address(test_address(), owner);
    state.assert_only_owner_or_developer();
}

#[test]
fn test_assert_only_owner_or_developer_passes_if_developer() {
    let state = setup_with_developer();
    let developer = 'developer'.try_into().unwrap();
    start_cheat_caller_address(test_address(), developer);
    state.assert_only_owner_or_developer();
}
