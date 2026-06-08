/// Module: satoshi_flip::dice_tests
///
/// Unit tests for the dice game module (previously untested).
#[test_only]
module satoshi_flip::dice_tests {

    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::test_utils;
    use sui::random::{Self, Random};

    use satoshi_flip::house_data::{Self, HouseData, HouseCap};
    use satoshi_flip::dice::{Self, DiceGame};

    const HOUSE_ADDRESS: address = @0xCAFE;
    const PLAYER_ADDRESS: address = @0xBEEF;
    const INITIAL_BALANCE: u64 = 100_000_000_000; // 100 SUI
    const STAKE_AMOUNT: u64 = 5_000_000_000; // 5 SUI
    const SIDES: u8 = 6;

    fun mint_coin(amount: u64, scenario: &mut Scenario): Coin<SUI> {
        coin::mint_for_testing<SUI>(amount, ts::ctx(scenario))
    }

    fun setup_house(scenario: &mut Scenario) {
        ts::next_tx(scenario, HOUSE_ADDRESS);
        { house_data::init_for_testing(ts::ctx(scenario)); };
        ts::next_tx(scenario, HOUSE_ADDRESS);
        {
            let house_cap = ts::take_from_sender<HouseCap>(scenario);
            let coin = mint_coin(INITIAL_BALANCE, scenario);
            house_data::initialize_house_data(house_cap, coin, vector[1, 2, 3, 4], ts::ctx(scenario));
        };
    }

    fun create_dice_game(scenario: &mut Scenario, guess: u8) {
        ts::next_tx(scenario, PLAYER_ADDRESS);
        {
            let mut house_data = ts::take_shared<HouseData>(scenario);
            let stake = mint_coin(STAKE_AMOUNT, scenario);
            dice::create_game(SIDES, guess, stake, &mut house_data, ts::ctx(scenario));
            ts::return_shared(house_data);
        };
    }

    #[test]
    fun test_dice_player_wins() {
        let mut scenario = ts::begin(HOUSE_ADDRESS);
        setup_house(&mut scenario);
        create_dice_game(&mut scenario, 3); // guess face 3

        // Force the die to land on 3 → player wins sides:1 minus a single fee.
        ts::next_tx(&mut scenario, HOUSE_ADDRESS);
        {
            let game = ts::take_shared<DiceGame>(&scenario);
            let mut house_data = ts::take_shared<HouseData>(&scenario);
            let initial = house_data::balance(&house_data);
            dice::finish_game_for_testing(game, 3, &mut house_data, ts::ctx(&mut scenario));
            // House balance pool drops by (sides-1)*stake (it pays the winnings; the fee
            // it keeps moves to the fees pool).
            let final = house_data::balance(&house_data);
            assert!(initial - final == ((SIDES as u64) - 1) * STAKE_AMOUNT, 0);
            ts::return_shared(house_data);
        };

        ts::next_tx(&mut scenario, PLAYER_ADDRESS);
        {
            let payout = ts::take_from_sender<Coin<SUI>>(&scenario);
            let fee = STAKE_AMOUNT / 100;
            assert!(coin::value(&payout) == (SIDES as u64) * STAKE_AMOUNT - fee, 0);
            test_utils::destroy(payout);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_dice_player_loses() {
        let mut scenario = ts::begin(HOUSE_ADDRESS);
        setup_house(&mut scenario);
        create_dice_game(&mut scenario, 3);

        ts::next_tx(&mut scenario, HOUSE_ADDRESS);
        {
            let game = ts::take_shared<DiceGame>(&scenario);
            let mut house_data = ts::take_shared<HouseData>(&scenario);
            let initial = house_data::balance(&house_data);
            dice::finish_game_for_testing(game, 4, &mut house_data, ts::ctx(&mut scenario)); // not 3
            // House gains the whole stake.
            assert!(house_data::balance(&house_data) - initial == STAKE_AMOUNT, 0);
            ts::return_shared(house_data);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = dice::EInvalidGuess)]
    fun test_dice_invalid_guess_fails() {
        let mut scenario = ts::begin(HOUSE_ADDRESS);
        setup_house(&mut scenario);
        create_dice_game(&mut scenario, 7); // guess > sides(6)
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = dice::EInvalidSides)]
    fun test_dice_invalid_sides_fails() {
        let mut scenario = ts::begin(HOUSE_ADDRESS);
        setup_house(&mut scenario);
        ts::next_tx(&mut scenario, PLAYER_ADDRESS);
        {
            let mut house_data = ts::take_shared<HouseData>(&scenario);
            let stake = mint_coin(STAKE_AMOUNT, &mut scenario);
            dice::create_game(1, 1, stake, &mut house_data, ts::ctx(&mut scenario)); // sides < 2
            ts::return_shared(house_data);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_dice_native_settles() {
        let mut scenario = ts::begin(HOUSE_ADDRESS);
        setup_house(&mut scenario);

        ts::next_tx(&mut scenario, @0x0);
        { random::create_for_testing(ts::ctx(&mut scenario)); };
        ts::next_tx(&mut scenario, @0x0);
        {
            let mut r = ts::take_shared<Random>(&scenario);
            random::update_randomness_state_for_testing(
                &mut r, 0,
                x"0202020202020202020202020202020202020202020202020202020202020202",
                ts::ctx(&mut scenario)
            );
            ts::return_shared(r);
        };

        create_dice_game(&mut scenario, 3);

        ts::next_tx(&mut scenario, PLAYER_ADDRESS);
        {
            let game = ts::take_shared<DiceGame>(&scenario);
            let mut house_data = ts::take_shared<HouseData>(&scenario);
            let r = ts::take_shared<Random>(&scenario);
            dice::finish_game_native(game, &mut house_data, &r, ts::ctx(&mut scenario));
            ts::return_shared(house_data);
            ts::return_shared(r);
        };

        ts::next_tx(&mut scenario, PLAYER_ADDRESS);
        { assert!(!ts::has_most_recent_shared<DiceGame>(), 0); };
        ts::end(scenario);
    }
}
