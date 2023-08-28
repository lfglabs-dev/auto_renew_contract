# Auto renew contract

This contract allows StarknetID to offer a convenient and secure auto-renewal feature. By activating the automatic renewal you keep the possibility of cutting it at any time and won't pay the transaction costs, you will only be charged the price of the domain.
Here are the guarantees offered by this contract:

- Your funds will only be used to renew the domains you've chosen
- You can only be charged up to the limit you've chosen
- You can only be charged once a year
- You can only be charged if your domain expires in less than a month

This contract is not upgradeable, we cannot change its code. This means that even if we wanted to be dishonest, we could not circumvent these rules.

# How to build/test?

This was built using scarb.

- building: `scarb --release build`
- testing: `scarb test`

# Deploy

First, create a `.env` file. You can use `.env.example` as reference. Just make sure to specify a `STARKNET_NETWORK` between (devnet, testnet & mainnet), and the associated `ACCOUNT_ADDRESS` and `ACCOUNT_PRIVATE_KEY` prefixed by the correct network name. If no account specific to a network name is specified, it will fallback to unprefixed `ACCOUNT_ADDRESS` and `ACCOUNT_PRIVATE_KEY`.

Here is how to setup the Python environment:

```
python3 -m venv ./env
source env/bin/activate
python -m pip install -r requirements.txt
```

And to run the deployment:

```
python3 scripts/deploy_testnet.py
```
