from starkware.starknet.compiler.compile import get_selector_from_name
from starknet_py.net.models.chains import StarknetChainId
from starknet_py.net.udc_deployer.deployer import Deployer
from starknet_py.net.gateway_client import GatewayClient
from starknet_py.net.account.account import Account
from starknet_py.net.signer.stark_curve_signer import KeyPair
from starknet_py.contract import Contract

import asyncio
import json

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
    print("starknetid_addr:", hex(starknetid_addr))

    # Declare and deploy pricing contract
    impl_file = open("./build/pricing.json", "r")
    declare_result = await Contract.declare(
        account=account, compiled_contract=impl_file.read(), max_fee=int(1e16)
    )
    impl_file.close()
    await declare_result.wait_for_acceptance()
    deploy_result = await declare_result.deploy(constructor_args={admin}, max_fee=int(1e16))
    await deploy_result.wait_for_acceptance()
    pricing_contract = deploy_result.deployed_contract
    pricing_addr = pricing_contract.address
    print("pricing_addr:", hex(pricing_addr))

    # Declare naming contract
    impl_file = open("./build/naming.json", "r")
    declare_result = await Contract.declare(
        account=account, compiled_contract=impl_file.read(), max_fee=int(1e16)
    )
    impl_file.close()
    await declare_result.wait_for_acceptance()
    naming_class_hash = declare_result.class_hash
    print("naming_class_hash:", hex(naming_class_hash))

    # Declare proxy and deploy implementation
    proxy_file = open("./build/proxy.json", "r")
    proxy_content = proxy_file.read()
    declare_proxy_tx = await account.sign_declare_transaction(
        compiled_contract=proxy_content, max_fee=max_fee
    )
    proxy_file.close()
    proxy_declaration = await client.declare(transaction=declare_proxy_tx)
    proxy_contract_class_hash = proxy_declaration.class_hash
    print("proxy class hash:", hex(proxy_contract_class_hash))

    proxy_json = json.loads(proxy_content)
    abi = proxy_json["abi"]
    deploy_call, address = deployer.create_deployment_call(
        class_hash=proxy_contract_class_hash,
        abi=abi,
        calldata={
            "implementation_hash": naming_class_hash,
            "selector": get_selector_from_name("initializer"),
            "calldata": [starknetid_addr, pricing_addr, admin, 0],
        },
    )

    resp = await account.execute(deploy_call, max_fee=int(1e16))
    print("deployment txhash:", hex(resp.transaction_hash))
    naming_address = address
    print("proxied naming contract address:", hex(naming_address))

    # Deploy renewal contract
    impl_file = open("./build/main.json", "r")
    declare_result = await Contract.declare(
        account=account, compiled_contract=impl_file.read(), max_fee=int(1e16)
    )
    impl_file.close()
    await declare_result.wait_for_acceptance()
    deploy_result = await declare_result.deploy(constructor_args={naming_address, pricing_addr}, max_fee=int(1e16))
    await deploy_result.wait_for_acceptance()
    renewal_contract = deploy_result.deployed_contract
    renewal_addr = renewal_contract.address
    print("renewal_addr:", hex(renewal_addr))


if __name__ == "__main__":
    loop = asyncio.get_event_loop()
    loop.run_until_complete(main())