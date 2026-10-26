#[starknet::contract]
pub mod MockAccessContract {
    use paxmata::components::access::AccessComponent;

    component!(path: AccessComponent, storage: access, event: AccessEvent);

    #[abi(embed_v0)]
    impl AccessImpl = AccessComponent::AccessImpl<ContractState>;
    impl InternalImpl = AccessComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        pub access: AccessComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        AccessEvent: AccessComponent::Event,
    }
}
