#[starknet::interface]
trait IAutoRenewal<TContractState> {
    fn get_renewing_allowance(
        self: @TContractState, domain: felt252, renewer: starknet::ContractAddress,
    ) -> u256;

    fn get_contracts(
        self: @TContractState
    ) -> (starknet::ContractAddress, starknet::ContractAddress, starknet::ContractAddress);

    fn enable_renewals(
        ref self: TContractState, domain: felt252, allowance: u256, meta_hash: felt252
    );
    fn disable_renewals(ref self: TContractState, domain: felt252);

    fn renew(
        ref self: TContractState,
        root_domain: felt252,
        renewer: starknet::ContractAddress,
        domain_price: u256,
        tax_price: u256,
        metadata: felt252,
    );

    fn batch_renew(
        ref self: TContractState,
        domains: array::Span::<felt252>,
        renewers: array::Span::<starknet::ContractAddress>,
        domain_prices: array::Span::<u256>,
        tax_prices: array::Span::<u256>,
        metadatas: array::Span::<felt252>,
    );

    fn start_admin_update(ref self: TContractState, new_admin: starknet::ContractAddress,);
    fn confirm_admin_update(ref self: TContractState);
    fn update_tax_contract(ref self: TContractState, new_addr: starknet::ContractAddress,);
    fn update_whitelisted_renewer(
        ref self: TContractState, whitelisted_renewer: starknet::ContractAddress
    );
    fn toggle_off(ref self: TContractState);
    fn claim(ref self: TContractState, amount: u256);
}

#[starknet::contract]
mod AutoRenewal {
    use starknet::ContractAddress;
    use starknet::{get_caller_address, get_contract_address, get_block_timestamp};
    use starknet::contract_address::ContractAddressZeroable;
    use array::ArrayTrait;
    use openzeppelin::token::erc20::interface::{IERC20CamelDispatcher, IERC20CamelDispatcherTrait};
    use naming::interface::naming::{INamingDispatcher, INamingDispatcherTrait};

    #[storage]
    struct Storage {
        naming_contract: ContractAddress,
        erc20_contract: ContractAddress,
        tax_contract: ContractAddress,
        admin: ContractAddress,
        temp_admin: ContractAddress,
        whitelisted_renewer: ContractAddress,
        can_renew: bool,
        // (renewer, domain) -> limit_price
        renewing_allowance: LegacyMap::<(ContractAddress, felt252), u256>,
        // (renewer, domain) -> timestamp
        last_renewal: LegacyMap::<(ContractAddress, felt252), u64>,
    }

    //
    // Events
    //

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        UpdatedRenewal: UpdatedRenewal,
        DisabledRenewal: DisabledRenewal,
        DomainRenewed: DomainRenewed,
        OnDeployment: OnDeployment,
        OnAdminUpdate: OnAdminUpdate,
        OnTaxContractUpdate: OnTaxContractUpdate,
        OnWhitelistedRenewerUpdate: OnWhitelistedRenewerUpdate,
        OnToggleOff: OnToggleOff,
        OnClaim: OnClaim,
    }

    // regarding renewals

    #[derive(Drop, starknet::Event)]
    struct UpdatedRenewal {
        #[key]
        domain: felt252,
        renewer: ContractAddress,
        allowance: u256,
        meta_hash: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct DisabledRenewal {
        #[key]
        domain: felt252,
        renewer: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct DomainRenewed {
        #[key]
        domain: felt252,
        renewer: ContractAddress,
        days: felt252,
        domain_price: u256,
        tax_price: u256,
        metadata: felt252,
        timestamp: u64,
    }

    // misc events

    #[derive(Drop, starknet::Event)]
    struct OnDeployment {
        naming_addr: ContractAddress,
        erc20_addr: ContractAddress,
        tax_addr: ContractAddress,
        admin_addr: ContractAddress,
        whitelisted_renewer: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct OnAdminUpdate {
        new_admin: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct OnTaxContractUpdate {
        new_tax_contract: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct OnWhitelistedRenewerUpdate {
        new_whitelisted_renewer: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct OnToggleOff {}

    #[derive(Drop, starknet::Event)]
    struct OnClaim {
        claimer: ContractAddress,
        erc20: ContractAddress,
        amount: u256
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
        // allowing naming 2^256-1, aka infinite approval according to its implementation
        // when moving funds, the storage variable won't be updated, saving gas
        IERC20CamelDispatcher { contract_address: erc20_addr }
            .approve(naming_addr, integer::BoundedInt::max());
        self
            .emit(
                Event::OnDeployment(
                    OnDeployment {
                        naming_addr, erc20_addr, tax_addr, admin_addr, whitelisted_renewer
                    }
                )
            );
    }

    #[external(v0)]
    impl AutoRenewalImpl of super::IAutoRenewal<ContractState> {
        fn get_renewing_allowance(
            self: @ContractState, domain: felt252, renewer: ContractAddress
        ) -> u256 {
            self.renewing_allowance.read((renewer, domain))
        }

        fn get_contracts(
            self: @ContractState
        ) -> (ContractAddress, ContractAddress, ContractAddress) {
            (self.naming_contract.read(), self.erc20_contract.read(), self.tax_contract.read())
        }

        fn enable_renewals(
            ref self: ContractState, domain: felt252, allowance: u256, meta_hash: felt252
        ) {
            let caller = get_caller_address();
            self.renewing_allowance.write((caller, domain), allowance);

            // we erase the previous renewal date
            self.last_renewal.write((caller, domain), 0);

            self
                .emit(
                    Event::UpdatedRenewal(
                        UpdatedRenewal { domain, renewer: caller, allowance, meta_hash }
                    )
                )
        }

        fn disable_renewals(ref self: ContractState, domain: felt252) {
            let caller = get_caller_address();
            self.renewing_allowance.write((caller, domain), 0);

            self.emit(Event::DisabledRenewal(DisabledRenewal { domain, renewer: caller, }))
        }

        fn renew(
            ref self: ContractState,
            root_domain: felt252,
            renewer: ContractAddress,
            domain_price: u256,
            tax_price: u256,
            metadata: felt252,
        ) {
            assert(self.can_renew.read(), 'Contract is disabled');
            assert(
                get_caller_address() == self.whitelisted_renewer.read(), 'You are not whitelisted'
            );
            self._renew(root_domain, renewer, domain_price, tax_price, metadata);
        }

        fn batch_renew(
            ref self: ContractState,
            domains: array::Span::<felt252>,
            renewers: array::Span::<starknet::ContractAddress>,
            domain_prices: array::Span::<u256>,
            tax_prices: array::Span::<u256>,
            metadatas: array::Span::<felt252>,
        ) {
            assert(self.can_renew.read(), 'Contract is disabled');
            assert(
                get_caller_address() == self.whitelisted_renewer.read(), 'You are not whitelisted'
            );
            assert(domains.len() == renewers.len(), 'Domain & renewers mismatch len');
            assert(domains.len() == domain_prices.len(), 'Domain & prices mismatch len');
            assert(domains.len() == tax_prices.len(), 'Domain & taxes mismatch len');
            assert(domains.len() == metadatas.len(), 'Domain & metadatas mismatch len');

            let mut domains = domains;
            let mut renewers = renewers;
            let mut domain_prices = domain_prices;
            let mut tax_prices = tax_prices;
            let mut metadatas = metadatas;

            loop {
                if domains.len() == 0 {
                    break;
                }
                let domain = domains.pop_front().unwrap();
                let renewer = renewers.pop_front().unwrap();
                let domain_price = domain_prices.pop_front().unwrap();
                let tax_price = tax_prices.pop_front().unwrap();
                let metadata = metadatas.pop_front().unwrap();
                self._renew(*domain, *renewer, *domain_price, *tax_price, *metadata);
            }
        }

        // Admin function to update admin address and the tax contract address
        fn start_admin_update(ref self: ContractState, new_admin: ContractAddress,) {
            assert(get_caller_address() == self.admin.read(), 'Caller not admin');
            self.temp_admin.write(new_admin);
        }

        fn confirm_admin_update(ref self: ContractState) {
            let temp_admin = self.temp_admin.read();
            assert(get_caller_address() == temp_admin, 'Caller not temp_admin');
            self.admin.write(temp_admin);
            self.emit(Event::OnAdminUpdate(OnAdminUpdate { new_admin: temp_admin }));
        }

        fn update_tax_contract(ref self: ContractState, new_addr: ContractAddress,) {
            assert(get_caller_address() == self.admin.read(), 'Caller not admin');
            self.tax_contract.write(new_addr);
            self
                .emit(
                    Event::OnTaxContractUpdate(OnTaxContractUpdate { new_tax_contract: new_addr })
                );
        }

        fn update_whitelisted_renewer(
            ref self: ContractState, whitelisted_renewer: starknet::ContractAddress
        ) {
            assert(get_caller_address() == self.admin.read(), 'Caller not admin');
            self.whitelisted_renewer.write(whitelisted_renewer);
            self
                .emit(
                    Event::OnWhitelistedRenewerUpdate(
                        OnWhitelistedRenewerUpdate { new_whitelisted_renewer: whitelisted_renewer }
                    )
                );
        }

        fn toggle_off(ref self: ContractState) {
            assert(get_caller_address() == self.admin.read(), 'Caller not admin');
            self.can_renew.write(false);
            self.emit(Event::OnToggleOff(OnToggleOff {}));
        }

        fn claim(ref self: ContractState, amount: u256) {
            let claimer = get_caller_address();
            assert(claimer == self.admin.read(), 'Caller not admin');
            let erc20 = self.erc20_contract.read();
            IERC20CamelDispatcher { contract_address: erc20 }.transfer(claimer, amount);
            self.emit(Event::OnClaim(OnClaim { claimer, erc20, amount }));
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
            domain_price: u256,
            tax_price: u256,
            metadata: felt252,
        ) {
            let naming = self.naming_contract.read();
            let limit_price = self.renewing_allowance.read((renewer, root_domain));
            let total_price = domain_price + tax_price;
            // We keep the ability to specify a domain_price inferior to the limit price
            // in case we lowered the prices of stark domains and don't want to debit
            // users more than they need even though they allowed us to do so.
            assert(limit_price >= domain_price, 'Renewal allowance insufficient');

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
            // events is sent before calls to other contracts to prevent a reordering via reentrancy attack
            self
                .emit(
                    Event::DomainRenewed(
                        DomainRenewed {
                            domain: root_domain,
                            renewer,
                            days: 365,
                            domain_price,
                            tax_price,
                            metadata,
                            timestamp: block_timestamp
                        }
                    )
                );
            let contract = get_contract_address();
            let erc20 = self.erc20_contract.read();
            let _tax_contract = self.tax_contract.read();

            // Transfer limit_price (including tax), will be canceled if the tx fails
            IERC20CamelDispatcher { contract_address: erc20 }
                .transferFrom(renewer, contract, total_price);
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
