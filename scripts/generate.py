from starkware.starknet.compiler.compile import get_selector_from_name
from starknet_py.net.models.chains import StarknetChainId
from starknet_py.net.udc_deployer.deployer import Deployer
from starknet_py.net.gateway_client import GatewayClient
from starknet_py.net.account.account import Account
from starknet_py.net.signer.stark_curve_signer import KeyPair
from starknet_py.contract import Contract
from constants import DEVNET_ACCOUNTS, erc20_addr, ENCODED_DOMAINS

import random
chainid = StarknetChainId.TESTNET
max_fee = int(1e16)
deployer = Deployer()

async def increase_allowance(client, naming_contract_addr):
    # Set approval to naming_contract for all existing accounts
    for j in range(0, len(DEVNET_ACCOUNTS)):
        account = DEVNET_ACCOUNTS[j]
        account = Account(
            client=client,
            address=int(account["address"], 16),
            key_pair=KeyPair(private_key=int(account["private_key"], 16), public_key=int(account["public_key"], 16)),
            chain=chainid
        )
        print("approval for account: ", hex(account.address))
        erc20_contract = await Contract.from_address(provider=account, address=erc20_addr)
        invocation = await erc20_contract.functions["approve"].invoke(naming_contract_addr, 900000000000000000000, max_fee=int(1e16))
        await invocation.wait_for_acceptance()

async def buy_domains(client, from_, to, starknetid_contract_addr, naming_contract_addr):
    # Buy multiple domains from different accounts
    for i in range(from_, to):
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
        print("Mint identity: ", i)
        invocation = await starknetid_contract.functions["mint"].invoke(i + 20, max_fee=int(1e16))
        await invocation.wait_for_acceptance()

        # buy domain
        print("Buy domain: ", ENCODED_DOMAINS[i - 1])
        invocation = await naming_contract.functions["buy"].invoke(i + 20, ENCODED_DOMAINS[i - 1], 60, 0, account.address, max_fee=int(1e16))
        await invocation.wait_for_acceptance()


async def toggle_renewals(client, _from, to, renewal_contract_addr):
    for i in range(_from, to):
        print("Toggled renewal for domain: ", ENCODED_DOMAINS[i - 1])
        account_index = random.randint(0, len(DEVNET_ACCOUNTS) - 1)
        account = Account(
            client=client,
            address=int(DEVNET_ACCOUNTS[account_index]["address"], 16),
            key_pair=KeyPair(private_key=int(DEVNET_ACCOUNTS[account_index]["private_key"], 16), public_key=int(DEVNET_ACCOUNTS[account_index]["public_key"], 16)),
            chain=chainid
        )
        renewal_contract = await Contract.from_address(provider=account, address=renewal_contract_addr)
        invocation = await renewal_contract.functions["toggle_renewals"].invoke(ENCODED_DOMAINS[i - 1], max_fee=int(1e16))
        await invocation.wait_for_acceptance()
