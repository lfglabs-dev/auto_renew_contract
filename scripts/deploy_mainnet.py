# %% Imports
import logging
from asyncio import run

from utils.constants import (
    COMPILED_CONTRACTS,
    ETH_TOKEN_ADDRESS,
    NAMING_ADDRESS_MAINNET,
    PRICING_ADDRESS_MAINNET,
    TAX_ADDRESS_MAINNET,
    ADMIN_ADDRESS_MAINNET,
    RENEWER_ADDRESS_MAINNET,
)
from utils.starknet import (
    declare_v2,
    deploy_v2,
    dump_declarations,
    dump_deployments,
    get_declarations,
    get_starknet_account,
    invoke,
    int_to_uint256,
    get_eth_contract,
    get_deployments,
)

logging.basicConfig()
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


# %% Main
async def main():
    # %% Declarations
    account = await get_starknet_account()
    logger.info(f"ℹ️  Using account {hex(account.address)} as deployer")

    class_hash = {
        contract["contract_name"]: await declare_v2(contract["contract_name"])
        for contract in COMPILED_CONTRACTS
    }
    dump_declarations(class_hash)

    # %% Deployments
    class_hash = get_declarations()

    print("class_hash", class_hash)

    deployments = {}
    deployments["auto_renew_contract_AutoRenewal"] = await deploy_v2(
        "auto_renew_contract_AutoRenewal",
        NAMING_ADDRESS_MAINNET,
        ETH_TOKEN_ADDRESS,
        TAX_ADDRESS_MAINNET,
        ADMIN_ADDRESS_MAINNET,
        RENEWER_ADDRESS_MAINNET,
    )
    dump_deployments(deployments)
    logger.info("✅ Configuration Complete")


# %% Run
if __name__ == "__main__":
    run(main())
