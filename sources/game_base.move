/// Module: satoshi_flip::game_base
///
/// Shared primitives for all games in the satoshi_flip package.
/// Centralizes fee calculation, payout math, and stake validation so each
/// game module (single_player, dice, lottery) doesn't duplicate logic.
///
/// Design: pure functions only — no state, no object creation.
/// Games import this module and call these helpers directly.
module satoshi_flip::game_base {

    use satoshi_flip::house_data::HouseData;

    // ==================== Error Codes ====================

    /// Stake is below the house minimum
    const EStakeTooLow: u64 = 100;
    /// Stake is above the house maximum
    const EStakeTooHigh: u64 = 101;
    /// Multiplier would overflow u64
    const EMultiplierOverflow: u64 = 102;

    // ==================== Stake Validation ====================

    /// Validate that a stake amount is within the house-configured bounds.
    /// Aborts with EStakeTooLow or EStakeTooHigh if out of range.
    public fun validate_stake(amount: u64, house_data: &HouseData) {
        assert!(amount >= house_data::min_stake(house_data), EStakeTooLow);
        assert!(amount <= house_data::max_stake(house_data), EStakeTooHigh);
    }

    // ==================== Fee Calculation ====================

    /// Calculate the house fee on a given stake amount.
    /// fee_bp is in basis points (100 bp = 1%).
    ///
    /// Returns fee in MIST (the same unit as the stake).
    ///
    /// Example: stake=1_000_000, fee_bp=100 (1%) => fee=10_000
    public fun calculate_fee(stake: u64, fee_bp: u16): u64 {
        (stake as u128 * (fee_bp as u128) / 10_000u128) as u64
    }

    // ==================== Payout Calculation ====================

    /// Calculate the total payout to a winner.
    ///
    /// Payout = (stake * multiplier_numerator / multiplier_denominator) - fee
    ///
    /// For a coin flip (2:1 payout): multiplier_numerator=2, multiplier_denominator=1
    /// For a dice game (6:1 payout): multiplier_numerator=6, multiplier_denominator=1
    ///
    /// Returns (payout, fee) where payout is what the winner receives
    /// and fee is what the house takes.
    public fun calculate_payout(
        stake: u64,
        multiplier_numerator: u64,
        multiplier_denominator: u64,
        fee_bp: u16
    ): (u64, u64) {
        assert!(multiplier_denominator > 0, EMultiplierOverflow);
        let gross = (stake as u128) * (multiplier_numerator as u128) / (multiplier_denominator as u128);
        let fee   = calculate_fee(stake, fee_bp) as u128;
        let net   = if (gross > fee) { gross - fee } else { 0 };
        (net as u64, fee as u64)
    }

    // ==================== House Balance Check ====================

    /// Check that the house has enough balance to cover a potential payout.
    /// Aborts if insufficient.
    ///
    /// Required balance = stake * multiplier_numerator / multiplier_denominator
    /// (gross payout — house needs to cover the max possible win)
    public fun assert_house_can_cover(
        stake: u64,
        multiplier_numerator: u64,
        multiplier_denominator: u64,
        house_balance: u64
    ) {
        let required = (stake as u128) * (multiplier_numerator as u128) / (multiplier_denominator as u128);
        assert!(house_balance >= (required as u64), 2); // EInsufficientHouseBalance
    }
}
