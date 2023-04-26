%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from src.interface.renewal import Renewal
from lib.starknetid.src.IStarknetID import IStarknetid
from src.interface.naming import Naming
from lib.cairo_contracts.src.openzeppelin.token.erc20.IERC20 import IERC20

const UPGRADE_ID = 1;
const NEW_IMPLEMENTATION = 123421241424141;

@external
func __setup__{syscall_ptr: felt*, range_check_ptr, pedersen_ptr: HashBuiltin*}() {
    tempvar renewal_contract;
    %{        
        context.renewal_contract = deploy_contract("./src/main.cairo").contract_address
        ids.renewal_contract = context.renewal_contract
    %}
    Renewal.initializer(renewal_contract, 123, 11111, 22222);
    return ();
}

@external
func test_vote_upgrade{syscall_ptr: felt*, range_check_ptr, pedersen_ptr: HashBuiltin*}() {
    tempvar renewal_contract;
    %{
        ids.renewal_contract = context.renewal_contract
        stop_prank_callable = start_prank(123, target_contract_address=ids.renewal_contract)
    %}

    // Test vote for upgrade
    Renewal.vote_upgrade(renewal_contract, UPGRADE_ID, NEW_IMPLEMENTATION, 1);
    let (vote) = Renewal.has_voted_upgrade(renewal_contract, 123, UPGRADE_ID, NEW_IMPLEMENTATION);
    assert vote = 1;

    %{ stop_prank_callable() %}
    return ();
}

@external
func test_vote_upgrade_fail{syscall_ptr: felt*, range_check_ptr, pedersen_ptr: HashBuiltin*}() {
    tempvar renewal_contract;
    %{
        ids.renewal_contract = context.renewal_contract
        stop_prank_callable = start_prank(123, target_contract_address=ids.renewal_contract)
        expect_revert(error_message="Votes can either be 1 or 0")
    %}
    // Should revert because vote value is incorrect
    Renewal.vote_upgrade(renewal_contract, UPGRADE_ID, NEW_IMPLEMENTATION, 3);

    %{ stop_prank_callable() %}
    return ();
}


@external
func test_upgrade_failed{syscall_ptr: felt*, range_check_ptr, pedersen_ptr: HashBuiltin*}() {
    tempvar renewal_contract;
    %{
        ids.renewal_contract = context.renewal_contract
        stop_prank_callable = start_prank(123, target_contract_address=ids.renewal_contract)
        expect_revert(error_message="Not enough votes to upgrade")
    %}
    // Should revert because quorum vote not reached
    Renewal.upgrade(renewal_contract, UPGRADE_ID, NEW_IMPLEMENTATION);
    
    %{ stop_prank_callable() %}
    return ();
}

@external
func test_upgrade{syscall_ptr: felt*, range_check_ptr, pedersen_ptr: HashBuiltin*}() {
    alloc_locals;
    // Simulate 3 votes for
    generate_votes();
    tempvar renewal_contract;
    %{
        ids.renewal_contract = context.renewal_contract
        stop_prank_callable = start_prank(123, target_contract_address=ids.renewal_contract)
    %}

    // Testing upgrade goes through
    Renewal.upgrade(renewal_contract,UPGRADE_ID,  NEW_IMPLEMENTATION);

    %{ stop_prank_callable() %}
    return ();
}

@external
func test_upgrade_blacklisted_failed{syscall_ptr: felt*, range_check_ptr, pedersen_ptr: HashBuiltin*}() {
    alloc_locals;
    // Simulate 3 votes for
    generate_votes();
    tempvar renewal_contract;
    %{
        ids.renewal_contract = context.renewal_contract
        stop_prank_callable = start_prank(123, target_contract_address=ids.renewal_contract)
        expect_revert(error_message="Upgrade is blacklisted")
    %}

    // Upgrading once
    Renewal.upgrade(renewal_contract,UPGRADE_ID,  NEW_IMPLEMENTATION);

    // Should revert because upgrade_id is blacklisted
    const ANOTHER_IMPLEMENTATION = 123421241424142;
    Renewal.upgrade(renewal_contract, UPGRADE_ID,  ANOTHER_IMPLEMENTATION);

    %{ stop_prank_callable() %}
    return ();
}

// util function to vote for upgrade
func generate_votes{syscall_ptr: felt*, range_check_ptr, pedersen_ptr: HashBuiltin*}() {
    alloc_locals;
    tempvar renewal_contract;
    %{
        ids.renewal_contract = context.renewal_contract
        stop_prank_callable = start_prank(123, target_contract_address=ids.renewal_contract)
    %}
    Renewal.vote_upgrade(renewal_contract, UPGRADE_ID, NEW_IMPLEMENTATION, 1);
    %{ 
        stop_prank_callable() 
        stop_prank_callable = start_prank(456, target_contract_address=ids.renewal_contract)
    %}
    Renewal.vote_upgrade(renewal_contract, UPGRADE_ID, NEW_IMPLEMENTATION, 1);
    %{ 
        stop_prank_callable() 
        stop_prank_callable = start_prank(789, target_contract_address=ids.renewal_contract)
    %}
    Renewal.vote_upgrade(renewal_contract, UPGRADE_ID, NEW_IMPLEMENTATION, 1);
    %{ stop_prank_callable()  %}
    return ();
}
