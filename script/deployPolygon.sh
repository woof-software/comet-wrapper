#!/bin/bash

set -exo pipefail

# Load .env file if it exists
if [ -f .env ]; then
  export $(cat .env | xargs)
fi

if [ -n "$RPC_POLYGON_URL" ]; then
  rpc_args="--rpc-url $RPC_POLYGON_URL"
else
  rpc_args=""
fi

if [ -n "$DEPLOYER_PK" ]; then
  wallet_args="--private-key $DEPLOYER_PK"
else
  wallet_args="--unlocked"
fi

if [ -n "$POLYSCAN_KEY" ]; then
  etherscan_args="--verify --etherscan-api-key $POLYSCAN_KEY"
else
  etherscan_args=""
fi


forge script \
    $rpc_args \
    $wallet_args \
    $etherscan_args \
    --broadcast \
    $@ \
    script/DeployCometWrapper.s.sol:DeployCometWrapper