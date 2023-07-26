#[starknet::interface]
trait IAutoRenewal<TContractState> {
    fn is_renewing(
        self: @TContractState,
        domain: felt252,
        renewer: starknet::ContractAddress,
        limit_price: u256
    ) -> felt252;

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
    use integer::u256_from_felt252;
    use debug::PrintTrait;

    use auto_renew_contract::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use auto_renew_contract::interfaces::naming::{INamingDispatcher, INamingDispatcherTrait};
    use auto_renew_contract::interfaces::pricing::{IPricingDispatcher, IPricingDispatcherTrait};

    #[storage]
    struct Storage {
        naming_contract: ContractAddress,
        pricing_contract: ContractAddress,
        // (renewer, domain, limit_price) -> 1 or 0
        _is_renewing: LegacyMap::<(ContractAddress, felt252, u256), felt252>,
        // (renewer, domain) -> timestamp
        last_renewal: LegacyMap::<(ContractAddress, felt252), felt252>,
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
        is_renewing: felt252,
        last_renewal: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct domain_renewed {
        domain: felt252,
        renewer: ContractAddress,
        days: felt252,
        limit_price: u256,
        timestamp: felt252,
    }

    //
    // Constructor
    //

    #[constructor]
    fn constructor(
        ref self: ContractState,
        naming_address: ContractAddress,
        pricing_address: ContractAddress,
        erc20_address: ContractAddress
    ) {
        self.naming_contract.write(naming_address);
        self.pricing_contract.write(pricing_address);

        // approve naming contract to transfer tokens
        let max: u256 = integer::BoundedInt::max();
        IERC20Dispatcher { contract_address: erc20_address }.approve(naming_address, max);
    }

    #[external(v0)]
    impl AutoRenewalImpl of super::IAutoRenewal<ContractState> {
        fn is_renewing(
            self: @ContractState, domain: felt252, renewer: ContractAddress, limit_price: u256
        ) -> felt252 {
            self._is_renewing.read((renewer, domain, limit_price))
        }

        fn get_contracts(self: @ContractState) -> (ContractAddress, ContractAddress) {
            (self.naming_contract.read(), self.pricing_contract.read())
        }

        fn toggle_renewals(ref self: ContractState, domain: felt252, limit_price: u256) {
            let caller = get_caller_address();
            let prev_renew = self._is_renewing.read((caller, domain, limit_price));
            self._is_renewing.write((caller, domain, limit_price), 1 - prev_renew);

            let _last_renewal = self.last_renewal.read((caller, domain));
            self.last_renewal.write((caller, domain), _last_renewal * prev_renew);

            self
                .emit(
                    Event::toggled_renewal(
                        toggled_renewal {
                            domain,
                            renewer: caller,
                            limit_price,
                            is_renewing: 1 - prev_renew,
                            last_renewal: _last_renewal * prev_renew
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
            let block_timestamp: felt252 = get_block_timestamp().into();
            let last_renewed = self.last_renewal.read((renewer, root_domain));
            let elapsed: u256 = u256_from_felt252(block_timestamp - last_renewed);
            let max = u256_from_felt252(86400 * 364);
            assert(elapsed > max, 'Domain already renewed');

            // Check domain is set to expire within a month
            let mut domain_arr = ArrayTrait::<felt252>::new();
            domain_arr.append(root_domain);
            let expiry = INamingDispatcher {
                contract_address: naming
            }.domain_to_expiry(domain_arr);
            assert(
                u256_from_felt252(expiry) <= u256_from_felt252(block_timestamp)
                    + u256_from_felt252(86400 * 30),
                'Domain not set to expire'
            );

            // Check renew price for domain is lower or equal to limit price
            let pricing = self.pricing_contract.read();
            let (erc20, renewal_price) = IPricingDispatcher {
                contract_address: pricing
            }.compute_renew_price(root_domain, 365);
            assert(renewal_price <= limit_price, 'Renewal price > limit price');

            // Renew domain
            let contract = get_contract_address();
            IERC20Dispatcher {
                contract_address: erc20
            }.transferFrom(renewer, contract, renewal_price);
            INamingDispatcher { contract_address: naming }.renew(root_domain, 365);

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
