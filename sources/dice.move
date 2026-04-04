/// Module: satoshi_flip::dice
///
/// Multi-sided dice game using the same BLS signature randomness as the coin flip.
/// Players guess which face (1 to N) the die will land on. A correct guess pays
/// N:1 minus the house fee.
///
/// ## Randomness approach
///
/// Uses the same BLS12-381 + Blake2b256 mechanism as single_player.move:
/// the house signs the game ID, and the resulting hash is reduced modulo `sides`
/// to get the outcome. This is house-controlled randomness — the house could
/// theoretically re-sign until a favorable outcome, but the economic cost
/// (time + gas + lost credibility) makes this impractical for small stakes.
///
/// ## Migration note
///
/// A production deployment should migrate to Sui's native `sui::random::Random`
/// module (available in framework >= v1.19). With native randomness, outcomes are
/// determined by a distributed key generation (DKG) protocol across all validators —
/// even the house cannot predict or manipulate the outcome. See RANDOMNESS.md.
///
/// The migration requires only:
/// 1. Changing `finish_game` to accept a `&Random` argument
/// 2. Replacing the BLS block with `random::generate_u8_in_range(&mut gen, 1, sides)`
/// 3. Removing the house's off-chain signing infrastructure
module satoshi_flip::dice {

    use sui::object::{Self, ID, UID};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::tx_context::TxContext;
    use sui::transfer;
    use sui::event;
    use sui::bls12381;
    use sui::hash::blake2b256;

    use satoshi_flip::house_data::{Self, HouseData};
    use satoshi_flip::game_base;

    // ==================== Error Codes ====================

    /// Guess is outside [1, sides] range
    const EInvalidGuess: u64 = 10;
    /// Dice must have 2 to 100 sides
    const EInvalidSides: u64 = 11;
    /// Invalid BLS signature from house
    const EInvalidBlsSignature: u64 = 12;

    // ==================== Structs ====================

    /// A single dice game instance.
    public struct DiceGame has key, store {
        id: UID,
        /// Number of sides on the die (2-100)
        sides: u8,
        /// Player's guess: 1 to sides (inclusive)
        guess: u8,
        /// Player address for payout routing
        player: address,
        /// Player's staked amount (held in escrow)
        stake: Balance<SUI>,
        /// Fee deducted from stake at settlement
        fee_amount: u64,
    }

    // ==================== Events ====================

    public struct DiceGameCreated has copy, drop {
        game_id: ID,
        player: address,
        sides: u8,
        guess: u8,
        stake: u64,
    }

    public struct DiceGameSettled has copy, drop {
        game_id: ID,
        player: address,
        outcome: u8,       // actual die face that came up (1-indexed)
        guess: u8,
        won: bool,
        payout: u64,       // amount sent to winner (0 if house wins)
    }

    // ==================== Game Creation ====================

    /// Create a new dice game.
    ///
    /// @param sides  Number of sides (2 to 100). A standard die is 6.
    /// @param guess  Player's guess: must be in [1, sides].
    /// @param stake  Coin staked by the player. Transferred to game escrow.
    /// @param house_data  Shared house configuration (min/max stake, fee rate).
    public fun create_game(
        sides: u8,
        guess: u8,
        stake: Coin<SUI>,
        house_data: &mut HouseData,
        ctx: &mut TxContext
    ) {
        assert!(sides >= 2 && sides <= 100, EInvalidSides);
        assert!(guess >= 1 && guess <= sides, EInvalidGuess);

        let stake_amount = coin::value(&stake);

        // Validate stake range using shared game_base logic
        game_base::validate_stake(stake_amount, house_data);

        // Ensure house can cover the payout: sides:1 payout minus fee
        game_base::assert_house_can_cover(
            stake_amount,
            sides as u64,
            1,
            house_data::balance(house_data)
        );

        // Calculate and reserve fee from stake
        let (_, fee_amount) = game_base::calculate_payout(
            stake_amount,
            sides as u64,
            1,
            house_data::base_fee_in_bp(house_data)
        );

        let game = DiceGame {
            id: object::new(ctx),
            sides,
            guess,
            player: tx_context::sender(ctx),
            stake: coin::into_balance(stake),
            fee_amount,
        };

        let game_id = object::id(&game);
        event::emit(DiceGameCreated {
            game_id,
            player: tx_context::sender(ctx),
            sides,
            guess,
            stake: stake_amount,
        });

        // Share the game object so the house can settle it
        transfer::share_object(game);
    }

    // ==================== Settlement ====================

    /// Settle a dice game using a BLS signature from the house.
    ///
    /// The house signs the game's object ID with its BLS12-381 private key.
    /// The Blake2b256 hash of the signature is reduced modulo `sides` to get
    /// the outcome (0-indexed), then shifted to 1-indexed for the result.
    ///
    /// ## Security note
    /// The house MUST NOT re-try with different signatures — that would let
    /// them manipulate outcomes. For trustless games, migrate to sui::random.
    /// See RANDOMNESS.md for details.
    ///
    /// @param game       The DiceGame to settle. Consumed on settlement.
    /// @param bls_sig    BLS12-381 signature of the game ID by the house.
    /// @param house_data Mutable house data (balance updated on outcome).
    public fun finish_game(
        game: DiceGame,
        bls_sig: vector<u8>,
        house_data: &mut HouseData,
        ctx: &mut TxContext
    ) {
        let DiceGame { id, sides, guess, player, stake, fee_amount } = game;

        let game_id = object::uid_to_bytes(&id);
        object::delete(id);

        // Verify BLS signature: house must have signed the game ID
        let public_key = house_data::public_key(house_data);
        let is_valid = bls12381::bls12381_min_pk_verify(&bls_sig, &public_key, &game_id);
        assert!(is_valid, EInvalidBlsSignature);

        // Derive outcome from hash of signature
        let hash = blake2b256(&bls_sig);
        // Take first byte, reduce modulo sides → 0-indexed [0, sides-1], add 1 → 1-indexed
        let outcome_0indexed = (*vector::borrow(&hash, 0) % sides);
        let outcome = outcome_0indexed + 1;

        let won = guess == outcome;
        let stake_amount = balance::value(&stake);

        let payout: u64;
        if (won) {
            // Deduct fee from stake, calculate gross payout
            let (net_payout, fee) = game_base::calculate_payout(
                stake_amount,
                sides as u64,
                1,
                house_data::base_fee_in_bp(house_data)
            );
            // House contributes (sides-1) * stake to the payout pool
            let house_contribution = (stake_amount as u128) * ((sides - 1) as u128);
            let house_bal = house_data::balance_mut(house_data);
            balance::join(house_bal, stake);

            // Transfer fee to house fee accumulator
            let fee_bal = house_data::fees_mut(house_data);
            let fee_coin = balance::split(house_bal, fee);
            balance::join(fee_bal, fee_coin);

            // Send net_payout to player
            let win_balance = balance::split(house_bal, net_payout);
            let win_coin = coin::from_balance(win_balance, ctx);
            transfer::public_transfer(win_coin, player);
            payout = net_payout;
            let _ = house_contribution;
        } else {
            // House wins: player's stake + fee goes to house
            let house_bal = house_data::balance_mut(house_data);
            let fee_bal = house_data::fees_mut(house_data);
            let fee_coin = balance::split(&mut stake, fee_amount);
            balance::join(fee_bal, fee_coin);
            balance::join(house_bal, stake);
            payout = 0;
        };

        event::emit(DiceGameSettled {
            game_id: object::id_from_bytes(game_id),
            player,
            outcome,
            guess,
            won,
            payout,
        });
    }
}
