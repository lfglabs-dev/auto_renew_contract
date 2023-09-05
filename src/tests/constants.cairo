use starknet::contract_address::ContractAddressZeroable;

fn ADMIN() -> starknet::ContractAddress {
    starknet::contract_address_const::<0x123>()
}

fn OTHER() -> starknet::ContractAddress {
    starknet::contract_address_const::<0x456>()
}

fn ZERO() -> starknet::ContractAddress {
    ContractAddressZeroable::zero()
}

fn BLOCK_TIMESTAMP() -> u64 {
    1690364
}

fn BLOCK_TIMESTAMP_ADD() -> u64 {
    1690364 + (86400 * 345)
}

fn BLOCK_TIMESTAMP_EXPIRED() -> u64 {
    1690364 + (86400 * 400)
}

fn TH0RGAL_DOMAIN() -> felt252 {
    28235132438
}

// 7 letter domain : 1234567
fn OTHER_DOMAIN() -> felt252 {
    13847469359445559
}
