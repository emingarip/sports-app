---
description: Rules and security constraints for the K-Coin Virtual Economy
---

# K-Coin Economy Workflow

When developing features that give, deduct, or check K-Coin balances, ALWAYS follow these strict security and architectural rules:

## 1. Zero Trust Client (Security First)
- **NEVER** trust the client (Flutter app) to update balances directly. For example, `supabase.from('profiles').update({'k_coin_balance': newBalance})` is strictly FORBIDDEN.
- All coin grants (rewards/purchases) and deductions (spending) MUST be performed via secured **Supabase RPC (PostgreSQL Functions)** or **Edge Functions**.

## 2. Mandatory Transaction Logs (Ledger)
- Every single change to a user's K-Coin balance must be accompanied by an `INSERT` into the `k_coin_transactions` table. The balance and the ledger must always match.
- A transaction must record the `user_id`, `amount` (positive or negative), `transaction_type` (e.g., `daily_reward`, `chat_animation`, `iap_purchase`), and `reference_id`.

## 3. Admin-Driven Configuration
- Rewards and Package data must NOT be hardcoded in the Flutter app.
- Fetch available packages from the `k_coin_packages` table.
- Fetch reward amounts and limits from the `k_coin_reward_rules` table.

## 4. Strict Testing Requirement
- Any new Edge Function or Postgres RPC dealing with K-Coins must have a corresponding automated test.
- Tests must explicitly verify that balances cannot drop below zero (constraint checks) and that the transaction ledger logs exactly match the profile balance changes.
