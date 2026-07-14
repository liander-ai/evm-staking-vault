#!/usr/bin/env bash
# Local end-to-end proof: anvil node -> forge deploy -> viem interaction.
export PATH="$HOME/.foundry/bin:$PATH"
cd "$HOME/evm-staking-vault" || exit 1

pkill -f anvil 2>/dev/null
sleep 0.5

anvil > /tmp/anvil.log 2>&1 &
ANVIL_PID=$!

# wait for RPC to be ready
for i in $(seq 1 50); do
  if curl -s http://localhost:8545 -X POST -H 'content-type: application/json' \
      -d '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' 2>/dev/null | grep -q result; then
    break
  fi
  sleep 0.3
done

PK=$(grep -oiE '0x[a-f0-9]{64}' /tmp/anvil.log | head -1)
echo "anvil key0 length: ${#PK}"
export PRIVATE_KEY="$PK"

echo "=== DEPLOY (once) ==="
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --private-key "$PK" --broadcast > /tmp/deploy.log 2>&1
grep -E 'StakeToken|RewardToken|Vault|Error|revert|Script ran' /tmp/deploy.log | head

STAKE=$(grep 'StakeToken' /tmp/deploy.log | grep -oiE '0x[a-f0-9]{40}' | head -1)
VAULT=$(grep 'Vault' /tmp/deploy.log | grep -oiE '0x[a-f0-9]{40}' | head -1)
echo "STAKE=$STAKE"
echo "VAULT=$VAULT"

echo "=== INTERACT (viem) ==="
RPC_URL=http://127.0.0.1:8545 CHAIN_ID=31337 PRIVATE_KEY="$PK" VAULT="$VAULT" STAKE_TOKEN="$STAKE" node scripts/interact.mjs

kill $ANVIL_PID 2>/dev/null
pkill -f anvil 2>/dev/null
echo "=== DONE ==="
