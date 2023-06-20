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
    0x00a00373A00352aa367058555149b573322910D54FCDf3a926E3E56D0dCb4b0c
)
deployer_account_private_key = int(argv[1])
admin = 0x00a00373A00352aa367058555149b573322910D54FCDf3a926E3E56D0dCb4b0c
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
        key_pair=KeyPair.from_private_key(deployer_account_private_key),
        chain=chainid
    )
    print("account", hex(account.address))
    nonce = await account.get_nonce()
    print("account nonce: ", nonce)

    # declare proxy contract
    proxy_file = open("./build/proxy.json", "r")
    proxy_content = proxy_file.read()

    proxy_contract_class_hash = 0xea0cbb4e76447cfa0e711a28405300794b1149e707e92288386ce14fa2ff0f
    impl_contract_class_hash = 0x6d5557dc2c38d36238aadeea19549662bf2d40483f25bbd275304a0feaa2394

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