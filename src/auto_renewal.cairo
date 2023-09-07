#[starknet::interface]
trait IAutoRenewal<TContractState> {
    fn is_renewing(
        self: @TContractState,
        domain: felt252,
        renewer: starknet::ContractAddress,
        limit_price: u256
    ) -> bool;

    fn get_contracts(
        self: @TContractState
    ) -> (starknet::ContractAddress, starknet::ContractAddress, starknet::ContractAddress);

    fn enable_renewals(
        ref self: TContractState, domain: felt252, limit_price: u256, meta_hash: felt252
    );
    fn disable_renewals(ref self: TContractState, domain: felt252, limit_price: u256);

    fn renew(
        ref self: TContractState,
        root_domain: felt252,
        renewer: starknet::ContractAddress,
        limit_price: u256,
        tax_price: u256,
        metadata: felt252,
    );

    fn batch_renew(
        ref self: TContractState,
        domain: array::Span::<felt252>,
        renewer: array::Span::<starknet::ContractAddress>,
        limit_price: array::Span::<u256>,
        tax_price: array::Span::<u256>,
        metadata: array::Span::<felt252>,
    );

    fn update_admin(ref self: TContractState, new_admin: starknet::ContractAddress,);
    fn update_tax_contract(ref self: TContractState, new_addr: starknet::ContractAddress,);
    fn toggle_off(ref self: TContractState);
}

#[starknet::contract]
mod AutoRenewal {
    use starknet::ContractAddress;
    use starknet::{get_caller_address, get_contract_address, get_block_timestamp};
    use starknet::contract_address::ContractAddressZeroable;
    use traits::{TryInto, Into};
    use option::OptionTrait;
    use array::ArrayTrait;
    use integer::u64_try_from_felt252;

    use debug::PrintTrait;

    use openzeppelin::token::erc20::interface::{IERC20CamelDispatcher, IERC20CamelDispatcherTrait};
    use naming::interface::naming::{INamingDispatcher, INamingDispatcherTrait};

    #[storage]
    struct Storage {
        naming_contract: ContractAddress,
        erc20_contract: ContractAddress,
        tax_contract: ContractAddress,
        admin: ContractAddress,
        whitelisted_renewer: ContractAddress,
        can_renew: bool,
        // (renewer, domain, limit_price) -> 1 or 0
        _is_renewing: LegacyMap::<(ContractAddress, felt252, u256), bool>,
        // (renewer, domain) -> timestamp
        last_renewal: LegacyMap::<(ContractAddress, felt252), u64>,
    }

    //
    // Events
    //

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        EnabledRenewal: EnabledRenewal,
        DisabledRenewal: DisabledRenewal,
        DomainRenewed: DomainRenewed,
    }

    #[derive(Drop, starknet::Event)]
    struct EnabledRenewal {
        #[key]
        domain: felt252,
        renewer: ContractAddress,
        limit_price: u256,
        meta_hash: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct DisabledRenewal {
        #[key]
        domain: felt252,
        renewer: ContractAddress,
        limit_price: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct DomainRenewed {
        #[key]
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
        ref self: ContractState,
        naming_addr: ContractAddress,
        erc20_addr: ContractAddress,
        tax_addr: ContractAddress,
        admin_addr: ContractAddress,
        whitelisted_renewer: ContractAddress
    ) {
        self.naming_contract.write(naming_addr);
        self.erc20_contract.write(erc20_addr);
        self.tax_contract.write(tax_addr);
        self.admin.write(admin_addr);
        self.whitelisted_renewer.write(whitelisted_renewer);
        self.can_renew.write(true);
        // allowing naming 2^251-1, aka infinite approval according to its implementation
        // when moving funds, the storage variable won't be updated, saving gas
        IERC20CamelDispatcher { contract_address: erc20_addr }
            .approve(
                naming_addr, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
            );
    }

    #[external(v0)]
    impl AutoRenewalImpl of super::IAutoRenewal<ContractState> {
        fn is_renewing(
            self: @ContractState, domain: felt252, renewer: ContractAddress, limit_price: u256
        ) -> bool {
            self._is_renewing.read((renewer, domain, limit_price))
        }

        fn get_contracts(
            self: @ContractState
        ) -> (ContractAddress, ContractAddress, ContractAddress) {
            (self.naming_contract.read(), self.erc20_contract.read(), self.tax_contract.read())
        }

        fn enable_renewals(
            ref self: ContractState, domain: felt252, limit_price: u256, meta_hash: felt252
        ) {
            let caller = get_caller_address();
            self._is_renewing.write((caller, domain, limit_price), true);

            // we erase the previous renewal date
            self.last_renewal.write((caller, domain), 0);

            self
                .emit(
                    Event::EnabledRenewal(
                        EnabledRenewal { domain, renewer: caller, limit_price, meta_hash }
                    )
                )
        }

        // limit_price can be found via the EnabledRenewal events
        fn disable_renewals(ref self: ContractState, domain: felt252, limit_price: u256) {
            let caller = get_caller_address();
            self._is_renewing.write((caller, domain, limit_price), false);

            self
                .emit(
                    Event::DisabledRenewal(
                        DisabledRenewal { domain, renewer: caller, limit_price, }
                    )
                )
        }

        fn renew(
            ref self: ContractState,
            root_domain: felt252,
            renewer: ContractAddress,
            limit_price: u256,
            tax_price: u256,
            metadata: felt252,
        ) {
            assert(self.can_renew.read(), 'Contract is disabled');
            assert(
                get_caller_address() == self.whitelisted_renewer.read(), 'You are not whitelisted'
            );
            self._renew(root_domain, renewer, limit_price, tax_price, metadata);
        }

        fn batch_renew(
            ref self: ContractState,
            domain: array::Span::<felt252>,
            renewer: array::Span::<starknet::ContractAddress>,
            limit_price: array::Span::<u256>,
            tax_price: array::Span::<u256>,
            metadata: array::Span::<felt252>,
        ) {
            assert(self.can_renew.read(), 'Contract is disabled');
            assert(
                get_caller_address() == self.whitelisted_renewer.read(), 'You are not whitelisted'
            );
            assert(domain.len() == renewer.len(), 'Domain & renewer mismatch len');
            assert(domain.len() == limit_price.len(), 'Domain & price mismatch len');

            let mut domain = domain;
            let mut renewer = renewer;
            let mut limit_price = limit_price;
            let mut tax_price = tax_price;
            let mut metadata = metadata;

            loop {
                if domain.len() == 0 {
                    break;
                }
                let _domain = domain.pop_front().expect('pop_front error');
                let _renewer = renewer.pop_front().expect('pop_front error');
                let _limit_price = limit_price.pop_front().expect('pop_front error');
                let _tax_price = tax_price.pop_front().expect('pop_front error');
                let _metadata = metadata.pop_front().expect('pop_front error');
                self._renew(*_domain, *_renewer, *_limit_price, *_tax_price, *_metadata);
            }
        }

        // Admin function to update admin address and the tax contract address
        fn update_admin(ref self: ContractState, new_admin: ContractAddress,) {
            assert(get_caller_address() == self.admin.read(), 'Caller not admin');
            self.admin.write(new_admin);
        }

        fn update_tax_contract(ref self: ContractState, new_addr: ContractAddress,) {
            assert(get_caller_address() == self.admin.read(), 'Caller not admin');
            self.admin.write(new_addr);
        }

        fn toggle_off(ref self: ContractState) {
            assert(get_caller_address() == self.admin.read(), 'Caller not admin');
            self.can_renew.write(false);
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
            tax_price: u256,
            metadata: felt252,
        ) {
            let naming = self.naming_contract.read();
            let can_renew = self._is_renewing.read((renewer, root_domain, limit_price));
            assert(can_renew, 'Renewal not toggled for domain');

            // Check domain has not been renew yet this year
            let block_timestamp = get_block_timestamp();
            let last_renewed = self.last_renewal.read((renewer, root_domain));
            // 364 because we keep adding one day margin to the existing month,
            // if we take more than a day to renew, the margin will shrink.
            assert(block_timestamp - last_renewed > 86400_u64 * 364_u64, 'Domain already renewed');

            // Check domain is set to expire within a month
            let expiry: u64 = INamingDispatcher { contract_address: naming }
                .domain_to_data(array![root_domain].span())
                .expiry;
            assert(expiry <= block_timestamp + (86400_u64 * 30_u64), 'Domain not set to expire');

            // Renew domain
            // last_renewal is updated before external contract calls to prevent reentrancy attacks
            // if the naming contract was compromised
            self.last_renewal.write((renewer, root_domain), block_timestamp);
            // events is sent before calls to other contracts a reordering via reentrancy attack
            self
                .emit(
                    Event::DomainRenewed(
                        DomainRenewed {
                            domain: root_domain,
                            renewer,
                            days: 365,
                            limit_price,
                            timestamp: block_timestamp
                        }
                    )
                );
            let contract = get_contract_address();
            let erc20 = self.erc20_contract.read();
            let _tax_contract = self.tax_contract.read();

            // Transfer limit_price (including tax), will be canceled if the tx fails
            IERC20CamelDispatcher { contract_address: erc20 }
                .transferFrom(renewer, contract, limit_price);
            // transfer tax price to tax contract address
            IERC20CamelDispatcher { contract_address: erc20 }.transfer(_tax_contract, tax_price);
            // spend the remaining money to renew the domain
            // if something remains after this, it can be considered as lost by the user,
            // we keep the ability to claim it back but can't guarantee we will do it
            INamingDispatcher { contract_address: naming }
                .renew(root_domain, 365_u16, ContractAddressZeroable::zero(), 0, metadata);
        }
    }
}
