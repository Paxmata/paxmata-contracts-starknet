use PhasesComponent::InternalTrait;
use paxmata::components::phases::{IPhases, Phase, PhasesComponent};
use paxmata::test_mocks::phases::MockPhasesContract;
use snforge_std::{EventSpyAssertionsTrait, spy_events, test_address};

type ComponentState = PhasesComponent::ComponentState<MockPhasesContract::ContractState>;

fn setup() -> ComponentState {
    PhasesComponent::component_state_for_testing()
}

#[test]
fn test_initial() {
    let mut state: ComponentState = setup();
    assert_eq!(state.current_phase(), Phase::Quoting);
}

#[test]
fn test_change_phase_transitions() {
    let mut state: ComponentState = setup();

    // Transition to Fundraising
    state.change_phase(Phase::Fundraising);
    assert_eq!(state.current_phase(), Phase::Fundraising);

    // Transition to Development
    state.change_phase(Phase::Development);
    assert_eq!(state.current_phase(), Phase::Development);

    // Transition to ProposalPending
    state.change_phase(Phase::ProposalPending);
    assert_eq!(state.current_phase(), Phase::ProposalPending);

    // Transition to Closed
    state.change_phase(Phase::Closed);
    assert_eq!(state.current_phase(), Phase::Closed);
}

#[test]
fn test_change_phase_emits_phase_changed_event() {
    let mut state: ComponentState = setup();
    let mut spy = spy_events();
    state.change_phase(Phase::Fundraising);
    let expected_event = PhasesComponent::Event::PhaseChanged(
        PhasesComponent::PhaseChanged { old_phase: Phase::Quoting, new_phase: Phase::Fundraising },
    );
    spy.assert_emitted(@array![(test_address(), expected_event)]);
}

#[test]
fn test_change_phase_to_same_phase_does_not_emit_event() {
    let mut state: ComponentState = setup();
    let mut spy = spy_events();
    state.change_phase(Phase::Quoting); // Change to the same phase
    let unexpected_event = PhasesComponent::Event::PhaseChanged(
        PhasesComponent::PhaseChanged { old_phase: Phase::Quoting, new_phase: Phase::Quoting },
    );
    spy.assert_not_emitted(@array![(test_address(), unexpected_event)]);
}

#[test]
fn test_assert_current_phase_passes_when_phase_matches() {
    let mut state: ComponentState = setup();
    state.assert_current_phase(Phase::Quoting);
    state.change_phase(Phase::Fundraising);
    state.assert_current_phase(Phase::Fundraising);
}

#[test]
#[should_panic(expected: "Expected phase: Fundraising, but current phase is: Quoting")]
fn test_assert_current_phase_panics_when_phase_does_not_match() {
    let mut state: ComponentState = setup();
    state.assert_current_phase(Phase::Fundraising);
}

#[test]
#[should_panic(expected: "Expected phase: Development, but current phase is: Fundraising")]
fn test_assert_current_phase_panics_after_phase_change() {
    let mut state: ComponentState = setup();
    state.change_phase(Phase::Fundraising);
    state.assert_current_phase(Phase::Development);
}

