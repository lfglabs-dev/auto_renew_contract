%lang starknet
from starkware.cairo.common.math import assert_nn
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address, get_block_timestamp, get_contract_address
from starkware.cairo.common.math import assert_not_zero, assert_le

from lib.cairo_contracts.src.openzeppelin.token.erc20.IERC20 import IERC20
from src.interface.naming import Naming
from src.interface.pricing import Pricing

//
// Storage
//

@storage_var
func naming_contract() -> (contract_address: felt) {
}

@storage_var
func pricing_contract() -> (contract_address: felt) {
}

@storage_var
func renews(renewer: felt, domain: felt) -> (bool: felt) {
}

@storage_var
func voted_upgrade(user: felt, upgrade: felt) -> (bool: felt) {
}

//
// Events
//

@event
func ToggledRenewal(domain: felt, renewer: felt, value: felt) {
}

@event
func DomainRenewed(domain: felt, renewer: felt, days: felt) {
}

@event
func VotedUpgrade(caller: felt, upgrade: felt, vote: felt) {
}

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    naming_address: felt, 
    pricing_address: felt
) {
    naming_contract.write(naming_address);
    pricing_contract.write(pricing_address);
    return ();
}

// @notice Get the status of renewals for a domain
// @param domain Domain to get status of
// @param user User to get status of
@view
func is_renewing{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    domain: felt, 
    renewer: felt
) -> (res: felt) {
    let (res) = renews.read(renewer, domain);
    return (res,);
}

// @notice Get the status of an upgrade vote
// @param upgrade Upgrade to get status of
// @param user User to get status of
@view
func has_voted_upgrade{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    user: felt,
    upgrade: felt, 
) -> (res: felt) {
    let (res) = voted_upgrade.read(user, upgrade);
    return (res,);
}

//
// Externals
//

// @notice Activate or deactivate renewals for a domain
// @param domain Domain to activate or deactivate renewals for
// @dev callable by owner of domain
@external
func toggle_renewals{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    domain: felt,
) {
    alloc_locals;
    let (caller) = get_caller_address();
    let (contract) = naming_contract.read();

    let (prev_renew) = renews.read(caller, domain);
    renews.write(caller, domain, 1 - prev_renew);

    ToggledRenewal.emit(domain, caller, 1 - prev_renew);

    return ();
} 

// @notice Renew a domain
// @param domain Domain to renew
// @dev callable by anyone, but will only renew if renewals are activated for domain
@external
func renew{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    root_domain: felt, renewer: felt,
) {
    alloc_locals;
    let (naming) = naming_contract.read(); 
    let (can_renew) = renews.read(renewer, root_domain);

    with_attr error_message("Renewer has not activated renewals for this domain") {
        assert_not_zero(can_renew);
    }

    let (expiry) = Naming.domain_to_expiry(naming, 1, cast(new(root_domain), felt*));
    let (block_timestamp) = get_block_timestamp();
    with_attr error_message("Domain is not set to expire within a month") {
        assert_le(expiry, block_timestamp + 86400 * 30);
    }

    let (pricing) = pricing_contract.read();
    let (erc20, renewal_price) = Pricing.compute_renew_price(pricing, root_domain, 365);

    let (contract) = get_contract_address();
    with_attr error_message("Error transferring tokens from renewer to contract") {
        IERC20.transferFrom(erc20, renewer, contract, renewal_price);
    }

    Naming.renew(naming, root_domain, 365);
    
    DomainRenewed.emit(root_domain, renewer, 365);

    return ();
}

@external
func batch_renew{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    domain_len: felt, domain: felt*, renewer_len: felt, renewer: felt*
) {
    with_attr error_message("domain and renewer array must have same length") {
        assert domain_len = renewer_len;
    }
    return _batch_renew_iter(domain_len, domain, renewer_len, renewer);
}

func _batch_renew_iter{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    domain_len: felt, domain: felt*, renewer_len: felt, renewer: felt*
) {
    if (domain_len == 0) {
        return ();
    }
    renew(domain[0], renewer[0]);
    return _batch_renew_iter(domain_len - 1, domain + 1, renewer_len - 1, renewer + 1);
}

// @notice Vote for an upgrade
// @param upgrade Upgrade to vote for
@external
func vote_upgrade{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    upgrade: felt,
) {
    let (caller) = get_caller_address();
    let (vote) = voted_upgrade.read(caller, upgrade);

    voted_upgrade.write(caller, upgrade, 1 - vote);

    VotedUpgrade.emit(caller, upgrade, 1 - vote);

    return ();
}

// @external
// func upgrade{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
//     upgrade: felt,
//     hash: felt,
// ) {
//     return ();
// }
