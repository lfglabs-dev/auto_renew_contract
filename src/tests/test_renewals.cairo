use array::ArrayTrait;
use result::ResultTrait;
use traits::Into;
use option::OptionTrait;
use integer::u128_to_felt252;
use debug::PrintTrait;

use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::testing;

use auto_renew_contract::auto_renewal::{
    AutoRenewal, IAutoRenewal, IAutoRenewalDispatcher, IAutoRenewalDispatcherTrait,
};
use auto_renew_contract::auto_renewal::AutoRenewal::{ContractState as AutoRenewalContractState, };

use super::utils::{deploy, build_domain_arr};
use super::mocks::erc20::{ERC20, MockERC20ABIDispatcher, MockERC20ABIDispatcherTrait};
use super::mocks::starknetid::{
    StarknetID, MockStarknetIDABIDispatcher, MockStarknetIDABIDispatcherTrait
};
use super::mocks::pricing::{Pricing, MockPricingABIDispatcher, MockPricingABIDispatcherTrait};
use super::mocks::naming::{Naming, MockNamingABIDispatcher, MockNamingABIDispatcherTrait};
use super::constants::{OWNER, OTHER, USER, ZERO, BLOCK_TIMESTAMP, TH0RGAL_DOMAIN, OTHER_DOMAIN};

#[cfg(test)]
fn deploy_autorenewal(
    naming_addr: ContractAddress, pricing_addr: ContractAddress, erc20_addr: ContractAddress
) -> IAutoRenewalDispatcher {
    let mut calldata = ArrayTrait::<felt252>::new();
    calldata.append(naming_addr.into());
    calldata.append(pricing_addr.into());
    calldata.append(erc20_addr.into());

    let address = deploy(AutoRenewal::TEST_CLASS_HASH, calldata);
    IAutoRenewalDispatcher { contract_address: address }
}

#[cfg(test)]
fn deploy_erc20(recipient: ContractAddress, initial_supply: u256) -> MockERC20ABIDispatcher {
    let mut calldata = ArrayTrait::<felt252>::new();

    calldata.append(initial_supply.low.into());
    calldata.append(initial_supply.high.into());
    calldata.append(recipient.into());

    let address = deploy(ERC20::TEST_CLASS_HASH, calldata);
    MockERC20ABIDispatcher { contract_address: address }
}

#[cfg(test)]
fn deploy_starknetid() -> MockStarknetIDABIDispatcher {
    let address = deploy(StarknetID::TEST_CLASS_HASH, ArrayTrait::<felt252>::new());
    MockStarknetIDABIDispatcher { contract_address: address }
}

#[cfg(test)]
fn deploy_pricing(erc20_addr: ContractAddress) -> MockPricingABIDispatcher {
    let mut calldata = ArrayTrait::<felt252>::new();
    calldata.append(erc20_addr.into());

    let address = deploy(Pricing::TEST_CLASS_HASH, calldata);
    MockPricingABIDispatcher { contract_address: address }
}


#[cfg(test)]
fn deploy_naming(
    starknetid_addr: ContractAddress, pricing_addr: ContractAddress, erc20_addr: ContractAddress
) -> MockNamingABIDispatcher {
    let mut calldata = ArrayTrait::<felt252>::new();
    calldata.append(starknetid_addr.into());
    calldata.append(pricing_addr.into());
    calldata.append(erc20_addr.into());

    let address = deploy(Naming::TEST_CLASS_HASH, calldata);
    MockNamingABIDispatcher { contract_address: address }
}

#[cfg(test)]
fn send_eth(
    erc20: MockERC20ABIDispatcher, sender: ContractAddress, recipient: ContractAddress, amount: u256
) {
    testing::set_caller_address(sender);
    testing::set_contract_address(sender);
    erc20.approve(sender, amount);
    erc20.transfer_from(sender, recipient, amount);
}

#[cfg(test)]
fn setup() -> (
    MockERC20ABIDispatcher,
    MockPricingABIDispatcher,
    MockStarknetIDABIDispatcher,
    MockNamingABIDispatcher,
    IAutoRenewalDispatcher
) {
    let erc20 = deploy_erc20(OWNER(), 100000.into());
    let pricing = deploy_pricing(erc20.contract_address);
    let starknetid = deploy_starknetid();
    let naming = deploy_naming(
        starknetid.contract_address, pricing.contract_address, erc20.contract_address
    );
    let autorenewal = deploy_autorenewal(
        naming.contract_address, pricing.contract_address, erc20.contract_address
    );

    return (erc20, pricing, starknetid, naming, autorenewal);
}

#[cfg(test)]
fn buy_domain(
    erc20: MockERC20ABIDispatcher,
    starknetid: MockStarknetIDABIDispatcher,
    naming: MockNamingABIDispatcher,
    buyer: ContractAddress,
    token_id: felt252,
    domain: felt252,
    days: felt252,
) {
    testing::set_caller_address(buyer);
    testing::set_contract_address(buyer);
    erc20.approve(naming.contract_address, 500.into());
    starknetid.mint(token_id);
    naming.buy(token_id, domain, days, 0, buyer);
}

#[cfg(test)]
#[test]
#[available_gas(20000000)]
fn test_toggle_renewal() {
    // initialize contracts
    let (erc20, pricing, starknetid, naming, autorenewal) = setup();

    // send eth to USER() & buy TH0RGAL_DOMAIN
    send_eth(erc20, OWNER(), USER(), 1000.into());
    buy_domain(erc20, starknetid, naming, USER(), 1.into(), TH0RGAL_DOMAIN(), 365.into());

    let limit_price: u256 = 600.into();

    // Should test autorenewal has been toggled for TH0RGAL_DOMAIN by USER() for limit_price
    autorenewal.toggle_renewals(TH0RGAL_DOMAIN(), limit_price);
    let renew = autorenewal.is_renewing(TH0RGAL_DOMAIN(), USER(), limit_price);
    assert(renew == 1, 'renew should be true');

    // Should test autorenewal has been untoggled for OTHER_DOMAIN by USER() for limit_price
    autorenewal.toggle_renewals(TH0RGAL_DOMAIN(), limit_price);
    let renew = autorenewal.is_renewing(TH0RGAL_DOMAIN(), USER(), limit_price);
    assert(renew == 0, 'renew should be false');
}

#[cfg(test)]
#[test]
#[available_gas(20000000)]
fn test_renew_domain() {
    // initialize contracts
    let (erc20, pricing, starknetid, naming, autorenewal) = setup();

    // send eth to USER() & buy TH0RGAL_DOMAIN for 10 days
    send_eth(erc20, OWNER(), USER(), 1000.into());
    buy_domain(erc20, starknetid, naming, USER(), 1.into(), TH0RGAL_DOMAIN(), 10.into());

    // Toggle renewal & approve ERC20 transfer
    let limit_price: u256 = 600.into();
    autorenewal.toggle_renewals(TH0RGAL_DOMAIN(), limit_price);
    erc20.approve(autorenewal.contract_address, 600.into());

    // Should test renewing TH0RGAL_DOMAIN for a year
    let mut domain_arr = ArrayTrait::<felt252>::new();
    domain_arr.append(TH0RGAL_DOMAIN());
    let expiry = naming.domain_to_expiry(domain_arr);
    assert(expiry == 86400 * 10, 'expiry should be 10');

    autorenewal.renew(TH0RGAL_DOMAIN(), USER(), limit_price);

    let mut domain_arr = ArrayTrait::<felt252>::new();
    domain_arr.append(TH0RGAL_DOMAIN());
    let new_expiry = naming.domain_to_expiry(domain_arr);
    assert(new_expiry == 86400 * 365 + 86400 * 10, 'new expiry should be 375 days');
}

#[cfg(test)]
#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Renewal not toggled for domain', 'ENTRYPOINT_FAILED', ))]
fn test_renew_fail_not_toggled() {
    // initialize contracts
    let (erc20, pricing, starknetid, naming, autorenewal) = setup();

    // send eth to USER & buy TH0RGAL_DOMAIN
    send_eth(erc20, OWNER(), USER(), 1000.into());
    buy_domain(erc20, starknetid, naming, USER(), 1.into(), TH0RGAL_DOMAIN(), 365.into());

    // Should revert because USER has not toggled renewals for TH0RGAL_DOMAIN
    let limit_price: u256 = 600.into();
    autorenewal.renew(TH0RGAL_DOMAIN(), USER(), limit_price);
}

#[cfg(test)]
#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Renewal price > limit price', 'ENTRYPOINT_FAILED', ))]
fn test_renew_fail_wrong_limit_price() {
    // initialize contracts
    let (erc20, pricing, starknetid, naming, autorenewal) = setup();

    // send eth to USER & buy TH0RGAL_DOMAIN for 10 days
    send_eth(erc20, OWNER(), USER(), 1000.into());
    buy_domain(erc20, starknetid, naming, USER(), 1.into(), TH0RGAL_DOMAIN(), 10.into());

    // Toggle renewal for a limit_price
    let limit_price: u256 = 300.into();
    autorenewal.toggle_renewals(TH0RGAL_DOMAIN(), limit_price);
    erc20.approve(autorenewal.contract_address, limit_price);

    // Should revert because price of renewing domain (500) is higher than limit_price (300)
    autorenewal.renew(TH0RGAL_DOMAIN(), USER(), limit_price);
}

#[cfg(test)]
#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Domain not set to expire', 'ENTRYPOINT_FAILED', ))]
fn test_renew_fail_expiry() {
    // initialize contracts
    let (erc20, pricing, starknetid, naming, autorenewal) = setup();

    // send eth to USER & buy TH0RGAL_DOMAIN
    send_eth(erc20, OWNER(), USER(), 1000.into());
    buy_domain(erc20, starknetid, naming, USER(), 1.into(), TH0RGAL_DOMAIN(), 365.into());

    // toggle renewal for TH0RGAL_DOMAIN
    let limit_price: u256 = 600.into();
    autorenewal.toggle_renewals(TH0RGAL_DOMAIN(), limit_price);

    erc20.approve(autorenewal.contract_address, 600.into());
    autorenewal.renew(TH0RGAL_DOMAIN(), USER(), limit_price);
}

#[cfg(test)]
#[test]
#[available_gas(20000000)]
fn test_renew_expired_domain() {
    // initialize contracts
    let (erc20, pricing, starknetid, naming, autorenewal) = setup();

    // send eth to USER() & buy TH0RGAL_DOMAIN for 10 days
    send_eth(erc20, OWNER(), USER(), 1000.into());
    buy_domain(erc20, starknetid, naming, USER(), 1.into(), TH0RGAL_DOMAIN(), 10.into());

    // Toggle renewal & approve ERC20 transfer
    let limit_price: u256 = 600.into();
    autorenewal.toggle_renewals(TH0RGAL_DOMAIN(), limit_price);
    erc20.approve(autorenewal.contract_address, 600.into());

    // Advance time and assert domain is expired
    testing::set_block_timestamp(1728000);
    let expiry = naming.domain_to_expiry(build_domain_arr(TH0RGAL_DOMAIN()));
    assert(integer::u256_from_felt252(expiry) < 1728000.into(), 'domain should be expired');

    // Should renew TH0RGAL_DOMAIN for a year even if it is expired
    autorenewal.renew(TH0RGAL_DOMAIN(), USER(), limit_price);
    let new_expiry = naming.domain_to_expiry(build_domain_arr(TH0RGAL_DOMAIN()));
    assert(new_expiry == 1728000 + 86400 * 365, 'new expiry should be 365 days');
}

#[cfg(test)]
#[test]
#[available_gas(20000000)]
fn test_renew_domains() {
    // initialize contracts
    let (erc20, pricing, starknetid, naming, autorenewal) = setup();

    let limit_price: u256 = 600.into();

    // send eth to USER() & buy TH0RGAL_DOMAIN for 10 days & toggle renewal
    send_eth(erc20, OWNER(), USER(), 1000.into());
    buy_domain(erc20, starknetid, naming, USER(), 1.into(), TH0RGAL_DOMAIN(), 10.into());
    autorenewal.toggle_renewals(TH0RGAL_DOMAIN(), limit_price);
    erc20.approve(autorenewal.contract_address, limit_price);

    // send eth to OTHER() & buy OTHER_DOMAIN for 10 days & toggle renewal
    send_eth(erc20, OWNER(), OTHER(), 1000.into());
    buy_domain(erc20, starknetid, naming, OTHER(), 1.into(), OTHER_DOMAIN(), 10.into());
    autorenewal.toggle_renewals(OTHER_DOMAIN(), limit_price);
    erc20.approve(autorenewal.contract_address, limit_price);

    // Should renew both domains for a year

    // Build calldata
    let mut domains_arr = ArrayTrait::<felt252>::new();
    domains_arr.append(TH0RGAL_DOMAIN());
    domains_arr.append(OTHER_DOMAIN());
    let mut renewers_arr = ArrayTrait::<ContractAddress>::new();
    renewers_arr.append(USER());
    renewers_arr.append(OTHER());
    let mut limit_prices_arr = ArrayTrait::<u256>::new();
    limit_prices_arr.append(limit_price);
    limit_prices_arr.append(limit_price);

    autorenewal.batch_renew(domains_arr, renewers_arr, limit_prices_arr);

    let expiry = naming.domain_to_expiry(build_domain_arr(TH0RGAL_DOMAIN()));
    assert(expiry == 86400 * 10 + 86400 * 365, 'new expiry should be 375 days');
    let expiry = naming.domain_to_expiry(build_domain_arr(OTHER_DOMAIN()));
    assert(expiry == 86400 * 10 + 86400 * 365, 'new expiry should be 375 days');
}
