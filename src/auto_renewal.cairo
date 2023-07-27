#[starknet::interface]
trait IAutoRenewal<TContractState> {
    fn is_renewing(
        self: @TContractState,
        domain: felt252,
        renewer: starknet::ContractAddress,
        limit_price: u256
    ) -> u64;

    fn get_contracts(
        self: @TContractState
    ) -> (starknet::ContractAddress, starknet::ContractAddress);

    fn toggle_renewals(ref self: TContractState, domain: felt252, limit_price: u256);

    fn renew(
        ref self: TContractState,
        root_domain: felt252,
        renewer: starknet::ContractAddress,
        limit_price: u256,
    );

    fn batch_renew(
        ref self: TContractState,
        domain: array::Array::<felt252>,
        renewer: array::Array::<starknet::ContractAddress>,
        limit_price: array::Array::<u256>,
    );
}

#[starknet::contract]
mod AutoRenewal {
    use starknet::ContractAddress;
    use starknet::{get_caller_address, get_contract_address, get_block_timestamp};
    use traits::{TryInto, Into};
    use option::OptionTrait;
    use array::ArrayTrait;
    use integer::u64_try_from_felt252;

    use auto_renew_contract::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use auto_renew_contract::interfaces::naming::{INamingDispatcher, INamingDispatcherTrait};

    #[storage]
    struct Storage {
        naming_contract: ContractAddress,
        erc20_contract: ContractAddress,
        // (renewer, domain, limit_price) -> 1 or 0
        _is_renewing: LegacyMap::<(ContractAddress, felt252, u256), u64>,
        // (renewer, domain) -> timestamp
        last_renewal: LegacyMap::<(ContractAddress, felt252), u64>,
    }

    //
    // Events
    //

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        toggled_renewal: toggled_renewal,
        domain_renewed: domain_renewed,
    }

    #[derive(Drop, starknet::Event)]
    struct toggled_renewal {
        domain: felt252,
        renewer: ContractAddress,
        limit_price: u256,
        is_renewing: u64,
        last_renewal: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct domain_renewed {
        domain: felt252,
        renewer: ContractAddress,
        days: felt252,
        limit_price: u256,
        timestamp: u64,
    }

    //
    // Constructor
    //

    #[constructor]
    fn constructor(
        ref self: ContractState, naming_address: ContractAddress, erc20_address: ContractAddress
    ) {
        self.naming_contract.write(naming_address);
        self.erc20_contract.write(erc20_address);
    }

    #[external(v0)]
    impl AutoRenewalImpl of super::IAutoRenewal<ContractState> {
        fn is_renewing(
            self: @ContractState, domain: felt252, renewer: ContractAddress, limit_price: u256
        ) -> u64 {
            self._is_renewing.read((renewer, domain, limit_price))
        }

        fn get_contracts(self: @ContractState) -> (ContractAddress, ContractAddress) {
            (self.naming_contract.read(), self.erc20_contract.read())
        }

        fn toggle_renewals(ref self: ContractState, domain: felt252, limit_price: u256) {
            let caller = get_caller_address();
            let prev_renew = self._is_renewing.read((caller, domain, limit_price));

            // we are using _is_renewing output as a boolean
            // here, we toggle its current value
            let new_renew = 1_u64 - prev_renew;
            self._is_renewing.write((caller, domain, limit_price), new_renew);

            let prev_last_renewal = self.last_renewal.read((caller, domain));
            // if we toggle the renewal on, we erase the previous renewal date
            let new_last_renewal = prev_last_renewal * prev_renew;
            self.last_renewal.write((caller, domain), new_last_renewal);

            self
                .emit(
                    Event::toggled_renewal(
                        toggled_renewal {
                            domain,
                            renewer: caller,
                            limit_price,
                            is_renewing: new_renew,
                            last_renewal: new_last_renewal
                        }
                    )
                )
        }

        fn renew(
            ref self: ContractState,
            root_domain: felt252,
            renewer: ContractAddress,
            limit_price: u256,
        ) {
            self._renew(root_domain, renewer, limit_price);
        }

        fn batch_renew(
            ref self: ContractState,
            domain: array::Array::<felt252>,
            renewer: array::Array::<starknet::ContractAddress>,
            limit_price: array::Array::<u256>,
        ) {
            assert(domain.len() == renewer.len(), 'Domain & renewer mismatch len');
            assert(domain.len() == limit_price.len(), 'Domain & price mismatch len');

            let mut domain = domain;
            let mut renewer = renewer;
            let mut limit_price = limit_price;

            loop {
                if domain.len() == 0 {
                    break;
                }
                let _domain = domain.pop_front().expect('pop_front error');
                let _renewer = renewer.pop_front().expect('pop_front error');
                let _limit_price = limit_price.pop_front().expect('pop_front error');
                self._renew(_domain, _renewer, _limit_price);
            }
        }
    }

    //
    // Internals
    //

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _renew(
            ref self: ContractState,
            root_domain: felt252,
            renewer: ContractAddress,
            limit_price: u256,
        ) {
            let naming = self.naming_contract.read();
            let can_renew = self._is_renewing.read((renewer, root_domain, limit_price));
            assert(can_renew == 1, 'Renewal not toggled for domain');

            // Check domain has not been renew yet this year
            let block_timestamp = get_block_timestamp();
            let last_renewed = self.last_renewal.read((renewer, root_domain));
            assert(block_timestamp - last_renewed > 86400_u64 * 364_u64, 'Domain already renewed');

            // Check domain is set to expire within a month
            let mut domain_arr = ArrayTrait::<felt252>::new();
            let block_timestamp2 = get_block_timestamp();
            domain_arr.append(root_domain);
            let expiry: u64 = u64_try_from_felt252(
                INamingDispatcher { contract_address: naming }.domain_to_expiry(domain_arr)
            )
                .expect('error converting to u64');
            assert(expiry <= block_timestamp2 + (86400_u64 * 30_u64), 'Domain not set to expire');

            // Renew domain
            let contract = get_contract_address();
            let erc20 = self.erc20_contract.read();
            IERC20Dispatcher {
                contract_address: erc20
            }.transferFrom(renewer, contract, limit_price);
            IERC20Dispatcher { contract_address: erc20 }.approve(naming, limit_price);
            INamingDispatcher { contract_address: naming }.renew(root_domain, 365, 0);
            IERC20Dispatcher { contract_address: erc20 }.approve(naming, 0.into());

            self.last_renewal.write((renewer, root_domain), block_timestamp);

            self
                .emit(
                    Event::domain_renewed(
                        domain_renewed {
                            domain: root_domain,
                            renewer,
                            days: 365,
                            limit_price,
                            timestamp: block_timestamp
                        }
                    )
                )
        }
    }
}
