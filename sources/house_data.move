module satoshi_flip::house_data {

    use sui::object::{Self, UID};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::package;
    use sui::tx_context::TxContext;
    use sui::transfer;
    use sui::event;

    const ECallerNotHouse: u64 = 0;
    const EInsufficientBalance: u64 = 1;

    // ==================== Events ====================

    /// Emitted when house is initialized
    public struct HouseInitialized has copy, drop {
        house: address,
        initial_balance: u64
    }

    /// Emitted when house balance changes
    public struct HouseBalanceChanged has copy, drop {
        house: address,
        old_balance: u64,
        new_balance: u64,
        is_deposit: bool
    }

    /// Emitted when fees are withdrawn
    public struct FeesWithdrawn has copy, drop {
        house: address,
        amount: u64
    }

    /// Emitted when stake limits are updated
    public struct StakeLimitsUpdated has copy, drop {
        house: address,
        min_stake: u64,
        max_stake: u64
    }

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
        let initial_balance = coin::value(&coin);
        assert!(initial_balance > 0, EInsufficientBalance);

        let house_addr = ctx.sender();

        let house_data = HouseData {
            id: object::new(ctx),
            balance: coin::into_balance(coin),
            house: house_addr,
            public_key,
            max_stake: 50_000_000_000, // 50 SUI.
            min_stake: 1_000_000_000, // 1 SUI.
            fees: balance::zero(),
            base_fee_in_bp: 100 // 1% in basis points.
        };

        // Emit initialization event
        event::emit(HouseInitialized {
            house: house_addr,
            initial_balance
        });

        let HouseCap { id } = house_cap;
        object::delete(id);

        transfer::share_object(house_data);
    }

    // ==================== Getter Functions ====================

    /// Returns the balance of the house
    public fun balance(house_data: &HouseData): u64 {
        balance::value(&house_data.balance)
    }

    /// Returns the address of the house
    public fun house(house_data: &HouseData): address {
        house_data.house
    }

    /// Returns the public key of the house
    public fun public_key(house_data: &HouseData): vector<u8> {
        house_data.public_key
    }

    /// Returns the max stake of the house
    public fun max_stake(house_data: &HouseData): u64 {
        house_data.max_stake
    }

    /// Returns the min stake of the house
    public fun min_stake(house_data: &HouseData): u64 {
        house_data.min_stake
    }

    /// Returns the fees balance of the house
    public fun fees(house_data: &HouseData): u64 {
        balance::value(&house_data.fees)
    }

    /// Returns the base fee in basis points
    public fun base_fee_in_bp(house_data: &HouseData): u16 {
        house_data.base_fee_in_bp
    }

    /// Returns mutable reference to the balance of the house (for game module)
    public(package) fun borrow_balance_mut(house_data: &mut HouseData): &mut Balance<SUI> {
        &mut house_data.balance
    }

    /// Returns mutable reference to the fees of the house (for game module)
    public(package) fun borrow_fees_mut(house_data: &mut HouseData): &mut Balance<SUI> {
        &mut house_data.fees
    }

    // ==================== House Management Functions ====================

    /// House can withdraw the accumulated fees
    public fun withdraw_fees(house_data: &mut HouseData, ctx: &mut TxContext): Coin<SUI> {
        assert!(ctx.sender() == house_data.house, ECallerNotHouse);
        let total_fees = balance::value(&house_data.fees);
        
        // Emit event
        event::emit(FeesWithdrawn {
            house: house_data.house,
            amount: total_fees
        });

        coin::take(&mut house_data.fees, total_fees, ctx)
    }

    /// House can withdraw from the house balance (profits)
    public fun withdraw(house_data: &mut HouseData, amount: u64, ctx: &mut TxContext): Coin<SUI> {
        assert!(ctx.sender() == house_data.house, ECallerNotHouse);
        let old_balance = balance::value(&house_data.balance);
        assert!(old_balance >= amount, EInsufficientBalance);
        
        // Emit event
        event::emit(HouseBalanceChanged {
            house: house_data.house,
            old_balance,
            new_balance: old_balance - amount,
            is_deposit: false
        });

        coin::take(&mut house_data.balance, amount, ctx)
    }

    /// House can top up the balance
    public fun top_up(house_data: &mut HouseData, coin: Coin<SUI>, _ctx: &mut TxContext) {
        let old_balance = balance::value(&house_data.balance);
        let deposit_amount = coin::value(&coin);
        
        // Emit event
        event::emit(HouseBalanceChanged {
            house: house_data.house,
            old_balance,
            new_balance: old_balance + deposit_amount,
            is_deposit: true
        });

        coin::put(&mut house_data.balance, coin);
    }

    /// House can update the min and max stake limits
    public fun update_stake_limits(
        house_data: &mut HouseData, 
        min_stake: u64, 
        max_stake: u64, 
        ctx: &mut TxContext
    ) {
        assert!(ctx.sender() == house_data.house, ECallerNotHouse);
        house_data.min_stake = min_stake;
        house_data.max_stake = max_stake;

        // Emit event
        event::emit(StakeLimitsUpdated {
            house: house_data.house,
            min_stake,
            max_stake
        });
    }

    /// House can update the base fee
    public fun update_base_fee(
        house_data: &mut HouseData, 
        base_fee_in_bp: u16, 
        ctx: &mut TxContext
    ) {
        assert!(ctx.sender() == house_data.house, ECallerNotHouse);
        house_data.base_fee_in_bp = base_fee_in_bp;
    }

    // ==================== Test-only Functions ====================

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(HOUSE_DATA {}, ctx);
    }
}
