%lang starknet

@contract_interface
namespace Renewal {
    func initializer(admin: felt, naming_address: felt, pricing_address: felt) {
    }
    
    func will_renew(domain: felt, user: felt) -> (res: felt) {
    }

    func has_voted_upgrade(upgrade: felt, user: felt) -> (res: felt) {
    }

    func toggle_renewals(domain: felt) {
    }

    func renew(root_domain: felt, renewer: felt) {
    }

    func batch_renew(domain_len: felt, domain: felt*, renewer_len: felt, renewer: felt*) {
    }

    func vote_upgrade(upgrade: felt, vote: felt) {
    }

    func upgrade(new_implementation: felt) {
    }
}