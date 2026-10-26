use starknet::ContractAddress;

#[starknet::interface]
pub trait IAccess<TContractState> {
    fn owner(self: @TContractState) -> ContractAddress;
    fn developer(self: @TContractState) -> ContractAddress;
}

#[starknet::component]
pub mod AccessComponent {
    use core::num::traits::Zero;
    use starknet::get_caller_address;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use super::*;

    #[storage]
    pub struct Storage {
        Access_owner: ContractAddress,
        Access_developer: ContractAddress,
        Access_initialized: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        OwnerSet: OwnerSet,
        DeveloperSet: DeveloperSet,
    }

    #[derive(Drop, starknet::Event)]
    pub struct OwnerSet {
        #[key]
        pub owner: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct DeveloperSet {
        #[key]
        pub developer: ContractAddress,
    }

    #[embeddable_as(AccessImpl)]
    impl Access<
        TContractState, +HasComponent<TContractState>,
    > of super::IAccess<ComponentState<TContractState>> {
        fn owner(self: @ComponentState<TContractState>) -> ContractAddress {
            self.Access_owner.read()
        }

        fn developer(self: @ComponentState<TContractState>) -> ContractAddress {
            self.Access_developer.read()
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        fn initialize(ref self: ComponentState<TContractState>, owner: ContractAddress) {
            assert!(!self.Access_initialized.read(), "Access component is already initialized");
            assert!(!owner.is_zero(), "Owner address cannot be zero address");
            self.Access_owner.write(owner);
            self.Access_initialized.write(true);
            self.emit(OwnerSet { owner });
        }

        fn set_developer(ref self: ComponentState<TContractState>, developer: ContractAddress) {
            assert!(self.Access_initialized.read(), "Access component is not initialized");
            assert!(!developer.is_zero(), "Developer address cannot be zero address");
            self.assert_only_owner();
            assert!(self.Access_developer.read().is_zero(), "Developer is already set");
            self.Access_developer.write(developer);
            self.emit(DeveloperSet { developer });
        }

        fn assert_only_owner(self: @ComponentState<TContractState>) {
            let caller = get_caller_address();
            assert!(caller == self.Access_owner.read(), "Caller is not the owner");
        }

        fn assert_only_developer(self: @ComponentState<TContractState>) {
            assert!(!self.Access_developer.read().is_zero(), "Developer is not set");
            let caller = get_caller_address();
            assert!(caller == self.Access_developer.read(), "Caller is not the developer");
        }

        fn assert_only_owner_or_developer(self: @ComponentState<TContractState>) {
            let caller = get_caller_address();
            let owner = self.Access_owner.read();
            let developer = self.Access_developer.read();
            assert!(!developer.is_zero(), "Developer is not set");
            assert!(caller == owner || caller == developer, "Caller is not the owner or developer");
        }
    }
}
