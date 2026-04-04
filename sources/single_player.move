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
    public fun finish_game(
        game: Game,
        bls_sig: vector<u8>,
        house_data: &mut HouseData,
        ctx: &mut TxContext
    ) {
        assert!(ctx.sender() == house_data::house(house_data), ENotAdmin);

        let Game {
            id,
            guess,
            player,
            stake,
            fee_amount
        } = game;

        let game_id = object::uid_to_inner(&id);

        // Verify BLS signature
        let msg = object::uid_to_bytes(&id);
        let public_key = house_data::public_key(house_data);
        assert!(
            bls12381::bls12381_min_pk_verify(&bls_sig, &public_key, &msg),
            EInvalidBlsSignature
        );

        // Use the BLS signature to derive randomness
        let hashed = blake2b256(&bls_sig);
        let coin_side = (*std::vector::borrow(&hashed, 0)) % 2;

        // Determine winner
        let player_won = (coin_side == guess);

        let stake_amount = balance::value(&stake);
        let payout: u64;
        let house_balance = house_data::borrow_balance_mut(house_data);

        if (player_won) {
            // Player wins: gets stake back + equal amount from house - fees
            let winnings = balance::split(house_balance, stake_amount - fee_amount);
            let mut player_balance = stake;
            balance::join(&mut player_balance, winnings);
            
            payout = balance::value(&player_balance);
            
            // Take fees and add to house fees
            let fees = balance::split(&mut player_balance, fee_amount);
            let house_fees = house_data::borrow_fees_mut(house_data);
            balance::join(house_fees, fees);

            // Transfer winnings to player
            transfer::public_transfer(coin::from_balance(player_balance, ctx), player);
        } else {
            // House wins: stake goes to house balance
            balance::join(house_balance, stake);
            payout = 0;
        };

        // Emit game settled event
        event::emit(GameSettled {
            game_id,
            player,
            player_won,
            payout,
            coin_side
        });

        // Delete game object
        object::delete(id);
    }

    /// Alternative: Finish game using a caller-supplied random value.
    /// DEPRECATED: This function is admin-gated to prevent players from
    /// controlling the outcome. Use finish_game() with a BLS signature instead.
    public fun finish_game_with_randomness(
        game: Game,
        random_value: u8,
        house_data: &mut HouseData,
        ctx: &mut TxContext
    ) {
        assert!(ctx.sender() == house_data::house(house_data), ENotAdmin);
        let Game {
            id,
            guess,
            player,
            stake,
            fee_amount
        } = game;

        let game_id = object::uid_to_inner(&id);
        let coin_side = random_value % 2;

        // Determine winner
        let player_won = (coin_side == guess);

        let stake_amount = balance::value(&stake);
        let payout: u64;
        let house_balance = house_data::borrow_balance_mut(house_data);

        if (player_won) {
            // Player wins: gets stake back + equal amount from house - fees
            let winnings = balance::split(house_balance, stake_amount - fee_amount);
            let mut player_balance = stake;
            balance::join(&mut player_balance, winnings);
            
            payout = balance::value(&player_balance);
            
            // Take fees and add to house fees
            let fees = balance::split(&mut player_balance, fee_amount);
            let house_fees = house_data::borrow_fees_mut(house_data);
            balance::join(house_fees, fees);

            // Transfer winnings to player
            transfer::public_transfer(coin::from_balance(player_balance, ctx), player);
        } else {
            // House wins: stake goes to house balance
            balance::join(house_balance, stake);
            payout = 0;
        };

        // Emit game settled event
        event::emit(GameSettled {
            game_id,
            player,
            player_won,
            payout,
            coin_side
        });

        // Delete game object
        object::delete(id);
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
