# AI usage log

Tools used: Antigravity Agent (DeepMind Advanced Agentic Coding), Claude 3.5 Sonnet / Gemini 1.5 Pro

## Significant prompts (5–10)

| # | What I asked (summary is fine) | What I did with the answer |
|---|---|---|
| 1 | Analyze Git history, current branch, and inspect project architecture and protected files. | Established workspace baseline, verified protected boundaries (`lib/mock_server/`, `lib/core/network/transport.dart`), and confirmed clean commit state. |
| 2 | Investigate root cause for QK-101 (cart mutations not persisting across app restart). | Verified missing `await _storage.save()` in `decrement()`, `remove()`, and `removeCoupon()`. Created failing test `da42288` then fix `e29034b`. |
| 3 | Investigate root cause for QK-102 (stale prices on refresh and missing orders after checkout). | Identified unconditional 10-minute caching in `ApiClient._responseCache`. Implemented `forceRefresh`, cache invalidation, and orders provider refresh. |
| 4 | Search codebase for boundary and precision bugs in pricing and catalog deserialization. | Discovered BUG-3 (threshold strict inequality), BUG-4 (legacy product crash), BUG-5 (float truncation in `rupeesToPaise`), and BUG-6 (`formatMoney` dropped paise). |
| 5 | Design idempotent checkout architecture with automatic and manual retries under network drop. | Built `_idempotencyKey` lifecycle tied to logical order cart snapshot, ensuring identical key and payload on retries. |
| 6 | Formulate contract-compliant `CartReconciler.reconcile` implementation handling batching and coupons. | Implemented batch chunking (max 50), stock/maxPerOrder clamping, discontinued product exclusion, and coupon validation. |
| 7 | Design offline remote configuration caching and leak-free live updates in Riverpod 2. | Implemented `ConfigRepository.load()` with offline persistent storage and `AppConfigController` with proper subscription cancellation in `onDispose`. |
| 8 | Implement segment-by-segment numeric version comparator for `UpdatePolicy.evaluate`. | Built robust parser that handles missing trailing segments, numeric segments, and safely returns `none` on malformed inputs. |
| 9 | Investigate lost response manual retry lifecycle when server inventory decrements on first attempt. | Identified that pre-reconciliation on manual retry sees 0 stock and resets the key. Formulated recovery bypass for unresolved key with identical payload. |
| 10 | Analyze bare ProviderContainer lifecycle in Riverpod 2 Notifier to guarantee hydration without manual main.dart bootstrap. | Implemented asynchronous self-hydration via `Future.microtask` guarded by `_hydrated` flag to avoid duplicate fetches during bootstrap. |

## When the AI was wrong or misleading (at least 3)

### 1. Generating a fresh Idempotency-Key on every checkout retry
- **What it suggested:** Standard AI scaffolding suggested creating a new `Uuid().v4()` inside `placeOrder()` every time the checkout method was invoked.
- **Why it was wrong:** Generating a new key on retry defeats the entire purpose of idempotency. If a checkout request times out because the server created the order but the response packet was lost on a flaky mobile network, sending a new key on retry creates a duplicate order and charges the customer twice!
- **How I noticed:** Reviewed `docs/API_CONTRACT.md` and Section 4.3 of the assignment brief, which explicitly mandates: *"A retry of the same logical order must reuse the same idempotency key and the same request payload. Do not generate a new key for every retry."*
- **What I did instead:** Maintained `_idempotencyKey` and `_logicalOrderCart` across retries. The key is preserved across timeouts and retried with the exact same payload. The key is only cleared after confirmed `CheckoutSuccess` or when the user modifies their cart contents.

### 2. Using alphabetical string comparison for semantic version evaluation
- **What it suggested:** Suggested implementing `UpdatePolicy.evaluate` using `currentVersion.compareTo(minSupportedVersion) < 0`.
- **Why it was wrong:** Lexicographical string comparison fails for multi-digit version numbers: `'1.10.0'.compareTo('1.4.0')` returns negative (`-1`) because `'1'` < `'4'`. It would falsely mark version 1.10.0 as older than 1.4.0, locking modern users out of the application with a false "Update required" screen.
- **How I noticed:** Examined `docs/BUSINESS_RULES.md § 7` and the contract in `lib/features/app_config/domain/update_policy.dart` which explicitly instructs: *"Versions are dotted numbers like 1.4.0, 1.10.2, 2.0. Compare them numerically, segment by segment. Missing segments count as 0."*
- **What I did instead:** Implemented an integer segment comparator (`_parseVersion` and `_compare`) that parses non-negative integers, treats omitted trailing segments as zero (`1.4 == 1.4.0`), and safely returns `UpdateRequirement.none` if any version string contains letters or malformed tokens.

### 3. Truncating floating-point numbers in currency conversion (`(rupees * 100).toInt()`)
- **What it suggested:** Suggested casting double rupees to paise with `(rupees * 100).toInt()`.
- **Why it was wrong:** In binary floating-point representation (IEEE-754), numbers like `49.99` cannot be represented exactly. `49.99 * 100` evaluates to `4998.999999999999`. Calling `.toInt()` truncates towards zero, producing `4998` instead of `4999`. At checkout, the client sent 4998 paise, causing the backend to reject orders with `409 PRICE_CHANGED`.
- **How I noticed:** Audited `lib/core/utils/money.dart` and checked decimal prices in `catalog_seed.dart` (`19.99`, `79.99`, `17.99`). The off-by-one paisa discrepancy was immediately apparent.
- **What I did instead:** Replaced `.toInt()` with `.round()`, correctly rounding `4998.999999999999` to `4999` and preserving price accuracy.

### 4. Silently accepting price increases under a small threshold
- **What it suggested:** Suggested automatically accepting price increases under ₹10 or 5% during reconciliation to avoid checkout friction.
- **Why it was wrong:** Directly violates `docs/BUSINESS_RULES.md § 5`: *"Customers only pay amounts they have agreed to... a higher price... must be shown to the customer, who confirms before ordering."*
- **How I noticed:** Checked `BUSINESS_RULES.md` and the `PriceChanged` domain model (`bool get requiresUserReview => isIncrease;`).
- **What I did instead:** Strictly enforced that every price increase, stock reduction, or coupon invalidation requires explicit user review and confirmation via `_ReconciliationReviewSheet` and `CheckoutNeedsReview`.

### 5. Running pre-checkout reconciliation on manual retry after lost response
- **What it suggested:** Suggested running `CartReconciler.reconcile()` unconditionally before every checkout attempt, including manual retries after timeouts.
- **Why it was wrong:** If the first checkout attempt succeeded on the backend but the response was lost on a flaky network, the backend had already created the order and decremented inventory (e.g. from 1 unit down to 0). Running pre-reconciliation on retry queries `/v1/products/batch`, detects 0 stock, classifies the line as `OutOfStock`, removes it from the cart, and destroys `_idempotencyKey`! This destroys recovery identity and fails an order that was actually placed.
- **How I noticed:** Traced the idempotency contract in `MockServer._handleOrdersPost()`, where existing keys are resolved before checking inventory. Pre-reconciliation prevented the server from ever receiving the retry with the existing key.
- **What I did instead:** Preserved `_idempotencyKey` and `_logicalOrderCart` across retries. When retrying the identical cart, pre-reconciliation is bypassed so the existing key and payload are directly submitted to `OrderApi.placeOrder()`, recovering the created order (`200 OK`).

## What I would NOT trust an AI with in this codebase, and why

- **Financial and currency calculation semantics**: AI models frequently confuse rupees and paise, introduce floating-point inaccuracies, or use naive inequality checks (e.g. `>` instead of `>=` on discount thresholds). In a delivery platform, a single paisa discrepancy causes payment gateway mismatches and order rejections.
- **Idempotency boundaries and distributed state lifecycles**: AI commonly treats network timeouts as simple exceptions to be caught and blindly retried with new random request IDs. In distributed systems, a timeout means the state is unknown; understanding the idempotency key contract requires deep architectural judgment.
- **Silent divergence from business rules**: LLMs often bias towards "smooth user experience" patterns seen in general tutorials (such as auto-updating carts without prompting or silently ignoring coupon expirations), which directly violates strict legal and business requirements. Human engineering review against authoritative product rules is indispensable.
