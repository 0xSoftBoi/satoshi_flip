```markdown
# satoshi_flip Development Patterns

> Auto-generated skill from repository analysis

## Overview
This skill covers the key development patterns and conventions used in the `satoshi_flip` TypeScript codebase. It documents file naming, import/export styles, testing patterns, and provides guidance for maintaining consistency across the project. While no specific automation workflows were detected, this guide will help you onboard quickly and contribute effectively.

## Coding Conventions

### File Naming
- **Pattern:** PascalCase  
  Example:  
  ```plaintext
  SatoshiFlipGame.ts
  PlayerWallet.ts
  ```

### Import Style
- **Pattern:** Relative imports  
  Example:  
  ```typescript
  import { CoinFlip } from './CoinFlip';
  import { getRandomNumber } from '../utils/Random';
  ```

### Export Style
- **Pattern:** Named exports  
  Example:  
  ```typescript
  export function flipCoin() { ... }
  export const SATOSHI_UNIT = 100_000_000;
  ```

### Commit Messages
- **Pattern:** Freeform, no strict prefixes  
  - Average length: ~61 characters  
  Example:  
  ```
  Add coin flip logic and update player balance after flip
  ```

## Workflows

_No automated workflows detected in this repository._  
You may wish to add workflows for building, testing, or linting in the future.

## Testing Patterns

- **Test Framework:** Unknown (no framework detected)
- **Test File Pattern:** Files are named with `.test.ts` suffix  
  Example:  
  ```plaintext
  CoinFlip.test.ts
  Wallet.test.ts
  ```
- **Test Structure:**  
  - Tests are colocated with source files or in a parallel structure.
  - To run tests, use your preferred TypeScript test runner (e.g., Jest, Mocha).

## Commands

| Command   | Purpose                                      |
|-----------|----------------------------------------------|
| /test     | Run all test files matching `*.test.ts`      |
| /lint     | (Suggested) Lint the codebase for style      |
| /build    | (Suggested) Compile the TypeScript sources   |

> _Note: Since no workflows were detected, `/test`, `/lint`, and `/build` are suggested commands for common developer actions. Implement these as needed in your project._
```