# Session 5: POS design notes

POS receipts are immutable inserts. `create_sale()` deliberately has no
`p_id` or `p_total`: a database counter creates `POS-YYMM####` numbers, and
the function reads `business_settings.vat_rate` before calculating the total.
The SQL calculation mirrors the frontend preview: cap line discounts, cap the
whole-sale discount, prorate it across taxable lines, then round VAT and total
to two decimal places. The browser’s total remains a preview only.

Every sale locks its product rows in a stable UUID order, verifies stock while
the locks are held, then inserts the receipt/lines/payments, deducts stock and
records `stock_movements` in one transaction. This is the Session 1
`adjust_product_stock()` pattern applied to a multi-product sale; concurrent
sales cannot both sell the last unit. The old browser stock-blocking guard was
removed rather than retained as a second source of authority.

Payments are individual `sale_payments` rows. Cash may exceed the calculated
total (the receipt derives the change); the combined non-cash legs may not.
This supports cash, mobile money, card, bank transfer and any split of them.

`create_sale_return()` keeps returns/exchanges linked to the original receipt
and exact sale line. It prevents cumulative returned quantity from exceeding
what was sold, restores returned stock, and check-then-deducts a replacement
in the same transaction. Its `approval_state` persists the existing “Pending
manager approval” UI state, but does not enforce authorization: staff identity
and manager enforcement remain Sessions 7 and 9 respectively.

All new business records carry `branch_id`; cashier and stock movement actor
remain descriptive text until Session 7, consistent with the existing schema.
RLS remains intentionally off until authentication/policies are introduced.
