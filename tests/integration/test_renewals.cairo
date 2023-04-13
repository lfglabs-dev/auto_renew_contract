%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from src.interface.renewal import Renewal
from lib.starknetid.src.IStarknetID import IStarknetid
from src.interface.naming import Naming
from lib.cairo_contracts.src.openzeppelin.token.erc20.IERC20 import IERC20

const TH0RGAL_STRING = 28235132438;

@external
func __setup__{syscall_ptr: felt*, range_check_ptr, pedersen_ptr: HashBuiltin*}() {
    %{
        from starkware.starknet.compiler.compile import get_selector_from_name
        context.starknet_id_contract = deploy_contract("./lib/starknetid/src/StarknetId.cairo").contract_address
        context.pricing_contract = deploy_contract("./lib/naming_contract/src/pricing/main.cairo", [123]).contract_address
        logic_contract_class_hash = declare("./lib/naming_contract/src/naming/main.cairo").class_hash
        context.naming_contract = deploy_contract("./lib/cairo_contracts/src/openzeppelin/upgrades/presets/Proxy.cairo", [logic_contract_class_hash,
            get_selector_from_name("initializer"), 4, 
            context.starknet_id_contract, context.pricing_contract, 456, 0]).contract_address
        
        context.renewal_contract = deploy_contract("./src/main.cairo", [context.naming_contract, context.pricing_contract]).contract_address
    %}
    return ();
}

func buy_domain{syscall_ptr: felt*, range_check_ptr, pedersen_ptr: HashBuiltin*}(days: felt) {
    tempvar starknet_id_contract;
    tempvar naming_contract;
    %{
        ids.starknet_id_contract = context.starknet_id_contract
        ids.naming_contract = context.naming_contract
        stop_prank_callable = start_prank(456)
        stop_mock = mock_call(123, "transferFrom", [1])
        warp(1, context.naming_contract)
    %}

    let token_id = 1;
    IStarknetid.mint(starknet_id_contract, token_id);
    Naming.buy(naming_contract, token_id, TH0RGAL_STRING, days, 0, 456);
    let (addr) = Naming.domain_to_address(naming_contract, 1, new (TH0RGAL_STRING));
    assert addr = 456;
    
    %{ 
        stop_mock() 
        stop_prank_callable()
    %}

    return ();
}

@external
func test_toggle_renewal{syscall_ptr: felt*, range_check_ptr, pedersen_ptr: HashBuiltin*}() {
    buy_domain(365);
    tempvar renewal_contract;
    %{
        ids.renewal_contract = context.renewal_contract
        stop_prank_callable = start_prank(456, target_contract_address=ids.renewal_contract)
    %}

    Renewal.toggle_renewals(renewal_contract, TH0RGAL_STRING);

    let (will_renew) = Renewal.is_renewing(renewal_contract, TH0RGAL_STRING, 456);
    assert will_renew = 1;

    Renewal.toggle_renewals(renewal_contract, TH0RGAL_STRING);

    let (wont_renew) = Renewal.is_renewing(renewal_contract, TH0RGAL_STRING, 456);
    assert wont_renew = 0;

    %{ stop_prank_callable() %}

    return ();
}

@external
func test_toggle_renewal_fail_not_owner{syscall_ptr: felt*, range_check_ptr, pedersen_ptr: HashBuiltin*}() {
    buy_domain(365);
    tempvar renewal_contract;
    %{
        ids.renewal_contract = context.renewal_contract
        expect_revert(error_message="Caller is not owner of domain")
    %}
    Renewal.toggle_renewals(renewal_contract, TH0RGAL_STRING);

    return ();
}

@external
func test_renews_fail_not_toggled{syscall_ptr: felt*, range_check_ptr, pedersen_ptr: HashBuiltin*}() {
    buy_domain(365);
    tempvar renewal_contract;
    %{
        ids.renewal_contract = context.renewal_contract
        expect_revert(error_message="Owner has not activated renewals for this domain")
    %}
    let (wont_renew) = Renewal.is_renewing(renewal_contract, TH0RGAL_STRING, 456);
    assert wont_renew = 0;

    Renewal.renew(renewal_contract, TH0RGAL_STRING);

    return ();
}


@external
func test_renew_fail_expiry{syscall_ptr: felt*, range_check_ptr, pedersen_ptr: HashBuiltin*}() {
    buy_domain(60);
    tempvar renewal_contract;
    %{
        ids.renewal_contract = context.renewal_contract
        expect_revert(error_message="Domain is not set to expire within a month")
        stop_prank_callable = start_prank(456, target_contract_address=ids.renewal_contract)
    %}

    Renewal.toggle_renewals(renewal_contract, TH0RGAL_STRING);
    let (will_renew) = Renewal.is_renewing(renewal_contract, TH0RGAL_STRING, 456);
    assert will_renew = 1;

    %{ stop_prank_callable() %}

    Renewal.renew(renewal_contract, TH0RGAL_STRING);

    return ();
}

@external
func test_renew_domain{syscall_ptr: felt*, range_check_ptr, pedersen_ptr: HashBuiltin*}() {
    buy_domain(60);
    tempvar renewal_contract;
    tempvar naming;
    %{
        ids.renewal_contract = context.renewal_contract
        ids.naming = context.naming_contract
        stop_prank_callable = start_prank(456, target_contract_address=ids.renewal_contract)
        warp(5180000, context.renewal_contract)
        stop_mock = mock_call(123, "transferFrom", [1])
    %}

    Renewal.toggle_renewals(renewal_contract, TH0RGAL_STRING);
    let (will_renew) = Renewal.is_renewing(renewal_contract, TH0RGAL_STRING, 456);
    assert will_renew = 1;

    %{ stop_prank_callable() %}

    Renewal.renew(renewal_contract, TH0RGAL_STRING);

    assert_expiry(TH0RGAL_STRING, (60 * 86400) + (365 * 86400) + 1);

    %{ 
        stop_mock()  
    %}

    return ();
}


func assert_expiry{syscall_ptr: felt*, range_check_ptr, pedersen_ptr: HashBuiltin*}(domain: felt, expected: felt) {
    tempvar naming;
    %{ 
        ids.naming = context.naming_contract
        warp(5180000, context.naming_contract) 
    %}
    let (expiry) = Naming.domain_to_expiry(naming, 1, cast(new(domain), felt*));
    assert expiry = expected;

    return ();
}




