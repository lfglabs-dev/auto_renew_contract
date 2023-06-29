from starkware.starknet.compiler.compile import get_selector_from_name
from starknet_py.net.models.chains import StarknetChainId
from starknet_py.net.udc_deployer.deployer import Deployer
from starknet_py.net.gateway_client import GatewayClient
from starknet_py.net.account.account import Account
from starknet_py.net.signer.stark_curve_signer import KeyPair
from starknet_py.contract import Contract
from generate import increase_allowance, buy_domains, toggle_renewals

import asyncio

# Devnet --seed 0 first account
deployer_account_addr = (
    0x7e00d496e324876bbc8531f2d9a82bf154d1a04a50218ee74cdd372f75a551a
)
deployer_account_private_key = 0xe3e70682c2094cac629f6fbed82c07cd
deployer_account_public_key = 0x7e52885445756b313ea16849145363ccb73fb4ab0440dbac333cf9d13de82b9
admin = 0x7e00d496e324876bbc8531f2d9a82bf154d1a04a50218ee74cdd372f75a551a
network_base_url = "http://0.0.0.0:5050"
network_gateway_url = "http://0.0.0.0:5050"
chainid = StarknetChainId.TESTNET
max_fee = int(1e16)
deployer = Deployer()

eth_token = 0x49D36570D4E46F48E99674BD3FCC84644DDD6B96F7C741B1562B82F9E004DC7
TH0RGAL_STRING = 28235132438

async def main():
    client: GatewayClient = GatewayClient(
        net={
            "feeder_gateway_url": network_base_url + '/feeder_gateway',
            "gateway_url": network_base_url + '/gateway',
        }
    )
    account: Account = Account(
        client=client,
        address=deployer_account_addr,
        key_pair=KeyPair(private_key=deployer_account_private_key, public_key=deployer_account_public_key),
        chain=chainid
    )
    print("account", hex(account.address))
    nonce = await account.get_nonce()
    print("account nonce: ", nonce)

    # Declare and deploy starknetid contract
    impl_file = open("./build/starknetid.json", "r")
    declare_result = await Contract.declare(
        account=account, compiled_contract=impl_file.read(), max_fee=int(1e16)
    )
    impl_file.close()
    await declare_result.wait_for_acceptance()
    deploy_result = await declare_result.deploy(max_fee=int(1e16))
    await deploy_result.wait_for_acceptance()
    starknetid_contract = deploy_result.deployed_contract
    starknetid_addr = starknetid_contract.address
    print("starknetid_addr:", starknetid_addr)

    # Declare and deploy pricing contract
    impl_file = open("./build/pricing.json", "r")
    declare_result = await Contract.declare(
        account=account, compiled_contract=impl_file.read(), max_fee=int(1e16)
    )
    impl_file.close()
    await declare_result.wait_for_acceptance()
    deploy_result = await declare_result.deploy(constructor_args={eth_token}, max_fee=int(1e16))
    await deploy_result.wait_for_acceptance()
    pricing_contract = deploy_result.deployed_contract
    pricing_addr = pricing_contract.address
    print("pricing_addr:", pricing_addr)

    # Declare and deploy naming contract
    impl_file = open("./build/naming.json", "r")
    declare_result = await Contract.declare(
        account=account, compiled_contract=impl_file.read(), max_fee=int(1e16)
    )
    impl_file.close()
    await declare_result.wait_for_acceptance()
    deploy_result = await declare_result.deploy(max_fee=int(1e16))
    await deploy_result.wait_for_acceptance()
    naming_contract = deploy_result.deployed_contract
    naming_addr = naming_contract.address
    print("naming_addr:", naming_addr)

    invocation = await naming_contract.functions["initializer"].invoke(starknetid_addr, pricing_addr, admin, 0, max_fee=int(1e16))
    await invocation.wait_for_acceptance()

    # Deploy renewal contract
    impl_file = open("./build/main.json", "r")
    declare_result = await Contract.declare(
        account=account, compiled_contract=impl_file.read(), max_fee=int(1e16)
    )
    impl_file.close()
    await declare_result.wait_for_acceptance()
    deploy_result = await declare_result.deploy(max_fee=int(1e16))
    await deploy_result.wait_for_acceptance()
    renewal_contract = deploy_result.deployed_contract
    renewal_addr = renewal_contract.address
    print("renewal_addr:", renewal_addr)

    invocation = await renewal_contract.functions["initializer"].invoke(naming_addr, pricing_addr, eth_token, max_fee=int(1e16))
    await invocation.wait_for_acceptance()

    await increase_allowance(client, naming_addr)
    await increase_allowance(client, renewal_addr)
    await buy_domains(client, 1, 10, starknetid_addr, naming_addr)
    await toggle_renewals(client, 1, 10, renewal_addr)


if __name__ == "__main__":
    loop = asyncio.get_event_loop()
    loop.run_until_complete(main())