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

    fn renew(ref self: TContractState, domain: felt252, days: felt252, );

    fn domain_to_address(
        self: @TContractState, domain: array::Array::<felt252>
    ) -> starknet::ContractAddress;

    fn domain_to_expiry(self: @TContractState, domain: array::Array::<felt252>) -> felt252;
}

#[starknet::interface]
trait MockNamingABI<TContractState> {
    fn buy(
        ref self: TContractState,
        token_id: felt252,
        domain: felt252,
        days: felt252,
        resolver: felt252,
        address: starknet::ContractAddress,
    );

    fn renew(ref self: TContractState, domain: felt252, days: felt252, );

    fn domain_to_address(
        self: @TContractState, domain: array::Array::<felt252>
    ) -> starknet::ContractAddress;

    fn domain_to_expiry(self: @TContractState, domain: array::Array::<felt252>) -> felt252;
}

#[starknet::contract]
mod Naming {
    use super::INaming;
    use zeroable::Zeroable;
    use array::ArrayTrait;
    use traits::Into;
    use integer::u256_from_felt252;
    use auto_renew_contract::tests::mocks::erc20::{
        ERC20, MockERC20ABIDispatcher, MockERC20ABIDispatcherTrait
    };
    use debug::PrintTrait;

    #[derive(Serde, Copy, Drop, storage_access::StorageAccess)]
    struct DomainData {
        owner: felt252,
        address: starknet::ContractAddress,
        expiry: felt252,
    }

    //
    // Storage
    //

    #[storage]
    struct Storage {
        starknetid_contract: starknet::ContractAddress,
        _pricing_contract: starknet::ContractAddress,
        _erc20_address: starknet::ContractAddress,
        _domain_data: LegacyMap::<felt252, DomainData>,
    }

    //
    // Constructor
    //

    #[constructor]
    fn constructor(
        ref self: ContractState,
        starknetid_addr: starknet::ContractAddress,
        pricing_addr: starknet::ContractAddress,
        erc20_addr: starknet::ContractAddress
    ) {
        self.starknetid_contract.write(starknetid_addr);
        self._pricing_contract.write(pricing_addr);
        self._erc20_address.write(erc20_addr);
    }

    //
    // Interface impl
    //

    #[external(v0)]
    impl INamingImpl of INaming<ContractState> {
        fn domain_to_address(
            self: @ContractState, domain: Array::<felt252>
        ) -> starknet::ContractAddress {
            let hashed_domain = self._hashed_domain(domain);
            let domain_data = self._domain_data.read(hashed_domain);
            domain_data.address
        }

        fn domain_to_expiry(self: @ContractState, domain: Array::<felt252>) -> felt252 {
            let hashed_domain = self._hashed_domain(domain);
            let domain_data = self._domain_data.read(hashed_domain);
            domain_data.expiry
        }

        fn buy(
            ref self: ContractState,
            token_id: felt252,
            domain: felt252,
            days: felt252,
            resolver: felt252,
            address: starknet::ContractAddress,
        ) {
            // pay_buy_domain
            let caller = starknet::get_caller_address();
            let erc20 = self._erc20_address.read();
            let contract = starknet::get_contract_address();
            MockERC20ABIDispatcher {
                contract_address: erc20
            }.transfer_from(caller, contract, u256 { low: 500, high: 0 });

            // write_domain_data
            let expiry = starknet::get_block_timestamp().into() + 86400 * days;
            self._domain_data.write(domain, DomainData { owner: token_id, address, expiry,  });
        }

        fn renew(ref self: ContractState, domain: felt252, days: felt252, ) {
            let current_timestamp = starknet::get_block_timestamp();
            let caller = starknet::get_caller_address();

            let mut domain_arr = ArrayTrait::<felt252>::new();
            domain_arr.append(domain);
            let hashed_domain = self._hashed_domain(domain_arr);

            // pay renew domain
            let erc20 = self._erc20_address.read();
            let contract = starknet::get_contract_address();
            MockERC20ABIDispatcher {
                contract_address: erc20
            }.transfer_from(caller, contract, u256 { low: 500, high: 0 });

            // write domain data with new expiry
            let domain_data: DomainData = self._domain_data.read(hashed_domain);
            let new_expiry = self.new_expiry(domain_data.expiry, current_timestamp.into(), days);
            self
                ._domain_data
                .write(
                    hashed_domain,
                    DomainData {
                        owner: domain_data.owner, address: domain_data.address, expiry: new_expiry, 
                    }
                );
        }
    }

    //
    // Internals
    //

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _hashed_domain(self: @ContractState, domain: Array::<felt252>) -> felt252 {
            let mut domain = domain;
            match domain.pop_front() {
                Option::Some(x) => x,
                Option::None(_) => 0,
            }
        }

        fn new_expiry(
            self: @ContractState, current_expiry: felt252, current_timestamp: felt252, days: felt252
        ) -> felt252 {
            if u256_from_felt252(current_expiry) < u256_from_felt252(current_timestamp) {
                return current_timestamp + 86400 * days;
            } else {
                return current_expiry + 86400 * days;
            }
        }
    }
}

