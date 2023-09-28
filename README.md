# Auto renew contract

This contract allows StarknetID to offer a convenient and secure auto-renewal feature. By activating the automatic renewal you keep the possibility of cutting it at any time and won't pay the transaction costs, you will only be charged the price of the domain.
Here are the guarantees offered by this contract:

- Your funds will only be used to renew the domains you've chosen
- You can only be charged up to the limit you've chosen
- You can only be charged once a year
- You can only be charged if your domain expires in less than a month

This contract is not upgradeable, we cannot change its code. This means that even if we wanted to be dishonest, we could not circumvent these rules.

# Technical notes

Here are some technical choices we made:

### 1. You can renew a domain you don't own.
This is useful if you want your domain to be controled by a smartcontract but you still want to pay for its renewal.

### 2. You need a domain name to disable a flow of spending
When you create a flow of spending, you specify for which domain it is valid and what yearly allowance you give to this contract. To disable this allowance you need to use the same account and provide the same domain. We emit events to allow users to easily retrieve these data so they will be able to see them in the front.

### 3. Your allowance is what we can spend
Your spending limit, sometimes called 'allowance', represents the maximum we can deduct from your account. Even if the actual cost is lower, it's best to set this limit carefully. While we can often refund overcharges or errors, we don't guarantee refunds, especially for small amounts.

### 4. Admin
This contract is controled by an admin who has the ability to fully disable the contract renewals for ever (if a vulnerability was found or the contract deprecated). It has also the power to change the allowed renewer (address allowed to renew domains of other people). This allowed renewer has to be trusted by StarknetID (but not the users) because it is in control of the tax_price. If the admin or renewer was compromised, the latter would still do its job but do not send tax money to StarknetID.

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
