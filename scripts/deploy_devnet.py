# %% Imports
import logging
from asyncio import run

from starknet_py.hash.selector import get_selector_from_name
from starknet_py.net.client_models import Call

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
    need_deploy = True
    # %% Declarations
    account = await get_starknet_account()
    if need_deploy:
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

        # call = Call(
        #     to_addr=deployments["auto_renew_contract_Pricing"]["address"],
        #     selector=get_selector_from_name("compute_buy_price"),
        #     calldata=[7, 365],
        # )
        # price_domain = await account.client.call_contract(call)
        # print('domain_price', price_domain)

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
            ETH_TOKEN_ADDRESS,
            0x7447084f620ba316a42c72ca5b8eefb3fe9a05ca5fe6430c65a69ecc4349b3b,
            account.address
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
                [x, x, 365, 0, account.address]
            )

        logger.info("⏳ Toggling renewal for domains...")
        for x in range(1, 10):
            approve = await eth.functions["approve"].invoke(
                int(deployments["auto_renew_contract_AutoRenewal"]["address"], 16), 
                int_to_uint256(2**128),
                max_fee=int(1e17)
            )
            await approve.wait_for_acceptance()
            await invoke(
                    "auto_renew_contract_AutoRenewal",
                    "enable_renewals",
                    [x, 600, 0, 0x683d4a5f8514fef22d709ea9c55d9419862820318e07a6cf20d49d758cbf06]
            )

        logger.info("⏳ Toggling back some domains...")
        for x in range(1, 5):
            # approve = await eth.functions["decreaseAllowance"].invoke(
            #     int(deployments["auto_renew_contract_AutoRenewal"]["address"], 16), 
            #     int_to_uint256(600),
            #     max_fee=int(1e17)
            # )
            # await approve.wait_for_acceptance()
            await invoke(
                    "auto_renew_contract_AutoRenewal",
                    "disable_renewals",
                    [x, 600, 0]
            )
        logger.info("✅ Generation Complete")
    else:
        eth = await get_eth_contract()
        deployments = get_deployments()
        test = await eth.functions["allowance"].call(
            account.address,
            int(deployments["auto_renew_contract_AutoRenewal"]["address"], 16), 
        )
        print('test', test)
        # Advance time : 31498364
        # curl -H "Content-Type: application/json"  -d "{ \"time\": 31498364, \"lite\": 1 }" -X POST localhost:5050/increase_time
        # logger.info("⏳ Renewing some domains...")
        # for x in range(6, 10):
        #     await invoke(
        #             "auto_renew_contract_AutoRenewal",
        #             "renew",
        #             [x, account.address, 600, 0]
        #     )
        logger.info("✅ Generation Complete")

# %% Run
if __name__ == "__main__":
    run(main())