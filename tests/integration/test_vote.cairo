%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from src.interface.renewal import Renewal
from lib.starknetid.src.IStarknetID import IStarknetid
from src.interface.naming import Naming
from lib.cairo_contracts.src.openzeppelin.token.erc20.IERC20 import IERC20

const TH0RGAL_STRING = 28235132438;

@external
func __setup__() {
    %{        
        context.renewal_contract = deploy_contract("./src/main.cairo", [111111, 22222]).contract_address
    %}
    return ();
}

@external
func test_vote_upgrade{syscall_ptr: felt*, range_check_ptr, pedersen_ptr: HashBuiltin*}() {
    tempvar renewal_contract;
    %{
        ids.renewal_contract = context.renewal_contract
        stop_prank_callable = start_prank(123, target_contract_address=ids.renewal_contract)
    %}

    Renewal.vote_upgrade(renewal_contract, 'upgrade_1');

    let (vote) = Renewal.has_voted_upgrade(renewal_contract, 123, 'upgrade_1');
    assert vote = 1;

    %{ stop_prank_callable() %}

    return ();
}
