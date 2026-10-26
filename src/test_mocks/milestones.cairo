#[starknet::contract]
pub mod MockMilestonesContract {
    use paxmata::components::milestones::MilestonesComponent;

    component!(path: MilestonesComponent, storage: milestones, event: MilestonesEvent);

    #[abi(embed_v0)]
    impl MilestonesImpl = MilestonesComponent::MilestonesImpl<ContractState>;
    impl InternalImpl = MilestonesComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        milestones: MilestonesComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        MilestonesEvent: MilestonesComponent::Event,
    }
}
