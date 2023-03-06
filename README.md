# deDCAt

Decentralized Dollar Cost Averaging Tool

## DISCLAIMER: Threw it together in a few hours. Use at your own risk.

## Why?

I couldn't find a decentralized way to convert my USDC into ETH.

## How?

Create an `order` using `createOrder`. Orders have startTime, endTime, interval, amountPerInterval, and some params to specify the UniSwap v3 pool to use.
You will have to **approve tokenIn** to the DCA contract, but the contract _will not transfer any tokens from your account_.
**This means you can set up DCA for the next 1 year without having the entire asset in your account. The DCA will succeed only if you have the asset in your account when the order is executed (e.g. salary being paid to wallet)**

Gelato order is automatically created. Gelato will call `executeOrder` the order at the specified intervals.
Gelato fees are paid in WETH, from your account. So you have to **approve WETH** to DCA contract, and have enough WETH in your account to pay for the fees.

## Caveats and Risks

1. No frontrunning protection (yet). Using a UniSwap v3 pool with a high liquidity fee should mitigate most of the risks.
2. No guarantee Gelato will execute exactly on time. If it doesn't, anyone else can as a fallback.
3. Didn't code for ETH. Use WETH instead.
