/// Module: satoshi_flip::house_data_tests
/// 
/// Unit tests for the house_data module
#[test_only]
module satoshi_flip::house_data_tests {

    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::test_utils;
    
    use satoshi_flip::house_data::{Self, HouseData, HouseCap};

    // Test constants
    const HOUSE_ADDRESS: address = @0xCAFE;
    const PLAYER_ADDRESS: address = @0xBEEF;
    const INITIAL_BALANCE: u64 = 100_000_000_000; // 100 SUI

    // Helper function to create a test coin
    fun mint_coin(amount: u64, scenario: &mut Scenario): Coin<SUI> {
        coin::mint_for_testing<SUI>(amount, ts::ctx(scenario))
    }

    #[test]
    fun test_house_initialization() {
        let mut scenario = ts::begin(HOUSE_ADDRESS);
        
        // Initialize house_data module (simulates package publish)
        {
            satoshi_flip::house_data::init_for_testing(ts::ctx(&mut scenario));
        };

        // House initializes with HouseCap
        ts::next_tx(&mut scenario, HOUSE_ADDRESS);
        {
            let house_cap = ts::take_from_sender<HouseCap>(&scenario);
            let coin = mint_coin(INITIAL_BALANCE, &mut scenario);
            let public_key = vector[1, 2, 3, 4]; // Dummy public key
            
            house_data::initialize_house_data(house_cap, coin, public_key, ts::ctx(&mut scenario));
        };

        // Verify house data was created correctly
        ts::next_tx(&mut scenario, HOUSE_ADDRESS);
        {
            let house_data = ts::take_shared<HouseData>(&scenario);
            
            assert!(house_data::balance(&house_data) == INITIAL_BALANCE, 0);
            assert!(house_data::house(&house_data) == HOUSE_ADDRESS, 1);
            assert!(house_data::min_stake(&house_data) == 1_000_000_000, 2);
            assert!(house_data::max_stake(&house_data) == 50_000_000_000, 3);
            assert!(house_data::base_fee_in_bp(&house_data) == 100, 4);
            assert!(house_data::fees(&house_data) == 0, 5);
            
            ts::return_shared(house_data);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_top_up_house() {
        let mut scenario = ts::begin(HOUSE_ADDRESS);
        
        // Initialize
        {
            satoshi_flip::house_data::init_for_testing(ts::ctx(&mut scenario));
        };

        ts::next_tx(&mut scenario, HOUSE_ADDRESS);
        {
            let house_cap = ts::take_from_sender<HouseCap>(&scenario);
            let coin = mint_coin(INITIAL_BALANCE, &mut scenario);
            let public_key = vector[1, 2, 3, 4];
            house_data::initialize_house_data(house_cap, coin, public_key, ts::ctx(&mut scenario));
        };

        // Top up house
        ts::next_tx(&mut scenario, HOUSE_ADDRESS);
        {
            let mut house_data = ts::take_shared<HouseData>(&scenario);
            let top_up_amount = 50_000_000_000; // 50 SUI
            let coin = mint_coin(top_up_amount, &mut scenario);
            
            house_data::top_up(&mut house_data, coin, ts::ctx(&mut scenario));
            
            assert!(house_data::balance(&house_data) == INITIAL_BALANCE + top_up_amount, 0);
            
            ts::return_shared(house_data);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_withdraw_from_house() {
        let mut scenario = ts::begin(HOUSE_ADDRESS);
        
        // Initialize
        {
            satoshi_flip::house_data::init_for_testing(ts::ctx(&mut scenario));
        };

        ts::next_tx(&mut scenario, HOUSE_ADDRESS);
        {
            let house_cap = ts::take_from_sender<HouseCap>(&scenario);
            let coin = mint_coin(INITIAL_BALANCE, &mut scenario);
            let public_key = vector[1, 2, 3, 4];
            house_data::initialize_house_data(house_cap, coin, public_key, ts::ctx(&mut scenario));
        };

        // Withdraw from house
        ts::next_tx(&mut scenario, HOUSE_ADDRESS);
        {
            let mut house_data = ts::take_shared<HouseData>(&scenario);
            let withdraw_amount = 20_000_000_000; // 20 SUI
            
            let withdrawn = house_data::withdraw(&mut house_data, withdraw_amount, ts::ctx(&mut scenario));
            
            assert!(coin::value(&withdrawn) == withdraw_amount, 0);
            assert!(house_data::balance(&house_data) == INITIAL_BALANCE - withdraw_amount, 1);
            
            test_utils::destroy(withdrawn);
            ts::return_shared(house_data);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_update_stake_limits() {
        let mut scenario = ts::begin(HOUSE_ADDRESS);
        
        // Initialize
        {
            satoshi_flip::house_data::init_for_testing(ts::ctx(&mut scenario));
        };

        ts::next_tx(&mut scenario, HOUSE_ADDRESS);
        {
            let house_cap = ts::take_from_sender<HouseCap>(&scenario);
            let coin = mint_coin(INITIAL_BALANCE, &mut scenario);
            let public_key = vector[1, 2, 3, 4];
            house_data::initialize_house_data(house_cap, coin, public_key, ts::ctx(&mut scenario));
        };

        // Update stake limits
        ts::next_tx(&mut scenario, HOUSE_ADDRESS);
        {
            let mut house_data = ts::take_shared<HouseData>(&scenario);
            let new_min = 500_000_000; // 0.5 SUI
            let new_max = 100_000_000_000; // 100 SUI
            
            house_data::update_stake_limits(&mut house_data, new_min, new_max, ts::ctx(&mut scenario));
            
            assert!(house_data::min_stake(&house_data) == new_min, 0);
            assert!(house_data::max_stake(&house_data) == new_max, 1);
            
            ts::return_shared(house_data);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = house_data::ECallerNotHouse)]
    fun test_withdraw_not_house_fails() {
        let mut scenario = ts::begin(HOUSE_ADDRESS);
        
        // Initialize
        {
            satoshi_flip::house_data::init_for_testing(ts::ctx(&mut scenario));
        };

        ts::next_tx(&mut scenario, HOUSE_ADDRESS);
        {
            let house_cap = ts::take_from_sender<HouseCap>(&scenario);
            let coin = mint_coin(INITIAL_BALANCE, &mut scenario);
            let public_key = vector[1, 2, 3, 4];
            house_data::initialize_house_data(house_cap, coin, public_key, ts::ctx(&mut scenario));
        };

        // Non-house tries to withdraw - should fail
        ts::next_tx(&mut scenario, PLAYER_ADDRESS);
        {
            let mut house_data = ts::take_shared<HouseData>(&scenario);
            
            // This should fail with ECallerNotHouse
            let withdrawn = house_data::withdraw(&mut house_data, 1000, ts::ctx(&mut scenario));
            
            test_utils::destroy(withdrawn);
            ts::return_shared(house_data);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = house_data::EInsufficientBalance)]
    fun test_withdraw_insufficient_balance_fails() {
        let mut scenario = ts::begin(HOUSE_ADDRESS);
        
        // Initialize
        {
            satoshi_flip::house_data::init_for_testing(ts::ctx(&mut scenario));
        };

        ts::next_tx(&mut scenario, HOUSE_ADDRESS);
        {
            let house_cap = ts::take_from_sender<HouseCap>(&scenario);
            let coin = mint_coin(INITIAL_BALANCE, &mut scenario);
            let public_key = vector[1, 2, 3, 4];
            house_data::initialize_house_data(house_cap, coin, public_key, ts::ctx(&mut scenario));
        };

        // Try to withdraw more than balance
        ts::next_tx(&mut scenario, HOUSE_ADDRESS);
        {
            let mut house_data = ts::take_shared<HouseData>(&scenario);
            
            // This should fail with EInsufficientBalance
            let withdrawn = house_data::withdraw(&mut house_data, INITIAL_BALANCE + 1, ts::ctx(&mut scenario));
            
            test_utils::destroy(withdrawn);
            ts::return_shared(house_data);
        };

        ts::end(scenario);
    }
}
