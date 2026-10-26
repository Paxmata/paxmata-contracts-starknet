use openzeppelin::interfaces::erc20::IERC20Dispatcher;
use openzeppelin::interfaces::accounts::ISRC6Dispatcher;
use openzeppelin::utils::snip12::OffchainMessageHash;
use paxmata::factory::PaxmataFactory::SNIP12MetadataImpl;
use paxmata::factory::{
    CreateProjectMessage, IPaxmataFactoryDispatcher, IPaxmataFactoryDispatcherTrait, PaxmataFactory,
    StructHashImpl,
};
use paxmata::project::{IPaxmataProjectDispatcher, IPaxmataProjectDispatcherTrait};
use snforge_std::signature::stark_curve::{StarkCurveKeyPairImpl, StarkCurveSignerImpl};
use snforge_std::signature::{KeyPairTrait, SignerTrait};
use snforge_std::{
    DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_block_timestamp_global, start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::{ClassHash, ContractAddress, SyscallResultTrait};
use crate::helpers::{addr, deploy_factory, deploy_signer_account, deploy_token};

const SIGNER_PRIVATE_KEY: felt252 = 0x123456;
const DEFAULT_EXPIRY: u64 = 9999999999;
const DEFAULT_ENGAGEMENT_FEE: u256 = 100_000;
const DEFAULT_DONATION_FEE_BPS: u16 = 300;
const DEFAULT_COMPLETION_BONUS_BPS: u16 = 100;
const DEFAULT_TOKEN_SUPPLY: u256 = 1_000_000;

fn get_create_project_message_hash(
    creator: ContractAddress, nonce: felt252, expiry: u64, signer: ContractAddress,
) -> felt252 {
    let message = CreateProjectMessage { creator, nonce, expiry };
    message.get_message_hash(signer)
}

fn sign_create_project_message(
    creator: ContractAddress, nonce: felt252, expiry: u64, signer: ContractAddress,
) -> Array<felt252> {
    let message_hash = get_create_project_message_hash(creator, nonce, expiry, signer);
    let key_pair = KeyPairTrait::from_secret_key(SIGNER_PRIVATE_KEY);
    let signature = key_pair.sign(message_hash).unwrap();
    let (r, s) = signature;
    array![r, s]
}

fn get_project_class_hash() -> ClassHash {
    *declare("PaxmataProject").unwrap_syscall().contract_class().class_hash
}

// Returns (factory, signer_address, default_token_address)
fn setup() -> (IPaxmataFactoryDispatcher, ISRC6Dispatcher, IERC20Dispatcher) {
    let owner = addr('owner');
    let token = deploy_token("Test Token", "TTK", DEFAULT_TOKEN_SUPPLY, owner);
    let signer = deploy_signer_account(SIGNER_PRIVATE_KEY);
    let project_class_hash = get_project_class_hash();
    let factory = deploy_factory(
        owner,
        token.contract_address,
        signer.contract_address,
        addr('treasury'),
        DEFAULT_ENGAGEMENT_FEE,
        DEFAULT_DONATION_FEE_BPS,
        DEFAULT_COMPLETION_BONUS_BPS,
        project_class_hash,
    );
    (factory, signer, token)
}

#[test]
fn test_initial_state_on_deployment() {
    let (factory, signer, token) = setup();
    let project_class_hash = get_project_class_hash();
    assert_eq!(factory.default_token(), token.contract_address);
    assert_eq!(factory.signer(), signer.contract_address);
    assert_eq!(factory.treasury(), addr('treasury'));
    assert_eq!(factory.engagement_fee(), DEFAULT_ENGAGEMENT_FEE);
    assert_eq!(factory.donation_fee_bps(), DEFAULT_DONATION_FEE_BPS);
    assert_eq!(factory.completion_bonus_bps(), DEFAULT_COMPLETION_BONUS_BPS);
    assert_eq!(factory.project_class_hash(), project_class_hash);
    assert_eq!(factory.total_projects(), 0);
}

#[test]
fn test_constructor_accepts_maximum_fee_rates() {
    let factory = deploy_factory(
        addr('owner'),
        addr('token'),
        addr('signer'),
        addr('treasury'),
        DEFAULT_ENGAGEMENT_FEE,
        1000,
        1000,
        get_project_class_hash(),
    );

    assert_eq!(factory.donation_fee_bps(), 1000);
    assert_eq!(factory.completion_bonus_bps(), 1000);
}

#[test]
fn test_create_project_returns_first_id_as_one() {
    let (factory, signer, _) = setup();
    let creator = addr('creator');
    let signature = sign_create_project_message(creator, 0, DEFAULT_EXPIRY, signer.contract_address);
    start_cheat_caller_address(factory.contract_address, creator);
    let project_id = factory.create_project(0, DEFAULT_EXPIRY, signature);
    stop_cheat_caller_address(factory.contract_address);
    assert_eq!(project_id, 1);
}

#[test]
fn test_create_project_increments_total_projects() {
    let (factory, signer, _) = setup();
    let creator = addr('creator');
    let signature = sign_create_project_message(creator, 0, DEFAULT_EXPIRY, signer.contract_address);
    start_cheat_caller_address(factory.contract_address, creator);
    factory.create_project(0, DEFAULT_EXPIRY, signature);
    stop_cheat_caller_address(factory.contract_address);
    assert_eq!(factory.total_projects(), 1);
}

#[test]
fn test_create_project_stores_non_zero_contract_address() {
    let (factory, signer, _) = setup();
    let creator = addr('creator');
    let signature = sign_create_project_message(creator, 0, DEFAULT_EXPIRY, signer.contract_address);
    start_cheat_caller_address(factory.contract_address, creator);
    let project_id = factory.create_project(0, DEFAULT_EXPIRY, signature);
    stop_cheat_caller_address(factory.contract_address);
    let zero: ContractAddress = 0.try_into().unwrap();
    assert_ne!(factory.get_project_contract(project_id), zero);
}

#[test]
fn test_create_project_emits_project_created_event() {
    let (factory, signer, _) = setup();
    let creator = addr('creator');
    let signature = sign_create_project_message(creator, 0, DEFAULT_EXPIRY, signer.contract_address);
    let mut spy = spy_events();
    start_cheat_caller_address(factory.contract_address, creator);
    let project_id = factory.create_project(0, DEFAULT_EXPIRY, signature);
    stop_cheat_caller_address(factory.contract_address);
    let project_contract = factory.get_project_contract(project_id);
    let expected = PaxmataFactory::Event::ProjectCreated(
        PaxmataFactory::ProjectCreated { project_id, owner: creator, project_contract },
    );
    spy.assert_emitted(@array![(factory.contract_address, expected)]);
}

#[test]
fn test_create_project_deploys_with_correct_settings() {
    let (factory, signer, _) = setup();
    let creator = addr('creator');
    let signature = sign_create_project_message(creator, 0, DEFAULT_EXPIRY, signer.contract_address);
    start_cheat_caller_address(factory.contract_address, creator);
    let project_id = factory.create_project(0, DEFAULT_EXPIRY, signature);
    stop_cheat_caller_address(factory.contract_address);
    let project_address = factory.get_project_contract(project_id);
    let project = IPaxmataProjectDispatcher { contract_address: project_address };
    assert_eq!(project.factory(), factory.contract_address);
    assert_eq!(project.engagement_fee(), DEFAULT_ENGAGEMENT_FEE);
    assert_eq!(project.completion_bonus_bps(), DEFAULT_COMPLETION_BONUS_BPS);
}

#[test]
fn test_create_multiple_projects_increments_ids() {
    let (factory, signer, _) = setup();
    let creator = addr('creator');
    let sig0 = sign_create_project_message(creator, 0, DEFAULT_EXPIRY, signer.contract_address);
    start_cheat_caller_address(factory.contract_address, creator);
    let id1 = factory.create_project(0, DEFAULT_EXPIRY, sig0);
    let sig1 = sign_create_project_message(creator, 1, DEFAULT_EXPIRY, signer.contract_address);
    let id2 = factory.create_project(1, DEFAULT_EXPIRY, sig1);
    stop_cheat_caller_address(factory.contract_address);
    assert_eq!(id1, 1);
    assert_eq!(id2, 2);
    assert_eq!(factory.total_projects(), 2);
}

#[test]
fn test_create_project_different_creators_have_independent_nonces() {
    let (factory, signer, _) = setup();
    let creator1 = addr('creator1');
    let creator2 = addr('creator2');
    let sig1 = sign_create_project_message(creator1, 0, DEFAULT_EXPIRY, signer.contract_address);
    start_cheat_caller_address(factory.contract_address, creator1);
    let id1 = factory.create_project(0, DEFAULT_EXPIRY, sig1);
    stop_cheat_caller_address(factory.contract_address);
    let sig2 = sign_create_project_message(creator2, 0, DEFAULT_EXPIRY, signer.contract_address);
    start_cheat_caller_address(factory.contract_address, creator2);
    let id2 = factory.create_project(0, DEFAULT_EXPIRY, sig2);
    stop_cheat_caller_address(factory.contract_address);
    assert_ne!(factory.get_project_contract(id1), factory.get_project_contract(id2));
    assert_eq!(factory.total_projects(), 2);
}

#[test]
#[should_panic(expected: "Signature has expired")]
fn test_create_project_panics_on_expired_signature() {
    let (factory, signer, _) = setup();
    let creator = addr('creator');
    let expiry: u64 = 1000;
    let signature = sign_create_project_message(creator, 0, expiry, signer.contract_address);
    start_cheat_block_timestamp_global(expiry + 1);
    start_cheat_caller_address(factory.contract_address, creator);
    factory.create_project(0, expiry, signature);
}

#[test]
#[should_panic(expected: "Invalid signature")]
fn test_create_project_panics_on_invalid_signature() {
    let (factory, _, _) = setup();
    let creator = addr('creator');
    start_cheat_caller_address(factory.contract_address, creator);
    factory.create_project(0, DEFAULT_EXPIRY, array![0, 0]);
}

#[test]
#[should_panic(expected: 'Nonces: invalid nonce')]
fn test_create_project_panics_on_wrong_nonce() {
    let (factory, signer, _) = setup();
    let creator = addr('creator');
    let wrong_nonce: felt252 = 5;
    let signature = sign_create_project_message(
        creator, wrong_nonce, DEFAULT_EXPIRY, signer.contract_address,
    );
    start_cheat_caller_address(factory.contract_address, creator);
    factory.create_project(wrong_nonce, DEFAULT_EXPIRY, signature);
}

#[test]
#[should_panic(expected: 'Nonces: invalid nonce')]
fn test_create_project_panics_on_replayed_nonce() {
    let (factory, signer, _) = setup();
    let creator = addr('creator');
    let sig_first = sign_create_project_message(creator, 0, DEFAULT_EXPIRY, signer.contract_address);
    start_cheat_caller_address(factory.contract_address, creator);
    factory.create_project(0, DEFAULT_EXPIRY, sig_first);
    let sig_replay = sign_create_project_message(creator, 0, DEFAULT_EXPIRY, signer.contract_address);
    factory.create_project(0, DEFAULT_EXPIRY, sig_replay);
}

#[test]
fn test_set_default_token_updates_token() {
    let (factory, _, _) = setup();
    let new_token = addr('new_token');
    start_cheat_caller_address(factory.contract_address, addr('owner'));
    factory.set_default_token(new_token);
    stop_cheat_caller_address(factory.contract_address);
    assert_eq!(factory.default_token(), new_token);
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_set_default_token_panics_if_not_owner() {
    let (factory, _, _) = setup();
    start_cheat_caller_address(factory.contract_address, addr('not_owner'));
    factory.set_default_token(addr('new_token'));
}

#[test]
#[should_panic(expected: "Default token cannot be zero address")]
fn test_set_default_token_panics_on_zero_address() {
    let (factory, _, _) = setup();
    let zero: ContractAddress = 0.try_into().unwrap();
    start_cheat_caller_address(factory.contract_address, addr('owner'));
    factory.set_default_token(zero);
}

#[test]
fn test_set_signer_updates_signer() {
    let (factory, _, _) = setup();
    let new_signer = addr('new_signer');
    start_cheat_caller_address(factory.contract_address, addr('owner'));
    factory.set_signer(new_signer);
    stop_cheat_caller_address(factory.contract_address);
    assert_eq!(factory.signer(), new_signer);
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_set_signer_panics_if_not_owner() {
    let (factory, _, _) = setup();
    start_cheat_caller_address(factory.contract_address, addr('not_owner'));
    factory.set_signer(addr('new_signer'));
}

#[test]
#[should_panic(expected: "Signer cannot be zero address")]
fn test_set_signer_panics_on_zero_address() {
    let (factory, _, _) = setup();
    let zero: ContractAddress = 0.try_into().unwrap();
    start_cheat_caller_address(factory.contract_address, addr('owner'));
    factory.set_signer(zero);
}

#[test]
fn test_set_treasury_updates_treasury() {
    let (factory, _, _) = setup();
    let new_treasury = addr('new_treasury');
    start_cheat_caller_address(factory.contract_address, addr('owner'));
    factory.set_treasury(new_treasury);
    stop_cheat_caller_address(factory.contract_address);
    assert_eq!(factory.treasury(), new_treasury);
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_set_treasury_panics_if_not_owner() {
    let (factory, _, _) = setup();
    start_cheat_caller_address(factory.contract_address, addr('not_owner'));
    factory.set_treasury(addr('new_treasury'));
}

#[test]
#[should_panic(expected: "Treasury cannot be zero address")]
fn test_set_treasury_panics_on_zero_address() {
    let (factory, _, _) = setup();
    let zero: ContractAddress = 0.try_into().unwrap();
    start_cheat_caller_address(factory.contract_address, addr('owner'));
    factory.set_treasury(zero);
}

#[test]
fn test_set_engagement_fee_updates_fee() {
    let (factory, _, _) = setup();
    let new_fee: u256 = 500_000;
    start_cheat_caller_address(factory.contract_address, addr('owner'));
    factory.set_engagement_fee(new_fee);
    stop_cheat_caller_address(factory.contract_address);
    assert_eq!(factory.engagement_fee(), new_fee);
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_set_engagement_fee_panics_if_not_owner() {
    let (factory, _, _) = setup();
    start_cheat_caller_address(factory.contract_address, addr('not_owner'));
    factory.set_engagement_fee(500_000);
}

#[test]
fn test_set_donation_fee_bps_updates_fee() {
    let (factory, _, _) = setup();
    let new_fee: u16 = 500;
    start_cheat_caller_address(factory.contract_address, addr('owner'));
    factory.set_donation_fee_bps(new_fee);
    stop_cheat_caller_address(factory.contract_address);
    assert_eq!(factory.donation_fee_bps(), new_fee);
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_set_donation_fee_bps_panics_if_not_owner() {
    let (factory, _, _) = setup();
    start_cheat_caller_address(factory.contract_address, addr('not_owner'));
    factory.set_donation_fee_bps(500);
}

#[test]
#[should_panic(expected: "Donation fee exceeds 10%")]
fn test_set_donation_fee_bps_panics_if_exceeds_max() {
    let (factory, _, _) = setup();
    start_cheat_caller_address(factory.contract_address, addr('owner'));
    factory.set_donation_fee_bps(1001);
}

#[test]
fn test_set_completion_bonus_bps_updates_bonus() {
    let (factory, _, _) = setup();
    let new_bonus: u16 = 200;
    start_cheat_caller_address(factory.contract_address, addr('owner'));
    factory.set_completion_bonus_bps(new_bonus);
    stop_cheat_caller_address(factory.contract_address);
    assert_eq!(factory.completion_bonus_bps(), new_bonus);
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_set_completion_bonus_bps_panics_if_not_owner() {
    let (factory, _, _) = setup();
    start_cheat_caller_address(factory.contract_address, addr('not_owner'));
    factory.set_completion_bonus_bps(200);
}

#[test]
#[should_panic(expected: "Completion bonus exceeds 10%")]
fn test_set_completion_bonus_bps_panics_if_exceeds_max() {
    let (factory, _, _) = setup();
    start_cheat_caller_address(factory.contract_address, addr('owner'));
    factory.set_completion_bonus_bps(1001);
}

#[test]
fn test_set_project_class_hash_updates_hash() {
    let (factory, _, _) = setup();
    let new_class_hash = get_project_class_hash();
    start_cheat_caller_address(factory.contract_address, addr('owner'));
    factory.set_project_class_hash(new_class_hash);
    stop_cheat_caller_address(factory.contract_address);
    assert_eq!(factory.project_class_hash(), new_class_hash);
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_set_project_class_hash_panics_if_not_owner() {
    let (factory, _, _) = setup();
    let class_hash = get_project_class_hash();
    start_cheat_caller_address(factory.contract_address, addr('not_owner'));
    factory.set_project_class_hash(class_hash);
}

#[test]
#[should_panic(expected: "Project class hash cannot be zero")]
fn test_set_project_class_hash_panics_on_zero_hash() {
    let (factory, _, _) = setup();
    let zero: ClassHash = 0.try_into().unwrap();
    start_cheat_caller_address(factory.contract_address, addr('owner'));
    factory.set_project_class_hash(zero);
}
