# Niftyswap Liquidity Migrator

The Niftyswap Liquidity Migrator is a tool that allows users to migrate their liquidity from one Niftyswap pool to another.
This is used by [Skyweaver](https://www.skyweaver.net/) to transfer liquidity from USDC.e to USDC.

## Process

In the below example, we will migrate liquidity from Niftyswap Exchange A to Niftyswap Exchange B.
NiftySwap Exchange A is the old pool that contains ERC1155 and USDC.e tokens, and Niftyswap Exchange B is the new pool that will contain ERC1155 and USDC tokens.

```mermaid
sequenceDiagram

actor M as Multisig
participant A as Niftyswap Exchange A
actor I as Migrator Contract
participant U as Uniswap
participant B as Niftyswap Exchange B

M-->>+I: Send Exchange A LP tokens
I->>+A: Remove liquidity
A->>-I: Send ERC1155 and USDC.e
I->>U: Approve USDC.e
I->>+U: Swap USDC.e
U->>-I: Send USDC
note over I: Detect valuation
I->>B: Approve USDC
I->>B: Deposit liquidity
I-->>M: Send Exchange B LP tokens
note over I: In case of slippage
I-->>-M: Send remaining USDC
```

Note that this repository has been designed to cater for any ERC1155 and ERC20 tokens.

## Usage

Install dependencies:

```sh
git submodule update --init --recursive
yarn
yarn lint:init # For developers
```

Run tests:

```sh
yarn test
```

Run the script:

```sh
cp .env.example .env
# Manually update the .env file with the correct values
forge script script/LiveTest.s.sol:LiveTestScript --fork-url https://rpc-mainnet.matic.quiknode.pro -vvvvv
```

Use the `--broadcast` flag to broadcast the transaction to the network.

## License

All contracts in this repository are released under the Apache-2.0 license.
