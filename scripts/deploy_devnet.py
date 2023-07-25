# %% Imports
import logging
from asyncio import run

from utils.constants import COMPILED_CONTRACTS_DEVNET, ETH_TOKEN_ADDRESS
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
    get_deployments
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
        for contract in COMPILED_CONTRACTS_DEVNET
    }
    dump_declarations(class_hash)

    # %% Deployments
    class_hash = get_declarations()

    print('class_hash', class_hash)
    
    deployments = {}
    deployments["auto_renew_contract_Pricing"] = await deploy_v2("auto_renew_contract_Pricing", ETH_TOKEN_ADDRESS)
    deployments["auto_renew_contract_StarknetID"] = await deploy_v2("auto_renew_contract_StarknetID")
    deployments["auto_renew_contract_Naming"] = await deploy_v2(
        "auto_renew_contract_Naming",
        deployments["auto_renew_contract_StarknetID"]["address"],
        deployments["auto_renew_contract_Pricing"]["address"],
        ETH_TOKEN_ADDRESS,
    )
    deployments["auto_renew_contract_AutoRenewal"] = await deploy_v2(
        "auto_renew_contract_AutoRenewal",
        deployments["auto_renew_contract_Naming"]["address"],
        deployments["auto_renew_contract_Pricing"]["address"],
        ETH_TOKEN_ADDRESS,
    )
    dump_deployments(deployments)

    logger.info("✅ Configuration Complete")

    logger.info("⏳ Generating dummy data on the devnet...")
    logger.info("⏳ Buying 10 domains for account...")
    eth = await get_eth_contract()
    for x in range(1, 10):
        # mint Starknet ID
        await invoke(
            "auto_renew_contract_StarknetID",
            "mint",
            [x]
        )
        # approve
        deployments = get_deployments()
        approve = await eth.functions["approve"].invoke(
            int(deployments["auto_renew_contract_Naming"]["address"], 16), 
            int_to_uint256(500),
            max_fee=int(1e17)
        )
        await approve.wait_for_acceptance()
        # buy domain
        await invoke(
            "auto_renew_contract_Naming",
            "buy",
            [x, x, 10, 0, account.address]
        )

    logger.info("⏳ Toggling renewal for domains...")
    for x in range(1, 10):
        approve = await eth.functions["approve"].invoke(
            int(deployments["auto_renew_contract_AutoRenewal"]["address"], 16), 
            600, 0,
            max_fee=int(1e17)
        )
        await approve.wait_for_acceptance()
        await invoke(
                "auto_renew_contract_AutoRenewal",
                "toggle_renewals",
                [x, 600, 0]
        )

    logger.info("⏳ Toggling back some domains...")
    for x in range(1, 5):
        approve = await eth.functions["approve"].invoke(
            int(deployments["auto_renew_contract_AutoRenewal"]["address"], 16), 
            0, 0,
            max_fee=int(1e17)
        )
        await approve.wait_for_acceptance()
        await invoke(
                "auto_renew_contract_AutoRenewal",
                "toggle_renewals",
                [x, 600, 0]
        )

    logger.info("✅ Generation Complete")

# %% Run
if __name__ == "__main__":
    run(main())