module satoshi_flip::house_data {

    use sui::object::{Self, UID};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::package;
    use sui::tx_context::TxContext;
    use sui::transfer;

    const ECallerNotHouse: u64 = 0;
    const EInsufficientBalance: u64 = 1;

    public struct HouseData has key {
        id: UID,
        balance: Balance<SUI>,
        house: address,
        public_key: vector<u8>,
        max_stake: u64,
        min_stake: u64,
        fees: Balance<SUI>,
        base_fee_in_bp: u16
    }

    public struct HouseCap has key {
        id: UID
    }

    public struct HOUSE_DATA has drop {}

    fun init(otw: HOUSE_DATA, ctx: &mut TxContext) {
        package::claim_and_keep(otw, ctx);

        let house_cap = HouseCap {
            id: object::new(ctx)
        };

        transfer::transfer(house_cap, ctx.sender());
    }

    public fun initialize_house_data(house_cap: HouseCap, coin: Coin<SUI>, public_key: vector<u8>, ctx: &mut TxContext) {
        assert!(coin::value(&coin) > 0, EInsufficientBalance);

        let house_data = HouseData {
            id: object::new(ctx),
            balance: coin::into_balance(coin),
            house: ctx.sender(),
            public_key,
            max_stake: 50_000_000_000, // 50 SUI.
            min_stake: 1_000_000_000, // 1 SUI.
            fees: balance::zero(),
            base_fee_in_bp: 100 // 1% in basis points.
        };

        let HouseCap { id } = house_cap;
        object::delete(id);

        transfer::share_object(house_data);
    }
}
