# satoshi_flip

A Sui Move coin-flip and dice game — and a worked example of **on-chain randomness**,
settled two ways so you can see the trade-off:

- **`finish_game`** — house-signed **BLS** randomness: verifiable, but *house-trusted*
  (the house can compute outcomes off-chain and decline to settle games it would lose).
- **`finish_game_native`** — Sui's native **`Random`**: trustless, unbiased, and the
  recommended default. Anyone can settle; the validators' DKG beacon picks the outcome.

The full analysis — why on-chain randomness is hard, what each path actually buys you,
and the `entry`-not-`public` footgun that makes the trustless path easy to get wrong —
is in **[RANDOMNESS.md](RANDOMNESS.md)**.

## Layout

```
sources/
  game_base.move      shared fee / payout / stake-validation helpers
  house_data.move     house bankroll + capability (the only minter of payouts)
  single_player.move  coin flip: create_game / finish_game (BLS) / finish_game_native
  dice.move           N-sided dice: same two settlement paths
tests/                single_player, dice, house_data unit tests (19 total)
RANDOMNESS.md         the randomness design + threat model
```

## Build & test

Requires the [Sui CLI](https://docs.sui.io/guides/developer/getting-started/sui-install).
The framework dependency is pinned to a specific commit (and `Move.lock` is committed),
so builds are reproducible.

```bash
sui move build
sui move test     # 19 tests
```

## Economics

A win pays `stake * multiplier` (2:1 for the coin, N:1 for an N-sided die) minus a single
house fee in basis points; on a loss the stake goes to the house. The house bankroll and
fee rate live in `HouseData`; payouts can only be minted by the contract holding the
house balance.

## Status

Educational. **Not audited; do not use with real funds.** The BLS path in particular is
verifiable but house-trusted — see RANDOMNESS.md for the threat model.

## License

MIT.
