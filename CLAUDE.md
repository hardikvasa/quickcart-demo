# QuickCart — project guide for Claude

QuickCart is a tiny static storefront. No build step, no dependencies.

- `index.html` — markup. The cart total is shown in the element with
  `id="cart-total"` (also `data-testid="cart-total"`).
- `styles.css` — styling only.
- `app.js` — all cart logic and rendering. Products and the initial cart
  live at the top of the file.

## Conventions

- Vanilla JavaScript only. Do not add frameworks, build tools, or npm
  dependencies.
- Keep changes minimal and surgical. Fix the reported bug and nothing else —
  do not refactor unrelated code or restyle the page.
- Money is in US dollars, formatted by `formatMoney()` as `$X.XX`.

## Verifying a change

There is no test runner. To sanity-check the cart total, compute the expected
value by hand from the items in the initial cart and confirm `cartTotal()`
returns it. The displayed total must equal the sum of each line item's
`price * quantity`.
