use starknet::ContractAddress;

#[starknet::interface]
pub trait IMessageTransmitter<TState> {
    fn receive_message(
        ref self: TState,
        message: ByteArray,
        attestation: ByteArray,
    ) -> bool;
}

#[starknet::interface]
pub trait IDonationProject<TState> {
    fn donate(ref self: TState, amount: u128, donor: ContractAddress);
    fn factory(self: @TState) -> ContractAddress;
}

#[starknet::interface]
pub trait IProjectFactory<TState> {
    fn get_project_contract(self: @TState, project_id: u256) -> ContractAddress;
}

#[starknet::contract]
pub mod DonationReceiver {
    use core::byte_array::ByteArrayTrait;
    use core::num::traits::Zero;
    use openzeppelin::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::{
        ContractAddress,
        get_block_timestamp,
        get_contract_address,
        storage::{
            Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
        },
    };
    use super::{
        IDonationProjectDispatcher,
        IDonationProjectDispatcherTrait,
        IMessageTransmitterDispatcher,
        IMessageTransmitterDispatcherTrait,
        IProjectFactoryDispatcher,
        IProjectFactoryDispatcherTrait,
    };

    const MESSAGE_BODY_OFFSET: u32 = 148;
    const HOOK_OFFSET_IN_BODY: u32 = 228;
    const HOOK_OFFSET: u32 = MESSAGE_BODY_OFFSET + HOOK_OFFSET_IN_BODY;
    const HOOK_LENGTH: u32 = 288;

    #[storage]
    struct Storage {
        message_transmitter: ContractAddress,
        token_messenger_minter: ContractAddress,
        usdc: ContractAddress,
        factory: ContractAddress,
        base_usdc: u256,
        base_token_messenger: u256,
        base_executor: u256,
        source_domain: u32,
        destination_domain: u32,
        version: u32,
        consumed_intents: Map<u256, bool>,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        message_transmitter: ContractAddress,
        token_messenger_minter: ContractAddress,
        usdc: ContractAddress,
        factory: ContractAddress,
        base_usdc: u256,
        base_token_messenger: u256,
        base_executor: u256,
        source_domain: u32,
        destination_domain: u32,
        version: u32,
    ) {
        assert!(!message_transmitter.is_zero(), "Invalid transmitter");
        assert!(!token_messenger_minter.is_zero(), "Invalid token messenger");
        assert!(!usdc.is_zero(), "Invalid USDC");
        assert!(!factory.is_zero(), "Invalid factory");
        assert!(base_usdc != 0, "Invalid Base USDC");
        assert!(base_token_messenger != 0, "Invalid Base messenger");
        assert!(base_executor != 0, "Invalid Base executor");
        assert!(version > 0, "Invalid receiver version");
        self.message_transmitter.write(message_transmitter);
        self.token_messenger_minter.write(token_messenger_minter);
        self.usdc.write(usdc);
        self.factory.write(factory);
        self.base_usdc.write(base_usdc);
        self.base_token_messenger.write(base_token_messenger);
        self.base_executor.write(base_executor);
        self.source_domain.write(source_domain);
        self.destination_domain.write(destination_domain);
        self.version.write(version);
    }

    #[external(v0)]
    fn relay_donation(
        ref self: ContractState,
        message: ByteArray,
        attestation: ByteArray,
    ) {
        let hook = self.validate_message_and_hook(@message);
        assert!(get_block_timestamp() <= hook.donation_deadline, "Donation deadline passed");
        assert!(!self.consumed_intents.entry(hook.intent_id).read(), "Intent already consumed");

        let project = IDonationProjectDispatcher { contract_address: hook.project };
        assert!(project.factory() == self.factory.read(), "Project factory mismatch");
        let factory = IProjectFactoryDispatcher { contract_address: self.factory.read() };
        assert!(
            factory.get_project_contract(hook.project_id) == hook.project,
            "Project mapping mismatch",
        );

        let usdc = IERC20Dispatcher { contract_address: self.usdc.read() };
        let balance_before = usdc.balance_of(get_contract_address());
        let accepted = IMessageTransmitterDispatcher {
            contract_address: self.message_transmitter.read(),
        }.receive_message(message, attestation);
        assert!(accepted, "Circle message rejected");
        let balance_after = usdc.balance_of(get_contract_address());
        assert!(balance_after - balance_before == hook.amount, "Mint amount mismatch");

        self.consumed_intents.entry(hook.intent_id).write(true);
        assert!(usdc.approve(hook.project, hook.amount), "USDC approval failed");
        let amount_u128: u128 = hook.amount.try_into().unwrap();
        project.donate(amount_u128, hook.donor);
    }

    #[external(v0)]
    fn recover_donation(
        ref self: ContractState,
        message: ByteArray,
        attestation: ByteArray,
    ) {
        let hook = self.validate_message_and_hook(@message);
        assert!(get_block_timestamp() > hook.donation_deadline, "Recovery not available");
        assert!(!self.consumed_intents.entry(hook.intent_id).read(), "Intent already consumed");

        let usdc = IERC20Dispatcher { contract_address: self.usdc.read() };
        let balance_before = usdc.balance_of(get_contract_address());
        let accepted = IMessageTransmitterDispatcher {
            contract_address: self.message_transmitter.read(),
        }.receive_message(message, attestation);
        assert!(accepted, "Circle message rejected");
        let balance_after = usdc.balance_of(get_contract_address());
        assert!(balance_after - balance_before == hook.amount, "Mint amount mismatch");

        self.consumed_intents.entry(hook.intent_id).write(true);
        assert!(usdc.transfer(hook.donor, hook.amount), "USDC recovery failed");
    }

    #[derive(Drop)]
    struct DonationHook {
        intent_id: u256,
        project_id: u256,
        donor: ContractAddress,
        project: ContractAddress,
        amount: u256,
        donation_deadline: u64,
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn validate_message_and_hook(
            self: @ContractState,
            message: @ByteArray,
        ) -> DonationHook {
            assert!(message.len() == HOOK_OFFSET + HOOK_LENGTH, "Invalid message length");
            assert!(read_u32(message, 4) == self.source_domain.read(), "Source domain mismatch");
            assert!(
                read_u32(message, 8) == self.destination_domain.read(),
                "Destination domain mismatch",
            );
            let self_felt: felt252 = get_contract_address().into();
            let self_address: u256 = self_felt.into();
            assert!(
                read_u256(message, 44) == self.base_token_messenger.read(),
                "Message sender contract mismatch",
            );
            let token_messenger_felt: felt252 = self.token_messenger_minter.read().into();
            assert!(
                read_u256(message, 76) == token_messenger_felt.into(),
                "Message recipient mismatch",
            );
            assert!(read_u256(message, 108) == self_address, "Destination caller mismatch");
            assert!(
                read_u256(message, MESSAGE_BODY_OFFSET + 4) == self.base_usdc.read(),
                "Burn token mismatch",
            );
            assert!(
                read_u256(message, MESSAGE_BODY_OFFSET + 36) == self_address,
                "Mint recipient mismatch",
            );
            assert!(
                read_u256(message, MESSAGE_BODY_OFFSET + 100) == self.base_executor.read(),
                "Message sender mismatch",
            );
            assert!(read_u256(message, MESSAGE_BODY_OFFSET + 132) == 0, "Nonzero max fee");
            assert!(
                read_u32(message, HOOK_OFFSET + 28) == self.version.read(),
                "Hook version mismatch",
            );
            let intent_id = read_u256(message, HOOK_OFFSET + 32);
            let project_id = read_u256(message, HOOK_OFFSET + 128);
            let project_felt: felt252 = read_u256(message, HOOK_OFFSET + 160)
                .try_into()
                .unwrap();
            let donor_felt: felt252 = read_u256(message, HOOK_OFFSET + 96)
                .try_into()
                .unwrap();
            let amount = read_u256(message, HOOK_OFFSET + 192);
            assert!(
                amount == read_u256(message, MESSAGE_BODY_OFFSET + 68),
                "Hook amount mismatch",
            );
            DonationHook {
                intent_id,
                project_id,
                donor: donor_felt.try_into().unwrap(),
                project: project_felt.try_into().unwrap(),
                amount,
                donation_deadline: read_u64(message, HOOK_OFFSET + 248),
            }
        }
    }

    fn read_u32(bytes: @ByteArray, offset: u32) -> u32 {
        let mut value: u32 = 0;
        let mut index: u32 = 0;
        loop {
            if index == 4 {
                break value;
            }
            value = value * 256 + bytes.at(offset + index).unwrap().into();
            index += 1;
        }
    }

    fn read_u64(bytes: @ByteArray, offset: u32) -> u64 {
        let mut value: u64 = 0;
        let mut index: u32 = 0;
        loop {
            if index == 8 {
                break value;
            }
            value = value * 256 + bytes.at(offset + index).unwrap().into();
            index += 1;
        }
    }

    fn read_u256(bytes: @ByteArray, offset: u32) -> u256 {
        let mut value: u256 = 0;
        let mut index: u32 = 0;
        loop {
            if index == 32 {
                break value;
            }
            value = value * 256 + bytes.at(offset + index).unwrap().into();
            index += 1;
        }
    }
}
