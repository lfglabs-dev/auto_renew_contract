#[starknet::interface]
trait INaming<TContractState> {
    fn buy(
        ref self: TContractState,
        token_id: felt252,
        domain: felt252,
        days: felt252,
        resolver: felt252,
        address: starknet::ContractAddress,
    );

    fn renew(ref self: TContractState, domain: felt252, days: felt252, sponsor: felt252);

    fn domain_to_address(
        self: @TContractState, domain: array::Array::<felt252>
    ) -> starknet::ContractAddress;

    fn domain_to_expiry(self: @TContractState, domain: array::Array::<felt252>) -> felt252;
}

