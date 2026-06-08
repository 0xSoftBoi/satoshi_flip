/// Module: satoshi_flip::single_player_tests
/// 
/// Unit tests for the single_player game module
#[test_only]
module satoshi_flip::single_player_tests {

    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::test_utils;
    use sui::random::{Self, Random};

    use satoshi_flip::house_data::{Self, HouseData, HouseCap};
    use satoshi_flip::single_player::{Self, Game};

    // Test constants
    const HOUSE_ADDRESS: address = @0xCAFE;
    const PLAYER_ADDRESS: address = @0xBEEF;
    const INITIAL_BALANCE: u64 = 100_000_000_000; // 100 SUI
    const STAKE_AMOUNT: u64 = 5_000_000_000; // 5 SUI

    // Helper function to create a test coin
    fun mint_coin(amount: u64, scenario: &mut Scenario): Coin<SUI> {
        coin::mint_for_testing<SUI>(amount, ts::ctx(scenario))
    }

    // Helper to setup house
    fun setup_house(scenario: &mut Scenario) {
        ts::next_tx(scenario, HOUSE_ADDRESS);
        {
            satoshi_flip::house_data::init_for_testing(ts::ctx(scenario));
        };

        ts::next_tx(scenario, HOUSE_ADDRESS);
        {
            let house_cap = ts::take_from_sender<HouseCap>(scenario);
            let coin = mint_coin(INITIAL_BALANCE, scenario);
            let public_key = vector[1, 2, 3, 4]; // Dummy public key
            house_data::initialize_house_data(house_cap, coin, public_key, ts::ctx(scenario));
        };
    }

    #[test]
    fun test_create_game() {
        let mut scenario = ts::begin(HOUSE_ADDRESS);
        setup_house(&mut scenario);

        // Player creates a game
        ts::next_tx(&mut scenario, PLAYER_ADDRESS);
        {
            let mut house_data = ts::take_shared<HouseData>(&scenario);
            let stake = mint_coin(STAKE_AMOUNT, &mut scenario);
            
            let _game_id = single_player::create_game(
                0, // HEADS
                stake,
                &mut house_data,
                ts::ctx(&mut scenario)
            );

            ts::return_shared(house_data);
        };

        // Verify game was created
        ts::next_tx(&mut scenario, PLAYER_ADDRESS);
        {
            let game = ts::take_shared<Game>(&scenario);
            
            assert!(single_player::guess(&game) == 0, 0);
            assert!(single_player::player(&game) == PLAYER_ADDRESS, 1);
            assert!(single_player::stake_amount(&game) == STAKE_AMOUNT, 2);
            
            // Fee should be 1% of stake
            let expected_fee = STAKE_AMOUNT / 100;
            assert!(single_player::fee_amount(&game) == expected_fee, 3);
            
            ts::return_shared(game);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_player_wins_with_randomness() {
        let mut scenario = ts::begin(HOUSE_ADDRESS);
        setup_house(&mut scenario);

        // Player creates a game betting on HEADS (0)
        ts::next_tx(&mut scenario, PLAYER_ADDRESS);
        {
            let mut house_data = ts::take_shared<HouseData>(&scenario);
            let stake = mint_coin(STAKE_AMOUNT, &mut scenario);
            
            single_player::create_game(
                0, // HEADS
                stake,
                &mut house_data,
                ts::ctx(&mut scenario)
            );

            ts::return_shared(house_data);
        };

        // House finishes game with random value that produces HEADS (even number % 2 = 0)
        ts::next_tx(&mut scenario, HOUSE_ADDRESS);
        {
            let game = ts::take_shared<Game>(&scenario);
            let mut house_data = ts::take_shared<HouseData>(&scenario);
            
            let initial_house_balance = house_data::balance(&house_data);
            
            // Random value 0 % 2 = 0 = HEADS, player should win
            single_player::finish_game_with_randomness(
                game,
                0, // Will result in HEADS
                &mut house_data,
                ts::ctx(&mut scenario)
            );

            // House should have paid out winnings
            let final_house_balance = house_data::balance(&house_data);
            
            // The house *balance* pool drops by the full stake; the fee it keeps is
            // moved into the separate fees pool, so net economic loss is stake - fee.
            let expected_loss = STAKE_AMOUNT;
            assert!(initial_house_balance - final_house_balance == expected_loss, 0);
            
            ts::return_shared(house_data);
        };

        // Verify player received payout
        ts::next_tx(&mut scenario, PLAYER_ADDRESS);
        {
            let payout = ts::take_from_sender<Coin<SUI>>(&scenario);
            // Player gets stake back + winnings, minus a single fee = 2*stake - fee.
            let fee = STAKE_AMOUNT / 100;
            let expected_payout = 2 * STAKE_AMOUNT - fee;
            assert!(coin::value(&payout) == expected_payout, 0);
            
            test_utils::destroy(payout);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_player_loses_with_randomness() {
        let mut scenario = ts::begin(HOUSE_ADDRESS);
        setup_house(&mut scenario);

        // Player creates a game betting on HEADS (0)
        ts::next_tx(&mut scenario, PLAYER_ADDRESS);
        {
            let mut house_data = ts::take_shared<HouseData>(&scenario);
            let stake = mint_coin(STAKE_AMOUNT, &mut scenario);
            
            single_player::create_game(
                0, // HEADS
                stake,
                &mut house_data,
                ts::ctx(&mut scenario)
            );

            ts::return_shared(house_data);
        };

        // House finishes game with random value that produces TAILS (odd number % 2 = 1)
        ts::next_tx(&mut scenario, HOUSE_ADDRESS);
        {
            let game = ts::take_shared<Game>(&scenario);
            let mut house_data = ts::take_shared<HouseData>(&scenario);
            
            let initial_house_balance = house_data::balance(&house_data);
            
            // Random value 1 % 2 = 1 = TAILS, player should lose
            single_player::finish_game_with_randomness(
                game,
                1, // Will result in TAILS
                &mut house_data,
                ts::ctx(&mut scenario)
            );

            // House should have gained the stake
            let final_house_balance = house_data::balance(&house_data);
            assert!(final_house_balance - initial_house_balance == STAKE_AMOUNT, 0);
            
            ts::return_shared(house_data);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = single_player::EInvalidGuess)]
    fun test_invalid_guess_fails() {
        let mut scenario = ts::begin(HOUSE_ADDRESS);
        setup_house(&mut scenario);

        // Player tries to create game with invalid guess
        ts::next_tx(&mut scenario, PLAYER_ADDRESS);
        {
            let mut house_data = ts::take_shared<HouseData>(&scenario);
            let stake = mint_coin(STAKE_AMOUNT, &mut scenario);
            
            // Guess of 2 is invalid (only 0 or 1 allowed)
            single_player::create_game(
                2,
                stake,
                &mut house_data,
                ts::ctx(&mut scenario)
            );

            ts::return_shared(house_data);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = single_player::EStakeTooLow)]
    fun test_stake_too_low_fails() {
        let mut scenario = ts::begin(HOUSE_ADDRESS);
        setup_house(&mut scenario);

        // Player tries to bet below minimum stake
        ts::next_tx(&mut scenario, PLAYER_ADDRESS);
        {
            let mut house_data = ts::take_shared<HouseData>(&scenario);
            let low_stake = 100_000_000; // 0.1 SUI, below 1 SUI minimum
            let stake = mint_coin(low_stake, &mut scenario);
            
            single_player::create_game(
                0,
                stake,
                &mut house_data,
                ts::ctx(&mut scenario)
            );

            ts::return_shared(house_data);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = single_player::EStakeTooHigh)]
    fun test_stake_too_high_fails() {
        let mut scenario = ts::begin(HOUSE_ADDRESS);
        setup_house(&mut scenario);

        // Player tries to bet above maximum stake
        ts::next_tx(&mut scenario, PLAYER_ADDRESS);
        {
            let mut house_data = ts::take_shared<HouseData>(&scenario);
            let high_stake = 60_000_000_000; // 60 SUI, above 50 SUI maximum
            let stake = mint_coin(high_stake, &mut scenario);
            
            single_player::create_game(
                0,
                stake,
                &mut house_data,
                ts::ctx(&mut scenario)
            );

            ts::return_shared(house_data);
        };

        ts::end(scenario);
    }

    // A garbage signature must be rejected by the BLS gate (this path was previously
    // untested — the other tests use the deterministic test-only settle).
    #[test]
    #[expected_failure(abort_code = single_player::EInvalidBlsSignature)]
    fun test_invalid_bls_signature_fails() {
        let mut scenario = ts::begin(HOUSE_ADDRESS);
        setup_house(&mut scenario);

        ts::next_tx(&mut scenario, PLAYER_ADDRESS);
        {
            let mut house_data = ts::take_shared<HouseData>(&scenario);
            let stake = mint_coin(STAKE_AMOUNT, &mut scenario);
            single_player::create_game(0, stake, &mut house_data, ts::ctx(&mut scenario));
            ts::return_shared(house_data);
        };

        ts::next_tx(&mut scenario, HOUSE_ADDRESS);
        {
            let game = ts::take_shared<Game>(&scenario);
            let mut house_data = ts::take_shared<HouseData>(&scenario);
            let bad_sig = vector[0u8, 0, 0, 0]; // not a valid BLS signature
            single_player::finish_game(game, bad_sig, &mut house_data, ts::ctx(&mut scenario));
            ts::return_shared(house_data);
        };

        ts::end(scenario);
    }

    // The trustless native-randomness path settles the game (consumes it and pays out),
    // and — unlike the BLS path — anyone, not just the house, can trigger it.
    #[test]
    fun test_native_randomness_settles() {
        let mut scenario = ts::begin(HOUSE_ADDRESS);
        setup_house(&mut scenario);

        // Create + seed the system Random object (normally lives at 0x8).
        ts::next_tx(&mut scenario, @0x0);
        { random::create_for_testing(ts::ctx(&mut scenario)); };
        ts::next_tx(&mut scenario, @0x0);
        {
            let mut r = ts::take_shared<Random>(&scenario);
            random::update_randomness_state_for_testing(
                &mut r,
                0,
                x"0101010101010101010101010101010101010101010101010101010101010101",
                ts::ctx(&mut scenario)
            );
            ts::return_shared(r);
        };

        ts::next_tx(&mut scenario, PLAYER_ADDRESS);
        {
            let mut house_data = ts::take_shared<HouseData>(&scenario);
            let stake = mint_coin(STAKE_AMOUNT, &mut scenario);
            single_player::create_game(0, stake, &mut house_data, ts::ctx(&mut scenario));
            ts::return_shared(house_data);
        };

        // A non-house caller settles via native randomness.
        ts::next_tx(&mut scenario, PLAYER_ADDRESS);
        {
            let game = ts::take_shared<Game>(&scenario);
            let mut house_data = ts::take_shared<HouseData>(&scenario);
            let r = ts::take_shared<Random>(&scenario);
            single_player::finish_game_native(game, &mut house_data, &r, ts::ctx(&mut scenario));
            ts::return_shared(house_data);
            ts::return_shared(r);
        };

        // Game object was consumed (settled).
        ts::next_tx(&mut scenario, PLAYER_ADDRESS);
        { assert!(!ts::has_most_recent_shared<Game>(), 0); };

        ts::end(scenario);
    }
}
