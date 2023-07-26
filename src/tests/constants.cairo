fn OWNER() -> starknet::ContractAddress {
    starknet::contract_address_const::<10>()
}

fn OTHER() -> starknet::ContractAddress {
    starknet::contract_address_const::<20>()
}

fn USER() -> starknet::ContractAddress {
    starknet::contract_address_const::<123>()
}

fn ZERO() -> starknet::ContractAddress {
    Zeroable::zero()
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

fn OTHER_DOMAIN() -> felt252 {
    11111111111
}
