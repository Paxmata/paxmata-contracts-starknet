use openzeppelin::interfaces::accounts::{ISRC6Dispatcher};
use openzeppelin::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin::utils::serde::SerializedAppend;
use paxmata::factory::IPaxmataFactoryDispatcher;
use paxmata::project::IPaxmataProjectDispatcher;
use snforge_std::signature::stark_curve::{StarkCurveKeyPairImpl, StarkCurveSignerImpl};
use snforge_std::signature::{KeyPairTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::{ClassHash, ContractAddress, SyscallResultTrait};

pub fn addr(name: felt252) -> ContractAddress {
    name.try_into().unwrap()
}

pub fn deploy_signer_account(private_key: felt252) -> ISRC6Dispatcher {
    let key_pair = KeyPairTrait::from_secret_key(private_key);
    let class = declare("AccountUpgradeable").unwrap_syscall().contract_class();
    let mut calldata = array![];
    calldata.append_serde(key_pair.public_key);
    let (contract_address, _) = class.deploy(@calldata).unwrap_syscall();
    ISRC6Dispatcher { contract_address }
}

pub fn deploy_token(
    name: ByteArray, symbol: ByteArray, supply: u256, recipient: ContractAddress,
) -> IERC20Dispatcher {
    let class = declare("ERC20Upgradeable").unwrap_syscall().contract_class();
    let mut calldata = array![];
    calldata.append_serde(name);
    calldata.append_serde(symbol);
    calldata.append_serde(supply);
    calldata.append_serde(recipient);
    calldata.append_serde(recipient);

    let (contract_address, _) = class.deploy(@calldata).unwrap_syscall();
    IERC20Dispatcher { contract_address }
}

pub fn deploy_factory(
    owner: ContractAddress,
    default_token: ContractAddress,
    signer: ContractAddress,
    treasury: ContractAddress,
    engagement_fee: u256,
    donation_fee_bps: u16,
    completion_bonus_bps: u16,
    project_class_hash: ClassHash,
) -> IPaxmataFactoryDispatcher {
    let class = declare("PaxmataFactory").unwrap_syscall().contract_class();
    let mut calldata = array![];
    calldata.append_serde(owner);
    calldata.append_serde(default_token);
    calldata.append_serde(signer);
    calldata.append_serde(treasury);
    calldata.append_serde(engagement_fee);
    calldata.append_serde(donation_fee_bps);
    calldata.append_serde(completion_bonus_bps);
    calldata.append_serde(project_class_hash);
    let (contract_address, _) = class.deploy(@calldata).unwrap_syscall();
    IPaxmataFactoryDispatcher { contract_address }
}

pub fn deploy_project(
    factory: ContractAddress,
    owner: ContractAddress,
    token: ContractAddress,
    treasury: ContractAddress,
    engagement_fee: u256,
    donation_fee_bps: u16,
    completion_bonus_bps: u16,
) -> IPaxmataProjectDispatcher {
    let class = declare("PaxmataProject").unwrap_syscall().contract_class();
    let mut calldata = array![];
    calldata.append_serde(factory);
    calldata.append_serde(owner);
    calldata.append_serde(token);
    calldata.append_serde(engagement_fee);
    calldata.append_serde(donation_fee_bps);
    calldata.append_serde(completion_bonus_bps);

    let (contract_address, _) = class.deploy(@calldata).unwrap_syscall();
    IPaxmataProjectDispatcher { contract_address }
}

pub fn transfer_tokens(
    token: IERC20Dispatcher, from: ContractAddress, to: ContractAddress, amount: u256,
) {
    start_cheat_caller_address(token.contract_address, from);
    token.transfer(to, amount);
    stop_cheat_caller_address(token.contract_address);
}

pub fn approve_tokens(
    token: IERC20Dispatcher, owner: ContractAddress, spender: ContractAddress, amount: u256,
) {
    start_cheat_caller_address(token.contract_address, owner);
    token.approve(spender, amount);
    stop_cheat_caller_address(token.contract_address);
}