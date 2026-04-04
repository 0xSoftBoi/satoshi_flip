# On-Chain Randomness: BLS vs Native Sui Randomness

This document explains why on-chain randomness is hard, how this package currently implements it (BLS signatures), and how to migrate to Sui's native randomness module — which is strictly better for production use.

---

## 1. Why On-Chain Randomness is Hard

A blockchain is a deterministic system: every node must compute the same result from the same inputs. "True" randomness violates this — if two nodes generate different random numbers, consensus breaks.

### Failed approaches

**Block hash as random seed**  
`block.prevrandao` or `block.timestamp` are publicly visible before transactions execute. A miner/validator can re-roll the block until they get a favorable outcome. Cheap to exploit, never appropriate for any meaningful value.

**Commit-reveal**  
Two-phase: player commits to a hash of their secret in tx1, reveals the secret in tx2. The random number is `hash(player_secret, house_secret)`.

*Problem:* The second revealer (usually the house) can refuse to reveal if the outcome is unfavorable (griefing attack). The first revealer is stuck. Requires a timeout mechanism that adds complexity and capital risk.

**VRF (Verifiable Random Function)**  
A VRF produces a pseudorandom output + cryptographic proof that the output was generated honestly from a specific private key and input. Used by Chainlink VRF on EVM chains.

*Problem on Sui:* External oracles introduce a trust dependency and latency. The VRF provider could be bribed, coerced, or simply go offline.

---

## 2. BLS Signature Randomness (Current Implementation)

### How it works

1. Player creates a game object. The game's `UID` (object ID) is unpredictable at creation time because it depends on the transaction digest.
2. House signs the game's object ID bytes using its BLS12-381 private key.
3. The contract verifies the signature with `bls12381::bls12381_min_pk_verify(sig, pub_key, game_id)`.
4. The Blake2b256 hash of the verified signature is used as the random seed.

### Why game_id is unmanipulable

The game object ID is derived from `hash(tx_digest || counter)`. The transaction digest includes the player's signature — the house cannot predict it before the player signs. Therefore, the house cannot pre-compute a BLS signature that produces a favorable outcome.

### The house re-sign attack

However: what if the house simply refuses to submit a settlement transaction until it happens to find a BLS signature that produces a favorable outcome?

```
// Pseudocode attack:
loop {
    sig = bls_sign(private_key, game_id)
    outcome = blake2b256(sig)[0] % 2  // 0=heads, 1=tails
    if (outcome == house_preferred) {
        submit finish_game(game, sig)
    }
    // else: generate another sig? No — BLS is deterministic.
}
```

**Actually, BLS is deterministic** — given the same key and message, it always produces the same signature. The house cannot "try again" with a different BLS signature for the same game_id/key pair. There is exactly ONE valid BLS signature per (key, message) pair.

**So BLS is actually safe against the re-sign attack** — as long as:
1. The house uses a single, fixed private key (no rotating keys)
2. The house key is not known to the player in advance

### Remaining trust assumptions

- **Key custody**: The house controls the BLS private key. A compromised house key compromises all games.
- **Key rotation**: If the house rotates keys, players must trust the new key. A malicious key rotation attack is possible.
- **Bias by timing**: The house can delay settlement indefinitely. While it cannot change the outcome, it can refuse to settle unfavorable games and claim "technical issues." A timeout mechanism is essential for production.

### Summary: BLS is appropriate when:
- Game value is modest (low incentive to corrupt key custody)
- House is a known, accountable entity
- Timeout/dispute mechanism exists for non-settlement

---

## 3. Sui Native Randomness (Recommended for Production)

Sui introduced `sui::random::Random` as a shared object backed by the validators' distributed key generation (DKG) protocol. Every epoch, validators collectively generate a new random seed using threshold secret sharing. No single validator knows the full seed — a 2/3 majority would need to collude.

### API (framework >= v1.19)

```move
use sui::random::{Self, Random};

// In your entry function — `r` is the shared Random object (address 0x8)
public fun finish_game(game: MyGame, r: &Random, ctx: &mut TxContext) {
    // Create a generator seeded from the validator DKG + current tx
    let mut gen = random::new_generator(r, ctx);
    
    // Generate a random bool (coin flip)
    let flip: bool = random::generate_bool(&mut gen);
    
    // Or a u8 in range [1, sides] for a dice game
    let roll: u8 = random::generate_u8_in_range(&mut gen, 1, sides);
}
```

The `Random` object at `0x8` is a system object updated every epoch. The `new_generator` call seeds a local PRNG from the validator DKG output + transaction-specific entropy, making each call unique within a transaction.

### Why it's better than BLS

| Property | BLS (current) | Native Random |
|---|---|---|
| Unpredictable by player? | Yes | Yes |
| Unpredictable by house? | Yes (but house controls settlement timing) | Yes |
| Requires off-chain infrastructure? | Yes (house signing service) | No |
| Trust assumption | Single house key | 2/3+ of validators |
| Bias by delay | Possible (house delays bad outcomes) | Not possible (validators settle) |
| Key rotation risk | Yes | No |
| Requires oracle? | No | No |

### Migration guide

To migrate `single_player.move` from BLS to native random:

```move
// Remove:
use sui::bls12381;
use sui::hash::blake2b256;

// Add:
use sui::random::{Self, Random};

// Old finish_game signature:
public fun finish_game(game: Game, bls_sig: vector<u8>, house_data: &mut HouseData, ctx: &mut TxContext)

// New finish_game signature (Random is a shared object, passed by reference):
public fun finish_game(game: Game, r: &Random, house_data: &mut HouseData, ctx: &mut TxContext)

// Old randomness block:
// let hash = blake2b256(&bls_sig);
// let coin_side = *vector::borrow(&hash, 0) % 2;

// New randomness block:
let mut gen = random::new_generator(r, ctx);
let coin_side: u8 = if (random::generate_bool(&mut gen)) { 1 } else { 0 };
```

The `Random` object address is `0x8` on both testnet and mainnet. When calling `finish_game`, pass it as:
```bash
sui client call --function finish_game --args <game_id> 0x8 <house_data_id>
```

### When BLS is still acceptable

- Low-value games where the house has no economic incentive to manipulate
- Situations where you want deterministic test vectors (BLS is predictable in tests)
- Educational projects (this repository)

---

## 4. Further Reading

- [Sui Randomness Design](https://docs.sui.io/guides/developer/advanced/randomness-onchain)
- [Sui Random module source](https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/packages/sui-framework/sources/random.move)
- [MystenLabs satoshi-coin-flip (official example)](https://github.com/MystenLabs/satoshi-coin-flip)
- [Drand — distributed randomness beacon](https://drand.love)
- [Chainlink VRF](https://docs.chain.link/vrf)
- [Commit-reveal schemes — Ethereum](https://medium.com/swlh/exploring-commit-reveal-schemes-on-ethereum-c4ff5a777db8)
