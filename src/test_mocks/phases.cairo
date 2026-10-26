#[starknet::contract]
pub mod MockPhasesContract {
    use paxmata::components::phases::PhasesComponent;

    component!(path: PhasesComponent, storage: phases, event: PhasesEvent);

    #[abi(embed_v0)]
    impl PhasesImpl = PhasesComponent::PhasesImpl<ContractState>;
    impl InternalImpl = PhasesComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        phases: PhasesComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        PhasesEvent: PhasesComponent::Event,
    }
}
