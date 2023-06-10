from starkware.starknet.compiler.compile import get_selector_from_name
from starknet_py.net.models.chains import StarknetChainId
from starknet_py.net.udc_deployer.deployer import Deployer
from starknet_py.net.gateway_client import GatewayClient
from starknet_py.net.account.account import Account
from starknet_py.net.signer.stark_curve_signer import KeyPair
from starknet_py.contract import Contract

import asyncio
import sys
import json

argv = sys.argv

deployer_account_addr = (
    0x048F24D0D0618FA31813DB91A45D8BE6C50749E5E19EC699092CE29ABE809294
)
deployer_account_private_key = int(argv[1])
deployer_account_public_key = int(argv[2])
admin = 0x048F24D0D0618FA31813DB91A45D8BE6C50749E5E19EC699092CE29ABE809294
# TESTNET: https://alpha4.starknet.io/
network_base_url = "https://alpha4.starknet.io/"
chainid = StarknetChainId.TESTNET
max_fee = int(1e16)
deployer = Deployer()

eth_token = 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7
naming_addr = 0x3bab268e932d2cecd1946f100ae67ce3dff9fd234119ea2f6da57d16d29fce
pricing_addr = 0x012bfb305562ff88860883f4d839d3a5f888ed1921aa1e7528dc9b8bcbd98e65

async def main():
    client: GatewayClient = GatewayClient("testnet")
    account: Account = Account(
        client=client,
        address=deployer_account_addr,
        key_pair=KeyPair(private_key=deployer_account_private_key, public_key=deployer_account_public_key),
        chain=chainid
    )
    print("account", hex(account.address))
    nonce = await account.get_nonce()
    print("account nonce: ", nonce)

    # Declare & deploy renewal contract
    impl_file = open("./build/main.json", "r")
    declare_result = await Contract.declare(
        account=account, compiled_contract=impl_file.read(), max_fee=int(1e16)
    )
    impl_file.close()
    await declare_result.wait_for_acceptance()
    impl_contract_class_hash = declare_result.class_hash
    print('impl_contract_class_hash:', impl_contract_class_hash)

    # declare proxy contract
    proxy_file = open("./build/proxy.json", "r")
    proxy_content = proxy_file.read()
    declare_contract_tx = await account.sign_declare_transaction(
        compiled_contract=proxy_content, max_fee=max_fee
    )
    proxy_file.close()
    proxy_declaration = await client.declare(transaction=declare_contract_tx)
    proxy_contract_class_hash = proxy_declaration.class_hash
    print("proxy class hash:", hex(proxy_contract_class_hash))

    proxy_json = json.loads(proxy_content)
    abi = proxy_json["abi"]
    deploy_call, address = deployer.create_deployment_call(
        class_hash=proxy_contract_class_hash,
        abi=abi,
        calldata={
            "implementation_hash": impl_contract_class_hash,
            "selector": get_selector_from_name("initializer"),
            "calldata": [
                admin,
                naming_addr,
                pricing_addr,
                eth_token,
            ],
        },
    )

    resp = await account.execute(deploy_call, max_fee=int(1e16))
    print("deployment txhash:", hex(resp.transaction_hash))
    print("proxied contract address:", hex(address))


if __name__ == "__main__":
    loop = asyncio.get_event_loop()
    loop.run_until_complete(main())