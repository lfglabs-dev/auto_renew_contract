use array::ArrayTrait;
use core::result::ResultTrait;
use option::OptionTrait;
use starknet::class_hash::Felt252TryIntoClassHash;
use starknet::ContractAddress;
use traits::TryInto;
use debug::PrintTrait;

fn deploy(contract_class_hash: felt252, calldata: Array<felt252>) -> ContractAddress {
    let (address, _) = starknet::deploy_syscall(
        contract_class_hash.try_into().unwrap(), 0, calldata.span(), false
    )
        .unwrap();
    address
}


fn deploy_debug(contract_class_hash: felt252, calldata: Array<felt252>) {
    match starknet::deploy_syscall(
        contract_class_hash.try_into().unwrap(), 0, calldata.span(), false
    ) {
        Result::Ok((address, _)) => address.print(),
        Result::Err(x) => x.print(),
    };
}

