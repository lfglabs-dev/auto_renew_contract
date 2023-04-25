from starkware.starknet.compiler.compile import get_selector_from_name
from starknet_py.net.models.chains import StarknetChainId
from starknet_py.net.udc_deployer.deployer import Deployer
from starknet_py.net.gateway_client import GatewayClient
from starknet_py.net.account.account import Account
from starknet_py.net.signer.stark_curve_signer import KeyPair
from starknet_py.contract import Contract
from constants import DEVNET_ACCOUNTS, erc20_addr

import random
chainid = StarknetChainId.TESTNET
max_fee = int(1e16)
deployer = Deployer()

async def increase_allowance(client, naming_contract_addr):
    # Increase allowance for all existing accounts
    for j in range(0, len(DEVNET_ACCOUNTS)):
        account = DEVNET_ACCOUNTS[j]
        account = Account(
            client=client,
            address=int(account["address"], 16),
            key_pair=KeyPair(private_key=int(account["private_key"], 16), public_key=int(account["public_key"], 16)),
            chain=chainid
        )
        erc20_contract = await Contract.from_address(provider=account, address=erc20_addr)
        invocation = await erc20_contract.functions["increaseAllowance"].invoke(naming_contract_addr, 900000000000000000000, max_fee=int(1e16))
        await invocation.wait_for_acceptance()

async def buy_domains(client, number, starknetid_contract_addr, naming_contract_addr):
    # Buy multiple domains from different accounts
    for i in range(1, number):
        print("Mint & buy domain: ", i)
        # get random account from seed accounts
        account_index = random.randint(1, len(DEVNET_ACCOUNTS) - 1)
        account = Account(
            client=client,
            address=int(DEVNET_ACCOUNTS[account_index]["address"], 16),
            key_pair=KeyPair(private_key=int(DEVNET_ACCOUNTS[account_index]["private_key"], 16), public_key=int(DEVNET_ACCOUNTS[account_index]["public_key"], 16)),
            chain=chainid
        )
        starknetid_contract = await Contract.from_address(provider=account, address=starknetid_contract_addr)
        naming_contract = await Contract.from_address(provider=account, address=naming_contract_addr)

        # Mint starknetid
        invocation = await starknetid_contract.functions["mint"].invoke(i, max_fee=int(1e16))
        await invocation.wait_for_acceptance()

        # buy domain
        invocation = await naming_contract.functions["buy"].invoke(i, i, 60, 0, admin, max_fee=int(1e16))
        await invocation.wait_for_acceptance()


async def toggle_renewals(client, numbers, renewal_contract_addr):
    for i in range(1, numbers):
        account_index = random.randint(1, len(DEVNET_ACCOUNTS) - 1)
        account = Account(
            client=client,
            address=int(DEVNET_ACCOUNTS[account_index]["address"], 16),
            key_pair=KeyPair(private_key=int(DEVNET_ACCOUNTS[account_index]["private_key"], 16), public_key=int(DEVNET_ACCOUNTS[account_index]["public_key"], 16)),
            chain=chainid
        )
        renewal_contract = await Contract.from_address(provider=account, address=renewal_contract_addr)
        invocation = await renewal_contract.functions["toggle_renewals"].invoke(i, max_fee=int(1e16))
        await invocation.wait_for_acceptance()
