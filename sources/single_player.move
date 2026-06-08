/// Module: satoshi_flip::single_player
/// 
/// This module implements a single-player coin flip game where players can bet on
/// the outcome of a coin flip (heads or tails). The house provides the randomness
/// using BLS signatures for provably fair gaming.
module satoshi_flip::single_player {

    use sui::object::{Self, ID, UID};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::tx_context::TxContext;
    use sui::transfer;
    use sui::event;
    use sui::bls12381;
    use sui::hash::blake2b256;
    use sui::random::{Self, Random};

    use satoshi_flip::house_data::{Self, HouseData};

    // ==================== Error Codes ====================

    /// Stake amount is below minimum
    const EStakeTooLow: u64 = 0;
    /// Stake amount is above maximum
    const EStakeTooHigh: u64 = 1;
    /// House has insufficient balance
    const EInsufficientHouseBalance: u64 = 2;
    /// Invalid BLS signature
    const EInvalidBlsSignature: u64 = 3;
    /// Invalid guess (must be 0 or 1)
    const EInvalidGuess: u64 = 4;
    /// Caller is not the house admin
    const ENotAdmin: u64 = 5;

    // ==================== Constants ====================

    /// Heads = 0, Tails = 1
    const HEADS: u8 = 0;
    const TAILS: u8 = 1;

    // ==================== Structs ====================

    /// Represents a single game instance
    public struct Game has key, store {
        id: UID,
        /// The player's guess: 0 = heads, 1 = tails
        guess: u8,
        /// The player's address
        player: address,
        /// The player's stake
        stake: Balance<SUI>,
        /// Fee amount taken from stake
        fee_amount: u64
    }

    // ==================== Events ====================

    /// Emitted when a new game is created
    public struct GameCreated has copy, drop {
        game_id: ID,
        player: address,
        guess: u8,
        stake_amount: u64
    }

    /// Emitted when a game is settled
    public struct GameSettled has copy, drop {
        game_id: ID,
        player: address,
        player_won: bool,
        payout: u64,
        coin_side: u8
    }

    // ==================== Game Functions ====================

    /// Player creates a new game by placing a bet with their guess
    /// guess: 0 = heads, 1 = tails
    public fun create_game(
        guess: u8,
        stake: Coin<SUI>,
        house_data: &mut HouseData,
        ctx: &mut TxContext
    ): ID {
        // Validate guess
        assert!(guess == HEADS || guess == TAILS, EInvalidGuess);

        let stake_amount = coin::value(&stake);
        
        // Validate stake amount
        assert!(stake_amount >= house_data::min_stake(house_data), EStakeTooLow);
        assert!(stake_amount <= house_data::max_stake(house_data), EStakeTooHigh);
        
        // Ensure house can cover the potential payout (stake * 2 - fees)
        let house_balance = house_data::balance(house_data);
        assert!(house_balance >= stake_amount, EInsufficientHouseBalance);

        // Calculate fee
        let fee_bp = house_data::base_fee_in_bp(house_data);
        let fee_amount = (((stake_amount as u128) * (fee_bp as u128) / 10000) as u64);

        let player = ctx.sender();

        let game = Game {
            id: object::new(ctx),
            guess,
            player,
            stake: coin::into_balance(stake),
            fee_amount
        };

        let game_id = object::id(&game);

        // Emit game created event
        event::emit(GameCreated {
            game_id,
            player,
            guess,
            stake_amount
        });

        // Transfer game to house to hold until settlement
        transfer::share_object(game);

        game_id
    }

    /// House finishes the game by providing a BLS signature over the game ID
    /// The signature is used to derive randomness for the coin flip
    /// Only the house admin may call this function.
    /// House settles the game by providing a BLS signature over the game ID.
    ///
    /// Verifiable, but house-*trusted*: BLS is deterministic, so the house can compute
    /// the outcome of any game off-chain before settling and simply decline to settle
    /// (or never create) games it would lose. For trustless play, use
    /// `finish_game_native`. See RANDOMNESS.md.
    public fun finish_game(
        game: Game,
        bls_sig: vector<u8>,
        house_data: &mut HouseData,
        ctx: &mut TxContext
    ) {
        assert!(ctx.sender() == house_data::house(house_data), ENotAdmin);

        let Game { id, guess, player, stake, fee_amount } = game;
        let game_id = object::uid_to_inner(&id);
        let msg = object::uid_to_bytes(&id);
        object::delete(id);

        // Verify the house signed THIS game's id.
        let public_key = house_data::public_key(house_data);
        assert!(
            bls12381::bls12381_min_pk_verify(&bls_sig, &public_key, &msg),
            EInvalidBlsSignature
        );

        let hashed = blake2b256(&bls_sig);
        let coin_side = (*std::vector::borrow(&hashed, 0)) % 2;

        settle(stake, fee_amount, guess, player, coin_side, game_id, house_data, ctx);
    }

    /// Trustless settlement using Sui's native on-chain randomness (DKG-derived).
    /// Anyone may call it — the outcome is fair regardless of caller — which is the
    /// whole point: it removes the house's selective-participation power.
    ///
    /// MUST be `entry`, not `public`: an `entry` function can't be called from another
    /// Move function, so a composing caller can't read the result, branch on it, and
    /// abort the transaction on a loss ("preview-and-abort"). See RANDOMNESS.md.
    entry fun finish_game_native(
        game: Game,
        house_data: &mut HouseData,
        r: &Random,
        ctx: &mut TxContext
    ) {
        let Game { id, guess, player, stake, fee_amount } = game;
        let game_id = object::uid_to_inner(&id);
        object::delete(id);

        let mut gen = random::new_generator(r, ctx);
        let coin_side = random::generate_u8_in_range(&mut gen, 0, 1);

        settle(stake, fee_amount, guess, player, coin_side, game_id, house_data, ctx);
    }

    /// Shared payout logic. On a player win the house pays 2:1 minus a single fee, so
    /// the player receives exactly `2*stake - fee` (and the emitted `payout` matches
    /// what is transferred). On a house win the player's whole stake goes to the house.
    fun settle(
        stake: Balance<SUI>,
        fee_amount: u64,
        guess: u8,
        player: address,
        coin_side: u8,
        game_id: ID,
        house_data: &mut HouseData,
        ctx: &mut TxContext
    ) {
        let player_won = (coin_side == guess);
        let stake_amount = balance::value(&stake);
        let payout: u64;

        if (player_won) {
            let gross = ((stake_amount as u128) * 2) as u64; // 2:1
            let net_payout = gross - fee_amount;
            let house_balance = house_data::borrow_balance_mut(house_data);
            balance::join(house_balance, stake);                       // pool the stake
            let fee_coin = balance::split(house_balance, fee_amount);  // house edge (once)
            let win_balance = balance::split(house_balance, net_payout);
            balance::join(house_data::borrow_fees_mut(house_data), fee_coin);
            transfer::public_transfer(coin::from_balance(win_balance, ctx), player);
            payout = net_payout;
        } else {
            balance::join(house_data::borrow_balance_mut(house_data), stake);
            payout = 0;
        };

        event::emit(GameSettled { game_id, player, player_won, payout, coin_side });
    }

    /// Test-only deterministic settlement: lets unit tests force heads/tails without an
    /// off-chain BLS signer or real randomness. Admin-gated and `#[test_only]` so it
    /// cannot be a production backdoor around the randomness.
    #[test_only]
    public fun finish_game_with_randomness(
        game: Game,
        random_value: u8,
        house_data: &mut HouseData,
        ctx: &mut TxContext
    ) {
        assert!(ctx.sender() == house_data::house(house_data), ENotAdmin);
        let Game { id, guess, player, stake, fee_amount } = game;
        let game_id = object::uid_to_inner(&id);
        object::delete(id);
        let coin_side = random_value % 2;
        settle(stake, fee_amount, guess, player, coin_side, game_id, house_data, ctx);
    }

    // ==================== View Functions ====================

    /// Get the player's guess for a game
    public fun guess(game: &Game): u8 {
        game.guess
    }

    /// Get the player's address for a game
    public fun player(game: &Game): address {
        game.player
    }

    /// Get the stake amount for a game
    public fun stake_amount(game: &Game): u64 {
        balance::value(&game.stake)
    }

    /// Get the fee amount for a game
    public fun fee_amount(game: &Game): u64 {
        game.fee_amount
    }
}
