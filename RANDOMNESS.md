# On-Chain Randomness: BLS vs Native Sui Randomness

This package settles each game two ways, on purpose, to show the trade-off:

- **`finish_game`** — house-signed **BLS** randomness. *Verifiable, but house-trusted.*
- **`finish_game_native`** — Sui's **native `Random`**. *Trustless, and the recommended default.*

This document explains why on-chain randomness is hard, what each path actually buys
you, and the one footgun that makes the "trustless" path easy to get wrong.

---

## 1. Why on-chain randomness is hard

A blockchain is deterministic: every node must compute the same result from the same
inputs. "True" randomness would break consensus. The naive fixes all leak:

- **Block hash / `timestamp` / `prevrandao`** — visible to the block producer before
  execution, who can re-roll the block until the outcome suits them. Never safe for value.
- **Commit-reveal** — the second revealer (usually the house) can refuse to reveal on a
  bad outcome (griefing). Needs a timeout and capital lock-up.
- **External VRF (e.g. Chainlink)** — adds an oracle you have to trust to be live and
  uncorrupted; extra latency.

---

## 2. BLS-signature randomness — verifiable, but *house-trusted*

### How it works (`finish_game` / `dice::finish_game`)

1. The player creates a game object. Its `UID` depends on the transaction digest, so it
   is not predictable before the player signs.
2. The house signs the game's id bytes with its BLS12-381 key.
3. The contract verifies with `bls12381::bls12381_min_pk_verify(sig, pub_key, game_id)`
   and derives the outcome from `blake2b256(sig)`.

Because BLS is **deterministic**, there is exactly one valid signature per (key, game id).
So the house *cannot* "re-sign until it likes the outcome" — that attack doesn't exist.

### …but that is not the same as trustless

The residual trust is **selective participation**, and it is the headline, not a footnote:

> BLS being deterministic *also* means the house can compute the outcome of any game
> **off-chain, in advance** — it just signs the id and hashes it. It cannot change a
> given game's outcome, but it never has to play one it would lose. It can simply
> **not settle** unfavorable games ("technical issues"), or screen which games it
> creates/accepts. The player has no on-chain recourse without a settlement timeout.

So BLS is **verifiable** (anyone can check the signature) but **not trustless** (you are
trusting the house to settle honestly and promptly). Other assumptions: key custody (a
leaked house key breaks every game) and key rotation.

**BLS is appropriate when** the stakes are modest, the house is a known/accountable
entity, and there is a settlement-timeout/dispute path. It is *not* "provably fair."

---

## 3. Native Sui randomness — trustless (implemented as `finish_game_native`)

Sui's `sui::random::Random` is a shared system object (`0x8`) backed by the validators'
distributed key generation. No single validator knows the seed; a ⅔ majority would have
to collude. `new_generator(r, ctx)` seeds a local PRNG from that beacon plus
transaction entropy.

This package implements it directly:

```move
use sui::random::{Self, Random};

/// MUST be `entry`, not `public` — see the footgun below.
entry fun finish_game_native(
    game: Game,
    house_data: &mut HouseData,
    r: &Random,
    ctx: &mut TxContext
) {
    let mut gen = random::new_generator(r, ctx);
    let coin_side = random::generate_u8_in_range(&mut gen, 0, 1); // dice: (&mut gen, 1, sides)
    // ... settle ...
}
```

Why it's strictly better here: it removes the house's selective-participation power
(**anyone** can call `finish_game_native` — the outcome is fair regardless of caller),
needs no off-chain signing service, and `generate_u8_in_range` is **unbiased** (the BLS
path's `byte % sides` is slightly biased whenever `sides` doesn't divide 256).

### ⚠️ The footgun: the consumer of `&Random` must be a private `entry` function

If you make a function that reads randomness `public`, you reintroduce a bias attack —
just a different one:

> A `public` function can be called from *another* Move function. A caller can invoke it,
> read the result, branch on it, and **abort the whole transaction** if the outcome is a
> loss — retrying until they win, paying only gas. This "preview-and-abort" is exactly
> what `entry` prevents: an `entry` function cannot be called from other Move code, only
> as a top-level transaction command, so its effects can't be inspected-and-reverted by a
> composing caller.

Rules of thumb, straight from Sui's randomness guidance: the function that consumes
`&Random` should be **`entry` and non-`public`**; do all randomness-dependent effects
(payouts, deletes) inside it; and don't let a caller observe the result before it commits.

| Property | BLS (`finish_game`) | Native (`finish_game_native`) |
|---|---|---|
| Unpredictable by player | yes | yes |
| Unpredictable by house | the *value* yes, but house controls *whether/when to settle* | yes |
| Selective participation / bias-by-delay | **possible** | not possible (anyone settles) |
| Off-chain infra | house signing service | none |
| Trust root | one house key | ⅔ of validators |
| Outcome bias | `byte % n` slightly biased | unbiased range |
| Footgun | — | must be `entry`, not `public` |

---

## 4. Further reading

- [Sui on-chain randomness guide](https://docs.sui.io/guides/developer/advanced/randomness-onchain) (see the "important limitations" on `entry`)
- [`sui::random` source](https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/packages/sui-framework/sources/random.move)
- [MystenLabs satoshi-coin-flip (official example)](https://github.com/MystenLabs/satoshi-coin-flip)
- [Drand — distributed randomness beacon](https://drand.love) · [Chainlink VRF](https://docs.chain.link/vrf)
