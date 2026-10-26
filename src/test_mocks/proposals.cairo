#[starknet::contract]
pub mod MockProposalsContract {
    use paxmata::components::proposals::ProposalsComponent;

    component!(path: ProposalsComponent, storage: proposals, event: ProposalsEvent);

    #[abi(embed_v0)]
    impl ProposalsImpl = ProposalsComponent::ProposalsImpl<ContractState>;
    impl InternalImpl = ProposalsComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        proposals: ProposalsComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ProposalsEvent: ProposalsComponent::Event,
    }
}
