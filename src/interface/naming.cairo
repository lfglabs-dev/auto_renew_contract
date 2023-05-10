%lang starknet
from starkware.cairo.common.uint256 import Uint256

@contract_interface
namespace Naming {
    func domain_to_address(domain_len: felt, domain: felt*) -> (address: felt) {
    }

    func domain_to_expiry(domain_len: felt, domain: felt*) -> (address: felt) {
    }

    func address_to_domain(address: felt) -> (domain_len: felt, domain: felt*) {
    }

    func domain_to_token_id(domain_len: felt, domain: felt*) -> (owner: felt) {
    }

    func buy(token_id: felt, domain: felt, days: felt, resolver: felt, address: felt) {
    }

    func renew(domain: felt, days: felt) {
    }
}