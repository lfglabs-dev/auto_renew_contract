# %% Imports
import logging
from asyncio import run

from starknet_py.hash.selector import get_selector_from_name
from starknet_py.net.client_models import Call

from utils.constants import COMPILED_CONTRACTS_DEVNET, ETH_TOKEN_ADDRESS, COMPILED_CONTRACTS_DEVNET_V0
from utils.starknet import (
    declare_v2,
    declare,
    deploy,
    deploy_v2,
    deploy_with_proxy,
    dump_declarations,
    dump_deployments,
    get_declarations,
    get_starknet_account,
    invoke,
    invoke_cairo0,
    get_eth_contract,
    get_deployments,
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
        
        # declare autorenewal contract in cairo1
        class_hash = {
            contract["contract_name"]: await declare_v2(contract["contract_name"])
            for contract in COMPILED_CONTRACTS_DEVNET
        }
        # declare cairo0 contracts : pricing, naming, identity
        class_hash_v0 = {
            contract["contract_name"]: await declare(contract["contract_name"])
            for contract in COMPILED_CONTRACTS_DEVNET_V0
        }
        class_hash = class_hash | class_hash_v0
        dump_declarations(class_hash)

        class_hash = get_declarations()
        print('class_hash', class_hash)

        # %% Deployments        
        deployments = {}
        deployments["pricing"] = await deploy("pricing", ETH_TOKEN_ADDRESS)

        call = Call(
            to_addr=deployments["pricing"]["address"],
            selector=get_selector_from_name("compute_buy_price"),
            calldata=[7, 365],
        )
        price_domain = await account.client.call_contract(call)
        price_domain = price_domain[1]
        print('domain_price', price_domain)

        deployments["starknetid"] = await deploy("starknetid")
        deployments["naming"] = await deploy_with_proxy("naming", [deployments["starknetid"]["address"], deployments["pricing"]["address"], account.address, 0])

        # Deploy auto renewal
        deployments["auto_renew_contract_AutoRenewal"] = await deploy_v2(
            "auto_renew_contract_AutoRenewal",
            deployments["naming"]["address"],
            ETH_TOKEN_ADDRESS,
            0x7447084f620ba316a42c72ca5b8eefb3fe9a05ca5fe6430c65a69ecc4349b3b, # addr of account 2 on devnet receiving tax payments
            account.address
        )
        print('deployments', deployments)
        dump_deployments(deployments)

        logger.info("✅ Configuration Complete")

        logger.info("⏳ Generating dummy data on the devnet...")
        logger.info("⏳ Buying 10 domains for account...")
        eth = await get_eth_contract()
        for x in range(1, 10):
            # mint Starknet ID
            await invoke_cairo0("starknetid", "mint", [x])
            # approve naming to spend price_domain on behalf of account
            deployments = get_deployments()
            approve = await eth.functions["approve"].invoke(
                int(deployments["naming"]["address"], 16), 
                price_domain,
                max_fee=int(1e17)
            )
            await approve.wait_for_acceptance()
            # buy domain
            metadata = 0 if x % 2 == 0 else 0x683d4a5f8514fef22d709ea9c55d9419862820318e07a6cf20d49d758cbf06
            await invoke_cairo0("naming", "buy", [x, x, 365, 0, account.address, 0, metadata])

        logger.info("⏳ Toggling renewal for domains...")
        for x in range(1, 10):
            approve = await eth.functions["approve"].invoke(
                int(deployments["auto_renew_contract_AutoRenewal"]["address"], 16), 
                2**128,
                max_fee=int(1e17)
            )
            await approve.wait_for_acceptance()
            metadata = 0 if x % 2 == 0 else 0x683d4a5f8514fef22d709ea9c55d9419862820318e07a6cf20d49d758cbf06
            await invoke(
                    "auto_renew_contract_AutoRenewal",
                    "enable_renewals",
                    [x, price_domain, 0, metadata]
            )

        logger.info("⏳ Toggling back some domains...")
        for x in range(1, 5):
            await invoke(
                    "auto_renew_contract_AutoRenewal",
                    "disable_renewals",
                    [x, price_domain, 0]
            )
        logger.info("✅ Generation Complete")
    else:
        eth = await get_eth_contract()
        deployments = get_deployments()
        # Advance time : 31498364
        # curl -H "Content-Type: application/json"  -d "{ \"time\": 31498364, \"lite\": 1 }" -X POST localhost:5050/increase_time
        # logger.info("⏳ Renewing some domains...")
        # for x in range(6, 10):
        #     await invoke(
        #             "auto_renew_contract_AutoRenewal",
        #             "renew",
        #             [x, account.address, price_domain, 0]
        #     )
        logger.info("✅ Generation Complete")

# %% Run
if __name__ == "__main__":
    run(main())