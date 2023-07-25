#[starknet::interface]
trait IERC20<TContractState> {
    fn transfer_from(
        ref self: TContractState,
        sender: starknet::ContractAddress,
        recipient: starknet::ContractAddress,
        amount: u256
    ) -> bool;

    fn approve(ref self: TContractState, spender: starknet::ContractAddress, amount: u256) -> bool;
}
