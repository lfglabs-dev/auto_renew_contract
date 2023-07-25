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
    103374042_u64
}

fn TH0RGAL_DOMAIN() -> felt252 {
    28235132438
}

fn OTHER_DOMAIN() -> felt252 {
    11111111111
}
