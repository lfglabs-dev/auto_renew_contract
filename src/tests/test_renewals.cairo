use array::ArrayTrait;
use result::ResultTrait;
use traits::Into;
use option::OptionTrait;
use debug::PrintTrait;
use starknet::{testing, ContractAddress, contract_address_const};

use super::utils;
use super::common::deploy_contracts;
use super::constants::{
    OTHER, ADMIN, ZERO, BLOCK_TIMESTAMP, BLOCK_TIMESTAMP_ADD, TH0RGAL_DOMAIN, OTHER_DOMAIN,
    BLOCK_TIMESTAMP_EXPIRED
};

use super::mocks::identity::Identity;
use super::mocks::identity::{IIdentityDispatcher, IIdentityDispatcherTrait};
use super::mocks::erc20::ERC20;
use openzeppelin::token::erc20::interface::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait};
use naming::naming::main::Naming;
use naming::interface::naming::{INamingDispatcher, INamingDispatcherTrait};
use naming::pricing::Pricing;
use naming::interface::pricing::{IPricingDispatcher, IPricingDispatcherTrait};
use auto_renew_contract::auto_renewal::{
    AutoRenewal, IAutoRenewal, IAutoRenewalDispatcher, IAutoRenewalDispatcherTrait,
};
use auto_renew_contract::auto_renewal::AutoRenewal::{ContractState as AutoRenewalContractState,};

#[test]
#[available_gas(20000000)]
fn test_toggle_renewal() {
    // initialize contracts
    let (erc20, pricing, starknetid, naming, autorenewal) = deploy_contracts();

    // buy TH0RGAL_DOMAIN
    testing::set_contract_address(ADMIN());
    let token_id: u128 = 1;
    let (_, price) = pricing.compute_buy_price(7, 365);
    erc20.approve(naming.contract_address, price);
    starknetid.mint(token_id);
    naming.buy(token_id, TH0RGAL_DOMAIN(), 365_u16, ZERO(), ZERO(), 0, 0);

    // Should test autorenewal has been toggled for TH0RGAL_DOMAIN by USER() for limit_price
    let limit_price: u256 = 600.into();
    autorenewal.enable_renewals(TH0RGAL_DOMAIN(), limit_price, 0);
    let renew = autorenewal.is_renewing(TH0RGAL_DOMAIN(), ADMIN(), limit_price);
    assert(renew == 1, 'renew should be true');

    // Should test autorenewal has been untoggled for OTHER_DOMAIN by USER() for limit_price
    autorenewal.disable_renewals(TH0RGAL_DOMAIN(), limit_price);
    let renew = autorenewal.is_renewing(TH0RGAL_DOMAIN(), ADMIN(), limit_price);
    assert(renew == 0, 'renew should be false');
}

#[test]
#[available_gas(20000000)]
fn test_renew_domain() {
    // initialize contracts
    let (erc20, pricing, starknetid, naming, autorenewal) = deploy_contracts();
    testing::set_block_timestamp(BLOCK_TIMESTAMP());
    let token_id: u128 = 1;

    // buy TH0RGAL_DOMAIN for a year
    testing::set_contract_address(ADMIN());
    let (_, price) = pricing.compute_buy_price(7, 365);
    erc20.approve(naming.contract_address, price);
    starknetid.mint(token_id);
    naming.buy(token_id, TH0RGAL_DOMAIN(), 365_u16, ZERO(), ZERO(), 0, 0);

    testing::set_block_timestamp(BLOCK_TIMESTAMP_ADD());

    // Toggle renewal & approve ERC20 transfer
    autorenewal.enable_renewals(TH0RGAL_DOMAIN(), price, 0);
    erc20.approve(autorenewal.contract_address, integer::BoundedInt::max());

    // Should test renewing TH0RGAL_DOMAIN for a year
    let expiry = naming.domain_to_data(array![TH0RGAL_DOMAIN()].span()).expiry;
    assert(expiry == (86400 * 365) + BLOCK_TIMESTAMP().into(), 'expiry should be 365 days');

    autorenewal.renew(TH0RGAL_DOMAIN(), ADMIN(), price, 0, 0);

    let new_expiry = naming.domain_to_data(array![TH0RGAL_DOMAIN()].span()).expiry;
    let limit: u256 = ((86400 * 345) + BLOCK_TIMESTAMP_ADD().into()).into();
    assert(new_expiry.into() >= limit, 'new expiry should be 365 days');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Renewal not toggled for domain', 'ENTRYPOINT_FAILED',))]
fn test_renew_fail_not_toggled() {
    // initialize contracts
    let (erc20, pricing, starknetid, naming, autorenewal) = deploy_contracts();
    let token_id: u128 = 1;

    // buy TH0RGAL_DOMAIN for a year
    testing::set_contract_address(ADMIN());
    let (_, price) = pricing.compute_buy_price(7, 365);
    erc20.approve(naming.contract_address, price);
    starknetid.mint(token_id);
    naming.buy(token_id, TH0RGAL_DOMAIN(), 365_u16, ZERO(), ZERO(), 0, 0);

    // Should revert because ADMIN() has not toggled renewals for TH0RGAL_DOMAIN
    autorenewal.renew(TH0RGAL_DOMAIN(), ADMIN(), price, 0, 0);
}

#[test]
#[available_gas(20000000)]
#[should_panic(
    expected: ('u256_sub Overflow', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED')
)]
fn test_renew_fail_wrong_limit_price() {
    // initialize contracts
    let (erc20, pricing, starknetid, naming, autorenewal) = deploy_contracts();
    let token_id: u128 = 1;
    testing::set_block_timestamp(BLOCK_TIMESTAMP());

    // buy TH0RGAL_DOMAIN for a year
    testing::set_contract_address(ADMIN());
    let (_, price) = pricing.compute_buy_price(7, 365);
    erc20.approve(naming.contract_address, price);
    starknetid.mint(token_id);
    naming.buy(token_id, TH0RGAL_DOMAIN(), 365_u16, ZERO(), ZERO(), 0, 0);

    testing::set_block_timestamp(BLOCK_TIMESTAMP_ADD());

    // Toggle renewal for a limit_price
    let lower_price: u256 = 300.into();
    autorenewal.enable_renewals(TH0RGAL_DOMAIN(), lower_price, 0);
    erc20.approve(autorenewal.contract_address, integer::BoundedInt::max());

    // Should revert because price of renewing domain is higher than limit price
    autorenewal.renew(TH0RGAL_DOMAIN(), ADMIN(), lower_price, 0, 0);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Domain already renewed', 'ENTRYPOINT_FAILED',))]
fn test_renew_fail_expiry() {
    // initialize contracts
    let (erc20, pricing, starknetid, naming, autorenewal) = deploy_contracts();
    let token_id: u128 = 1;
    testing::set_block_timestamp(BLOCK_TIMESTAMP());

    // buy TH0RGAL_DOMAIN
    testing::set_contract_address(ADMIN());
    let (_, price) = pricing.compute_buy_price(7, 365);
    erc20.approve(naming.contract_address, price);
    starknetid.mint(token_id);
    naming.buy(token_id, TH0RGAL_DOMAIN(), 365_u16, ZERO(), ZERO(), 0, 0);

    autorenewal.enable_renewals(TH0RGAL_DOMAIN(), price, 0);
    erc20.approve(autorenewal.contract_address, integer::BoundedInt::max());

    // Should revert because TH0RGAL_DOMAIN will not expire within a month
    autorenewal.renew(TH0RGAL_DOMAIN(), ADMIN(), price, 0, 0);
}

#[test]
#[available_gas(20000000)]
fn test_renew_expired_domain() {
    // initialize contracts
    let (erc20, pricing, starknetid, naming, autorenewal) = deploy_contracts();
    let token_id: u128 = 1;

    testing::set_block_timestamp(BLOCK_TIMESTAMP());

    // buy TH0RGAL_DOMAIN
    testing::set_contract_address(ADMIN());
    let (_, price) = pricing.compute_buy_price(7, 365);
    erc20.approve(naming.contract_address, price);
    starknetid.mint(token_id);
    naming.buy(token_id, TH0RGAL_DOMAIN(), 365_u16, ZERO(), ZERO(), 0, 0);

    // Toggle renewal & approve ERC20 transfer
    autorenewal.enable_renewals(TH0RGAL_DOMAIN(), price, 0);
    erc20.approve(autorenewal.contract_address, integer::BoundedInt::max());

    // Advance time and assert domain is expired
    testing::set_block_timestamp(BLOCK_TIMESTAMP_EXPIRED());
    let expiry: u256 = naming.domain_to_data(array![TH0RGAL_DOMAIN()].span()).expiry.into();
    assert(expiry < BLOCK_TIMESTAMP_EXPIRED().into(), 'domain should be expired');

    // Should renew TH0RGAL_DOMAIN for a year even if it is expired
    autorenewal.renew(TH0RGAL_DOMAIN(), ADMIN(), price, 0, 0);
    let new_expiry = naming.domain_to_data(array![TH0RGAL_DOMAIN()].span()).expiry;
    let limit: u256 = ((86400 * 345) + BLOCK_TIMESTAMP_EXPIRED().into()).into();
    assert(new_expiry.into() >= limit, 'new expiry should be 365 days');
}

#[test]
#[available_gas(20000000)]
fn test_renew_domains() {
    // initialize contracts
    let (erc20, pricing, starknetid, naming, autorenewal) = deploy_contracts();
    let token_id: u128 = 1;
    let token_id2: u128 = 2;

    testing::set_block_timestamp(BLOCK_TIMESTAMP());

    // buy TH0RGAL_DOMAIN & OTHER_DOMAIN
    testing::set_contract_address(ADMIN());
    let (_, price) = pricing.compute_buy_price(7, 365);
    erc20.approve(naming.contract_address, price * 2);
    starknetid.mint(token_id);
    starknetid.mint(token_id2);
    naming.buy(token_id, TH0RGAL_DOMAIN(), 365_u16, ZERO(), ZERO(), 0, 0);
    naming.buy(token_id2, OTHER_DOMAIN(), 365_u16, ZERO(), ZERO(), 0, 0);
    autorenewal.enable_renewals(TH0RGAL_DOMAIN(), price, 0);
    autorenewal.enable_renewals(OTHER_DOMAIN(), price, 0);
    erc20.approve(autorenewal.contract_address, integer::BoundedInt::max());
    // Should renew both domains for a year
    testing::set_block_timestamp(BLOCK_TIMESTAMP_ADD());

    autorenewal
        .batch_renew(
            array![TH0RGAL_DOMAIN(), OTHER_DOMAIN()].span(),
            array![ADMIN(), ADMIN()].span(),
            array![price, price].span(),
            array![0, 0].span(),
            array![0, 0].span()
        );

    let limit: u256 = ((86400 * 345) + BLOCK_TIMESTAMP_ADD().into()).into();
    let expiry = naming.domain_to_data(array![TH0RGAL_DOMAIN()].span()).expiry;
    assert(expiry.into() >= limit, 'new expiry should be 365 days');
    let expiry = naming.domain_to_data(array![OTHER_DOMAIN()].span()).expiry;
    assert(expiry.into() >= limit, 'new expiry should be 365 days');
}

#[test]
#[available_gas(20000000)]
fn test_renew_with_metadata() {
    // initialize contracts
    let (erc20, pricing, starknetid, naming, autorenewal) = deploy_contracts();
    let tax_contract = contract_address_const::<0x111>();
    let token_id: u128 = 1;
    let metadata = 222222;
    let tax_price: u256 = 100;
    testing::set_block_timestamp(BLOCK_TIMESTAMP());

    // buy TH0RGAL_DOMAIN & OTHER_DOMAIN
    testing::set_contract_address(ADMIN());
    let (_, price) = pricing.compute_buy_price(7, 365);
    erc20.approve(naming.contract_address, price);
    starknetid.mint(token_id);
    naming.buy(token_id, TH0RGAL_DOMAIN(), 365_u16, ZERO(), ZERO(), 0, metadata);

    autorenewal.enable_renewals(TH0RGAL_DOMAIN(), price, metadata);
    erc20.approve(autorenewal.contract_address, integer::BoundedInt::max());

    testing::set_block_timestamp(BLOCK_TIMESTAMP_ADD());

    // Should renew domain & send tax price to tax contract
    autorenewal.renew(TH0RGAL_DOMAIN(), ADMIN(), price, tax_price, metadata);
    let tax_balance = erc20.balance_of(tax_contract);
    assert(tax_balance == tax_price, 'tax balance should be 100');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller not admin', 'ENTRYPOINT_FAILED',))]
fn test_update_tax_addr_fail() {
    // initialize contracts
    let (erc20, pricing, starknetid, naming, autorenewal) = deploy_contracts();

    // Should revert because OTHER() is not admin
    testing::set_contract_address(OTHER());
    autorenewal.update_tax_contract(OTHER());
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller not admin', 'ENTRYPOINT_FAILED',))]
fn test_toggle_off_contract_fail() {
    // initialize contracts
    let (erc20, pricing, starknetid, naming, autorenewal) = deploy_contracts();

    // Should revert because OTHER() is not admin
    testing::set_contract_address(OTHER());
    autorenewal.toggle_off();
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Contract is disabled', 'ENTRYPOINT_FAILED',))]
fn test_renew_disabled_contract_fails() {
    // initialize contracts
    let (erc20, pricing, starknetid, naming, autorenewal) = deploy_contracts();
    testing::set_block_timestamp(BLOCK_TIMESTAMP());
    let token_id: u128 = 1;

    testing::set_contract_address(ADMIN());
    // buy TH0RGAL_DOMAIN for a year
    testing::set_contract_address(ADMIN());
    let (_, price) = pricing.compute_buy_price(7, 365);
    erc20.approve(naming.contract_address, price);
    starknetid.mint(token_id);
    naming.buy(token_id, TH0RGAL_DOMAIN(), 365_u16, ZERO(), ZERO(), 0, 0);

    testing::set_block_timestamp(BLOCK_TIMESTAMP_ADD());

    // Toggle renewal & approve ERC20 transfer
    autorenewal.enable_renewals(TH0RGAL_DOMAIN(), price, 0);
    erc20.approve(autorenewal.contract_address, integer::BoundedInt::max());

    autorenewal.toggle_off();

    autorenewal.renew(TH0RGAL_DOMAIN(), ADMIN(), price, 0, 0);
}
