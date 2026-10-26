#[starknet::contract]
pub mod MockEscrowContract {
    use paxmata::components::escrow::EscrowComponent;

    component!(path: EscrowComponent, storage: escrow, event: EscrowEvent);

    #[abi(embed_v0)]
    impl EscrowImpl = EscrowComponent::EscrowImpl<ContractState>;
    impl InternalImpl = EscrowComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        pub escrow: EscrowComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        EscrowEvent: EscrowComponent::Event,
    }
}
