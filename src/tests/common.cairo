use super::utils;
use super::constants::ADMIN;

use super::mocks::identity::Identity;
use super::mocks::identity::{IIdentityDispatcher, IIdentityDispatcherTrait};
use super::mocks::erc20::ERC20;
use openzeppelin::token::erc20::interface::{
    IERC20Camel, IERC20CamelDispatcher, IERC20CamelDispatcherTrait
};
use naming::naming::main::Naming;
use naming::interface::naming::{INamingDispatcher, INamingDispatcherTrait};
use naming::pricing::Pricing;
use naming::interface::pricing::{IPricingDispatcher, IPricingDispatcherTrait};
use auto_renew_contract::auto_renewal::{
    AutoRenewal, IAutoRenewal, IAutoRenewalDispatcher, IAutoRenewalDispatcherTrait,
};
use auto_renew_contract::auto_renewal::AutoRenewal::{ContractState as AutoRenewalContractState,};
use starknet::{
    get_contract_address, testing::set_contract_address, contract_address::ContractAddressZeroable
};

fn deploy_contracts() -> (
    IERC20CamelDispatcher,
    IPricingDispatcher,
    IIdentityDispatcher,
    INamingDispatcher,
    IAutoRenewalDispatcher
) {
    // erc20
    let eth = utils::deploy(ERC20::TEST_CLASS_HASH, array!['ether', 'ETH', 0, 1, ADMIN().into()]);
    // pricing
    let pricing = utils::deploy(Pricing::TEST_CLASS_HASH, array![eth.into()]);
    // identity
    let identity = utils::deploy(Identity::TEST_CLASS_HASH, ArrayTrait::<felt252>::new());
    // naming
    let naming = utils::deploy(
        Naming::TEST_CLASS_HASH, array![identity.into(), pricing.into(), 0, ADMIN().into()]
    );
    // autorenewal
    let renewal = utils::deploy(
        AutoRenewal::TEST_CLASS_HASH,
        array![naming.into(), eth.into(), 0x111, ADMIN().into(), ADMIN().into()]
    );
    set_contract_address(ADMIN());

    (
        IERC20CamelDispatcher { contract_address: eth },
        IPricingDispatcher { contract_address: pricing },
        IIdentityDispatcher { contract_address: identity },
        INamingDispatcher { contract_address: naming },
        IAutoRenewalDispatcher { contract_address: renewal }
    )
}
