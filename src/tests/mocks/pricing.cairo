#[starknet::interface]
trait IPricing<TContractState> {
    fn compute_buy_price(
        self: @TContractState, domain: felt252, days: felt252
    ) -> (starknet::ContractAddress, u256);

    fn compute_renew_price(
        self: @TContractState, domain: felt252, days: felt252
    ) -> (starknet::ContractAddress, u256);
}

#[starknet::interface]
trait MockPricingABI<TContractState> {
    fn compute_buy_price(
        self: @TContractState, domain: felt252, days: felt252
    ) -> (starknet::ContractAddress, u256);

    fn compute_renew_price(
        self: @TContractState, domain: felt252, days: felt252
    ) -> (starknet::ContractAddress, u256);
}

#[starknet::contract]
mod Pricing {
    use super::IPricing;
    // use zeroable::Zeroable;

    //
    // Storage
    //

    #[storage]
    struct Storage {
        erc20: starknet::ContractAddress, 
    }

    //
    // Constructor
    //

    #[constructor]
    fn constructor(ref self: ContractState, erc20_addr: starknet::ContractAddress) {
        self.erc20.write(erc20_addr);
    }

    //
    // Interface impl
    //

    #[external(v0)]
    impl IPricingImpl of IPricing<ContractState> {
        fn compute_buy_price(
            self: @ContractState, domain: felt252, days: felt252
        ) -> (starknet::ContractAddress, u256) {
            (self.erc20.read(), u256 { low: 500, high: 0 })
        }

        fn compute_renew_price(
            self: @ContractState, domain: felt252, days: felt252
        ) -> (starknet::ContractAddress, u256) {
            (self.erc20.read(), u256 { low: 500, high: 0 })
        }
    }
}
