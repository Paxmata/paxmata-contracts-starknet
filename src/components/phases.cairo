use core::fmt::{Display, Error, Formatter};

#[derive(Serde, Drop, Debug, Clone, PartialEq, starknet::Store)]
pub enum Phase {
    #[default]
    Quoting,
    Fundraising,
    Development,
    ProposalPending,
    Closed,
}

impl PhaseDisplay of Display<Phase> {
    fn fmt(self: @Phase, ref f: Formatter) -> Result<(), Error> {
        match self {
            Phase::Quoting => f.buffer.append(@"Quoting"),
            Phase::Fundraising => f.buffer.append(@"Fundraising"),
            Phase::Development => f.buffer.append(@"Development"),
            Phase::ProposalPending => f.buffer.append(@"ProposalPending"),
            Phase::Closed => f.buffer.append(@"Closed"),
        }
        Ok(())
    }
}

#[starknet::interface]
pub trait IPhases<TContractState> {
    fn current_phase(self: @TContractState) -> Phase;
}

#[starknet::component]
pub mod PhasesComponent {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use super::Phase;

    #[storage]
    pub struct Storage {
        Phases_phase: Phase,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        PhaseChanged: PhaseChanged,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PhaseChanged {
        pub old_phase: Phase,
        pub new_phase: Phase,
    }

    #[embeddable_as(PhasesImpl)]
    impl Phases<
        TContractState, +HasComponent<TContractState>,
    > of super::IPhases<ComponentState<TContractState>> {
        fn current_phase(self: @ComponentState<TContractState>) -> Phase {
            self.Phases_phase.read()
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        fn change_phase(ref self: ComponentState<TContractState>, new_phase: Phase) {
            let old_phase = self.Phases_phase.read();
            if (old_phase == new_phase) {
                return;
            }
            self.Phases_phase.write(new_phase.clone());
            self.emit(PhaseChanged { old_phase, new_phase });
        }

        fn assert_current_phase(ref self: ComponentState<TContractState>, expected_phase: Phase) {
            let current_phase = self.Phases_phase.read();
            assert!(
                current_phase == expected_phase,
                "Expected phase: {}, but current phase is: {}",
                expected_phase,
                current_phase,
            );
        }
    }
}
