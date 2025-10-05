# Clarity Examples Official

Production-grade smart contract collection from Trust Machines with enterprise-level Clarity implementations.

## Overview

This repository contains two educational but production-ready smart contracts that demonstrate advanced Clarity programming patterns and DeFi primitives:

1. **Borrowing Protocol Example** - Educational borrowing system with collateral management
2. **Yield Calculator Example** - Example yield calculation and distribution mechanism

## Contracts

### 1. Borrowing Protocol Example (`borrowing-protocol-example.clar`)

A sophisticated lending protocol that allows users to deposit collateral, create loans, and manage debt with automated liquidation mechanisms.

#### Key Features:
- **Collateral Management**: Users can deposit and withdraw STX as collateral
- **Over-collateralized Loans**: Minimum 150% collateralization ratio
- **Interest Calculation**: Dynamic interest accrual based on time elapsed
- **Liquidation System**: Automated liquidation when collateral ratio falls below 120%
- **Real-time Health Monitoring**: Track loan health and liquidation risk

#### Core Functions:
- `deposit-collateral(amount)` - Deposit STX as collateral
- `create-loan(collateral-amount, borrow-amount)` - Create a new loan
- `repay-loan(loan-id)` - Repay loan with interest
- `liquidate-loan(loan-id)` - Liquidate undercollateralized positions
- `withdraw-collateral(amount)` - Withdraw available collateral

#### Configuration:
- Minimum collateral ratio: 150%
- Liquidation threshold: 120%
- Liquidation penalty: 10%
- Interest rate: 0.01% per block

### 2. Yield Calculator Example (`yield-calculator-example.clar`)

A comprehensive yield farming and staking platform that supports multiple pools with different APY rates and lock periods.

#### Key Features:
- **Multi-Pool Support**: Up to 10 different yield pools
- **Flexible Staking**: Configurable minimum amounts and lock periods
- **Compound Rewards**: Ability to automatically restake rewards
- **Yield Projections**: Calculate expected returns over time
- **Admin Controls**: Pool management and APY adjustments

#### Core Functions:
- `create-pool(name, token-symbol, apy-rate, min-stake-amount, lock-period)` - Create new yield pool
- `stake-tokens(pool-id, amount)` - Stake tokens in a specific pool
- `claim-rewards(pool-id)` - Claim accumulated rewards
- `compound-rewards(pool-id)` - Reinvest rewards for compound growth
- `unstake-tokens(pool-id)` - Unstake tokens and claim final rewards

#### Pool Configuration:
- APY rates in basis points (10000 = 100%)
- Customizable minimum stake amounts
- Flexible lock periods in blocks
- Per-pool activation controls

## Getting Started

### Prerequisites
- [Clarinet](https://docs.hiro.so/clarinet/) installed
- Basic knowledge of Clarity smart contracts
- Understanding of DeFi concepts

### Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd clarity-examples-official
```

2. Install dependencies:
```bash
npm install
```

3. Validate contracts:
```bash
clarinet check
```

4. Run tests:
```bash
npm test
```

## Usage Examples

### Borrowing Protocol

```clarity
;; Deposit 1000 STX as collateral
(contract-call? .borrowing-protocol-example deposit-collateral u1000000000)

;; Create a loan with 800 STX collateral, borrowing 400 STX
(contract-call? .borrowing-protocol-example create-loan u800000000 u400000000)

;; Check loan health
(contract-call? .borrowing-protocol-example get-loan-health u1)

;; Repay loan with interest
(contract-call? .borrowing-protocol-example repay-loan u1)
```

### Yield Calculator

```clarity
;; Create a high-yield pool (20% APY)
(contract-call? .yield-calculator-example create-pool "High Yield" "HYP" u2000 u100000000 u144)

;; Stake 500 STX in pool 1
(contract-call? .yield-calculator-example stake-tokens u1 u500000000)

;; Check pending rewards
(contract-call? .yield-calculator-example calculate-pending-rewards tx-sender u1)

;; Compound rewards for exponential growth
(contract-call? .yield-calculator-example compound-rewards u1)
```

## Architecture

### Security Features
- Comprehensive error handling with descriptive error codes
- Input validation and authorization checks
- Protection against common attack vectors
- Careful handling of arithmetic operations

### Data Structures
- Efficient mapping structures for user data
- Optimized storage patterns
- Proper indexing for quick lookups

### Mathematical Precision
- High-precision calculations for interest and yields
- Safe arithmetic operations to prevent overflow
- Accurate time-based calculations

## Testing

The contracts include comprehensive test suites written in TypeScript using the Clarinet testing framework:

```bash
# Run all tests
npm test

# Run specific contract tests
npm test borrowing-protocol-example
npm test yield-calculator-example
```

## Deployment

### Testnet Deployment
```bash
clarinet integrate
```

### Mainnet Deployment
1. Review all contract code and tests
2. Perform security audit
3. Deploy using Clarinet or Hiro Platform
4. Verify contract deployment

## Security Considerations

⚠️ **Important**: These contracts are for educational purposes. Before using in production:

- Conduct thorough security audits
- Test extensively on testnet
- Consider oracle integration for price feeds
- Implement proper governance mechanisms
- Add emergency pause functionality
- Review economic parameters

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run `clarinet check` to validate
6. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For questions and support:
- [Hiro Documentation](https://docs.hiro.so/)
- [Clarity Language Reference](https://docs.stacks.co/clarity/)
- [Trust Machines GitHub](https://github.com/trust-machines)

## Acknowledgments

- Trust Machines team for enterprise-level guidance
- Hiro Systems for Clarity development tools
- Stacks community for feedback and testing

---

**Disclaimer**: These smart contracts are provided as educational examples. Always conduct proper testing and audits before deploying to mainnet.