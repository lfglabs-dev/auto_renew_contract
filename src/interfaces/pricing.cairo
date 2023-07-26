#[starknet::interface]
trait IPricing<TContractState> {
    fn compute_buy_price(
        self: @TContractState, domain: felt252, days: felt252
    ) -> (starknet::ContractAddress, u256);

    fn compute_renew_price(
        self: @TContractState, domain: felt252, days: felt252
    ) -> (starknet::ContractAddress, u256);
}
