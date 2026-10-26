use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::{OffchainMessageHash, SNIP12Metadata, StructHash};
use starknet::{ClassHash, ContractAddress};

const CREATE_PROJECT_TYPE_HASH: felt252 =
    0x1152b003d48a804fd93b444b0306aefe28232ae8f0c48d3ee8a55b41b602645;

#[derive(Copy, Drop, Hash)]
pub struct CreateProjectMessage {
    pub creator: ContractAddress,
    pub nonce: felt252,
    pub expiry: u64,
}

pub impl StructHashImpl of StructHash<CreateProjectMessage> {
    fn hash_struct(self: @CreateProjectMessage) -> felt252 {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(CREATE_PROJECT_TYPE_HASH).update_with(*self).finalize()
    }
}

#[starknet::interface]
pub trait IPaxmataFactory<TState> {
    fn create_project(
        ref self: TState, nonce: felt252, expiry: u64, signature: Array<felt252>,
    ) -> u256;

    // Only owner write
    fn set_default_token(ref self: TState, new_default_token: ContractAddress);
    fn set_signer(ref self: TState, new_signer: ContractAddress);
    fn set_treasury(ref self: TState, new_treasury: ContractAddress);
    fn set_engagement_fee(ref self: TState, new_fee: u256);
    fn set_donation_fee_bps(ref self: TState, new_fee_bps: u16);
    fn set_completion_bonus_bps(ref self: TState, new_bonus_bps: u16);
    fn set_project_class_hash(ref self: TState, new_class_hash: ClassHash);

    // View functions
    fn default_token(self: @TState) -> ContractAddress;
    fn signer(self: @TState) -> ContractAddress;
    fn treasury(self: @TState) -> ContractAddress;
    fn engagement_fee(self: @TState) -> u256;
    fn donation_fee_bps(self: @TState) -> u16;
    fn completion_bonus_bps(self: @TState) -> u16;
    fn project_class_hash(self: @TState) -> ClassHash;
    fn total_projects(self: @TState) -> u256;
    fn get_project_contract(self: @TState, project_id: u256) -> ContractAddress;
}

#[starknet::contract]
pub mod PaxmataFactory {
    use core::num::traits::Zero;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::interfaces::accounts::{ISRC6Dispatcher, ISRC6DispatcherTrait};
    use openzeppelin::utils::cryptography::nonces::NoncesComponent;
    use openzeppelin::utils::serde::SerializedAppend;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::syscalls::deploy_syscall;
    use starknet::{
        SyscallResultTrait, get_block_timestamp, get_caller_address, get_contract_address,
    };
    use super::*;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    component!(path: NoncesComponent, storage: nonces, event: NoncesEvent);
    #[abi(embed_v0)]
    impl NoncesImpl = NoncesComponent::NoncesImpl<ContractState>;
    impl NoncesInternalImpl = NoncesComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        default_token: ContractAddress,
        signer: ContractAddress,
        treasury: ContractAddress,
        engagement_fee: u256,
        donation_fee_bps: u16,
        completion_bonus_bps: u16,
        project_class_hash: ClassHash,
        total_projects: u256,
        project_contracts: Map<u256, ContractAddress>,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        nonces: NoncesComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        ProjectCreated: ProjectCreated,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        NoncesEvent: NoncesComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ProjectCreated {
        #[key]
        pub project_id: u256,
        #[key]
        pub owner: ContractAddress,
        #[key]
        pub project_contract: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        default_token: ContractAddress,
        signer: ContractAddress,
        treasury: ContractAddress,
        engagement_fee: u256,
        donation_fee_bps: u16,
        completion_bonus_bps: u16,
        project_class_hash: ClassHash,
    ) {
        assert!(!default_token.is_zero(), "Default token cannot be zero address");
        assert!(!signer.is_zero(), "Signer cannot be zero address");
        assert!(!treasury.is_zero(), "Treasury cannot be zero address");
        assert!(donation_fee_bps <= 1000, "Donation fee exceeds 10%");
        assert!(completion_bonus_bps <= 1000, "Completion bonus exceeds 10%");
        assert!(!project_class_hash.is_zero(), "Project class hash cannot be zero");
        self.ownable.initializer(owner);
        self.default_token.write(default_token);
        self.signer.write(signer);
        self.treasury.write(treasury);
        self.engagement_fee.write(engagement_fee);
        self.donation_fee_bps.write(donation_fee_bps);
        self.completion_bonus_bps.write(completion_bonus_bps);
        self.project_class_hash.write(project_class_hash);
    }

    // Required for hash computation.
    pub impl SNIP12MetadataImpl of SNIP12Metadata {
        fn name() -> felt252 {
            'PaxmataFactory'
        }
        fn version() -> felt252 {
            'v1'
        }
    }

    #[abi(embed_v0)]
    impl PaxmataFactoryImpl of IPaxmataFactory<ContractState> {
        fn create_project(
            ref self: ContractState, nonce: felt252, expiry: u64, signature: Array<felt252>,
        ) -> u256 {
            let creator = get_caller_address();
            self.nonces.use_checked_nonce(creator, nonce);
            self.assert_valid_signature(creator, nonce, expiry, signature);

            let total_projects = self.total_projects.read();
            let project_id = total_projects + 1;
            self.total_projects.write(project_id);
            let project_class_hash = self.project_class_hash.read();
            let salt: felt252 = project_id.try_into().expect('Salt too large');

            let mut project_contract_calldata = array![];
            project_contract_calldata.append_serde(get_contract_address());
            project_contract_calldata.append_serde(creator);
            project_contract_calldata.append_serde(self.default_token.read());
            project_contract_calldata.append_serde(self.engagement_fee.read());
            project_contract_calldata.append_serde(self.donation_fee_bps.read());
            project_contract_calldata.append_serde(self.completion_bonus_bps.read());
            let (project_address, _return_data) = deploy_syscall(
                project_class_hash, salt, project_contract_calldata.span(), false,
            )
                .unwrap_syscall();

            self.project_contracts.entry(project_id).write(project_address);

            let project_created_event = ProjectCreated {
                project_id: project_id, owner: creator, project_contract: project_address,
            };

            self.emit(project_created_event);

            project_id
        }

        // Only owner write
        fn set_default_token(ref self: ContractState, new_default_token: ContractAddress) {
            self.ownable.assert_only_owner();
            assert!(!new_default_token.is_zero(), "Default token cannot be zero address");
            self.default_token.write(new_default_token);
        }

        fn set_signer(ref self: ContractState, new_signer: ContractAddress) {
            self.ownable.assert_only_owner();
            assert!(!new_signer.is_zero(), "Signer cannot be zero address");
            self.signer.write(new_signer);
        }

        fn set_treasury(ref self: ContractState, new_treasury: ContractAddress) {
            self.ownable.assert_only_owner();
            assert!(!new_treasury.is_zero(), "Treasury cannot be zero address");
            self.treasury.write(new_treasury);
        }

        fn set_engagement_fee(ref self: ContractState, new_fee: u256) {
            self.ownable.assert_only_owner();
            self.engagement_fee.write(new_fee);
        }

        fn set_donation_fee_bps(ref self: ContractState, new_fee_bps: u16) {
            self.ownable.assert_only_owner();
            assert!(new_fee_bps <= 1000, "Donation fee exceeds 10%");
            self.donation_fee_bps.write(new_fee_bps);
        }

        fn set_completion_bonus_bps(ref self: ContractState, new_bonus_bps: u16) {
            self.ownable.assert_only_owner();
            assert!(new_bonus_bps <= 1000, "Completion bonus exceeds 10%");
            self.completion_bonus_bps.write(new_bonus_bps);
        }

        fn set_project_class_hash(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            assert!(!new_class_hash.is_zero(), "Project class hash cannot be zero");
            self.project_class_hash.write(new_class_hash);
        }


        // View functions
        fn default_token(self: @ContractState) -> ContractAddress {
            self.default_token.read()
        }

        fn signer(self: @ContractState) -> ContractAddress {
            self.signer.read()
        }

        fn treasury(self: @ContractState) -> ContractAddress {
            self.treasury.read()
        }

        fn engagement_fee(self: @ContractState) -> u256 {
            self.engagement_fee.read()
        }

        fn donation_fee_bps(self: @ContractState) -> u16 {
            self.donation_fee_bps.read()
        }

        fn completion_bonus_bps(self: @ContractState) -> u16 {
            self.completion_bonus_bps.read()
        }

        fn project_class_hash(self: @ContractState) -> ClassHash {
            self.project_class_hash.read()
        }

        fn total_projects(self: @ContractState) -> u256 {
            self.total_projects.read()
        }

        fn get_project_contract(self: @ContractState, project_id: u256) -> ContractAddress {
            self.project_contracts.entry(project_id).read()
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn assert_valid_signature(
            self: @ContractState,
            creator: ContractAddress,
            nonce: felt252,
            expiry: u64,
            signature: Array<felt252>,
        ) {
            let block_timestamp = get_block_timestamp();
            assert!(expiry > block_timestamp, "Signature has expired");

            let signer = ISRC6Dispatcher { contract_address: self.signer.read() };
            let message = CreateProjectMessage { creator, nonce, expiry };
            let hash = message.get_message_hash(signer.contract_address);
            let is_valid_signature_felt = signer.is_valid_signature(hash, signature);
            // Check either 'VALID' or true for backwards compatibility
            let is_valid_signature = is_valid_signature_felt == starknet::VALIDATED
                || is_valid_signature_felt == 1;
            assert!(is_valid_signature, "Invalid signature");
        }
    }

    #[cfg(test)]
    mod constructor_tests {
        use starknet::{ClassHash, ContractAddress};
        use super::{constructor, contract_state_for_testing};

        fn address(value: felt252) -> ContractAddress {
            value.try_into().unwrap()
        }

        fn class_hash() -> ClassHash {
            1.try_into().unwrap()
        }

        #[test]
        #[should_panic(expected: "Default token cannot be zero address")]
        fn test_constructor_panics_if_default_token_is_zero() {
            let mut state = contract_state_for_testing();
            constructor(
                ref state,
                address('owner'),
                address(0),
                address('signer'),
                address('treasury'),
                100,
                300,
                100,
                class_hash(),
            );
        }

        #[test]
        #[should_panic(expected: "Signer cannot be zero address")]
        fn test_constructor_panics_if_signer_is_zero() {
            let mut state = contract_state_for_testing();
            constructor(
                ref state,
                address('owner'),
                address('token'),
                address(0),
                address('treasury'),
                100,
                300,
                100,
                class_hash(),
            );
        }

        #[test]
        #[should_panic(expected: "Treasury cannot be zero address")]
        fn test_constructor_panics_if_treasury_is_zero() {
            let mut state = contract_state_for_testing();
            constructor(
                ref state,
                address('owner'),
                address('token'),
                address('signer'),
                address(0),
                100,
                300,
                100,
                class_hash(),
            );
        }

        #[test]
        #[should_panic(expected: "Donation fee exceeds 10%")]
        fn test_constructor_panics_if_donation_fee_exceeds_max() {
            let mut state = contract_state_for_testing();
            constructor(
                ref state,
                address('owner'),
                address('token'),
                address('signer'),
                address('treasury'),
                100,
                1001,
                100,
                class_hash(),
            );
        }

        #[test]
        #[should_panic(expected: "Completion bonus exceeds 10%")]
        fn test_constructor_panics_if_completion_bonus_exceeds_max() {
            let mut state = contract_state_for_testing();
            constructor(
                ref state,
                address('owner'),
                address('token'),
                address('signer'),
                address('treasury'),
                100,
                300,
                1001,
                class_hash(),
            );
        }

        #[test]
        #[should_panic(expected: "Project class hash cannot be zero")]
        fn test_constructor_panics_if_project_class_hash_is_zero() {
            let mut state = contract_state_for_testing();
            constructor(
                ref state,
                address('owner'),
                address('token'),
                address('signer'),
                address('treasury'),
                100,
                300,
                100,
                0.try_into().unwrap(),
            );
        }
    }
}
