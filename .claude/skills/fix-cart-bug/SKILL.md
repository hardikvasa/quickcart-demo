---
name: fix-cart-bug
description: Use when fixing a reported bug in the QuickCart store, especially anything about the cart, prices, line items, or the order total being wrong. Provides the procedure for diagnosing and making a minimal, correct fix.
---

# Fixing a QuickCart bug

Follow this procedure when an issue reports incorrect behavior in the store.

## 1. Reproduce from the report

Read the issue carefully. Identify the expected behavior versus what the user
sees. For total/price issues, work out the correct number by hand from the
items in the initial cart (each line is `price * quantity`, summed).

## 2. Locate the responsible code

All cart logic lives in `app.js`. The functions to look at first:

- `cartTotal()` — computes the number shown as the order total.
- `renderCart()` — renders line items and writes the total into the page.
- `PRODUCTS` / `cart` — the product catalog and the initial cart contents.

Trace how the displayed value is produced before changing anything.

## 3. Make the minimal fix

Change only what is needed to correct the reported behavior. Do not refactor,
rename, restyle, or "improve" unrelated code. Preserve the existing code style
and formatting.

## 4. Verify

Compute the expected result by hand and confirm the corrected code produces it.
For the default cart, sum each item's `price * quantity` across all line items
and check that `cartTotal()` returns exactly that dollar amount.

## 5. Summarize

State what was wrong, the one-line root cause, and the exact change you made.
