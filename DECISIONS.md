# Decisions & trade-offs

> Short and specific beats long and generic. Bullet points are fine.

## 1. Cart reconciliation policy (Feature 1)

- **When does reconciliation run, and why there?**
  - **Pre-checkout (`CheckoutController.placeOrder`)**: Reconciliation runs immediately before placing an order. This ensures the customer is never charged an amount, price, or quantity different from what the backend expects, guaranteeing zero un-reviewed price increases or stock rejections.
  - **Post-conflict handling (HTTP 409 responses)**: In addition to pre-checkout checks, if a race condition occurs where prices drift or stock depletes in the exact millisecond between reconciliation and `_placeOrder`, any `409` conflict (`PRICE_CHANGED`, `INSUFFICIENT_STOCK`, `PRODUCT_UNAVAILABLE`, `COUPON_INVALID`, `TOTAL_MISMATCH`) immediately triggers a re-reconciliation, updates the local cart, and prompts the user with `CheckoutNeedsReview`.
  - **Why not on every cart screen build?** Running full batch product and coupon network calls on every build or scroll would spam the backend and introduce jarring loading flickers while the user is simply reviewing their basket.
- **What does the user see for each kind of change?**
  - **Price increase**: Shown in a bottom sheet review (`_ReconciliationReviewSheet`) displaying old price vs. new price (`PriceChanged.isIncrease == true`). Checkout halts with `CheckoutNeedsReview` until the user reviews and confirms.
  - **Price decrease**: Applied silently to the cart per `docs/BUSINESS_RULES.md § 5`. The user is charged less without unnecessary friction.
  - **Out of stock**: Shown clearly in the review sheet. The item is removed from the active cart so an impossible order is not attempted.
  - **Quantity reduced**: Shown clearly in the review sheet indicating the available stock limit (`QuantityReduced(requested -> available)`). Cart quantity is clamped to `min(stock, maxPerOrder)`.
  - **Discontinued / no longer sold**: Shown in the review sheet (`ProductUnavailable`). Omitted from the cart.
  - **Coupon removed**: Shown in the review sheet indicating whether the coupon expired or is invalid (`CouponRemoved(code, reason)`).
- **What happens to out-of-stock / discontinued items?**
  - They are excluded from the reconciled cart and presented to the user with a distinct warning in the review sheet.
  - *Reconciliation event precedence*: Availability and stock checks (`serverProduct.stock <= 0`) are evaluated strictly before price drift checks. An item that is zero-stock or unavailable generates exactly one actionable `OutOfStock` or `ProductUnavailable` event and is removed, preventing confusing and contradictory `PriceChanged` events on unpurchasable lines.
  - *Justification*: The backend will unconditionally reject any order containing zero-stock or inactive products (`409 PRODUCT_UNAVAILABLE` or `INSUFFICIENT_STOCK`). Forcing the user to manually remove them or silently failing checkout creates frustration; presenting them as excluded items with an updated subtotal lets the user proceed with what is currently available.
- **Offline-built carts:**
  - Carts built completely offline survive application restarts via `CartStorage` (with QK-101 fixed).
  - When connection is restored and checkout is tapped, reconciliation queries `/v1/products/batch` and `/v1/coupons/validate` to sync prices and stock to current real-world state.
  - If network is completely unreachable at checkout, `NetworkException` surfaces a clear, honest error message ("You appear to be offline. Please check your internet connection.") without corrupting local cart state.
- **Alternatives considered and rejected:**
  - *Automatic order placement with price drops and price increases under ₹10*: Rejected because `BUSINESS_RULES.md § 5` strictly dictates that customers must never pay more than they agreed to without explicit review.
  - *Optimistic checkout without pre-reconciliation*: Rejected because slow networks would cause cryptic 409 failures from the server, resulting in a poor customer experience.

## 2. Safe checkout & idempotency

- **How are duplicate orders prevented?**
  - **Idempotency-Key lifecycle**: We generate a UUIDv4 key for each *logical order attempt*.
  - **Logical Order Identity**: A logical order is tied to the exact cart items and pricing snapshot (`_logicalOrderCart`).
  - **Automatic retry on timeout**: If a checkout request times out (`ApiTimeoutException`), `CheckoutController` performs an immediate retry reusing the exact same `Idempotency-Key` and request payload. If the server already created the order on the first attempt but the response was dropped (e.g. simulated by `chaos.loseNextOrderResponses`), the backend recognizes the key, avoids duplicate creation, and returns the existing order (`200 OK`).
  - **Manual retry order recovery without pre-reconciliation**: If automatic retry is exhausted and the user taps "Place order" to retry manually for the identical logical cart (`_logicalOrderCart == cart`), `CheckoutController` reuses the existing `_idempotencyKey` and payload and bypasses pre-reconciliation directly to `OrderApi.placeOrder()`. This ensures that if the server already created the order and decremented inventory, the backend idempotency table returns the existing order (`200 OK`) rather than a redundant pre-checkout reconciliation seeing 0 inventory and destroying the recovery identity.
  - **Cart mutation resets key**: If the user modifies items, accepts reconciliation changes, or adds a coupon, the payload changes; the controller resets `_idempotencyKey = null` so a fresh key is generated for the new logical order. This avoids `422 IDEMPOTENCY_KEY_REUSED` rejections from the server.
  - **Concurrency lock**: `CheckoutController.placeOrder()` checks `state.isPlacingOrder`. Concurrent calls (e.g. double taps) return the in-progress operation or cached failure rather than dispatching parallel network requests.
- **What does the user see on timeout / lost response?**
  - If automatic retry also times out: "The request timed out. Your order may have been placed. Check My orders or tap to retry."
  - This provides transparency, prevents panic ordering, and directs the user to verified state.
- **Edge cases you handled:**
  - Double tapping checkout button (UI disabled + controller state guard).
  - Server successfully creating order but dropping response (`chaos.loseNextOrderResponses = 1`).
  - Network timeout before server receipt.
  - Server 409 conflict during submission automatically triggering reconciliation and showing updated items.
  - Store closing while the user is actively on the cart screen.
  - Cart clearing occurring *only* after confirmed `CheckoutSuccess`.
  - Cache invalidation of `/v1/orders` upon order creation so the new order appears on "My orders" immediately.
- **Edge cases you know you did NOT handle:**
  - Multi-device simultaneous checkout: If a user logs into two different physical devices with the same account and checks out different carts simultaneously, client-generated UUIDs will not detect cross-device conflicts (this requires a server-side distributed checkout session).
  - Payment gateway webhooks: The application simulates direct order creation without a 3rd-party PG (Razorpay/Stripe) redirect flow.

## 3. Remote config, updates & kill switch (Feature 2)

- **Caching strategy and failure behaviour:**
  - In `ConfigRepository.load()`: Successful fetches write the raw values map to persistent `KeyValueStore` under key `remote_config.v1`.
  - On offline startup or network failure, `load()` reads the cached JSON from `KeyValueStore` and parses it via `AppConfig.fromValues()`.
  - If no cache exists or the stored string is corrupt, it falls back to `AppConfig.defaults()`.
  - `load()` never throws an exception, guaranteeing the application always boots safely even on a cold offline start.
- **How live updates propagate, and how you avoid leaks:**
  - In `AppConfigController.build()`, we subscribe to `ref.watch(configRepositoryProvider).remoteUpdates`.
  - On new version broadcast, `refresh()` is called to fetch the new config and update `state`.
  - Subscriptions are registered with `ref.onDispose(() => sub.cancel())`, guaranteeing that disposing the provider or container completely cancels the listener.
  - `_subscription?.cancel()` is also called on re-build, preventing duplicate listeners.
  - Verified in `test/app_config_test.dart` that bare `ProviderContainer` updates live and drops listeners to 0 upon disposal.
  - *Bare container asynchronous self-hydration*: `AppConfigController.build()` triggers an asynchronous microtask hydration (`Future.microtask`) so that bare `ProviderContainer` test instances self-hydrate server-seeded configuration without depending exclusively on `main.dart` bootstrap. Redundant network calls during `main.dart` bootstrap are prevented via a `_hydrated` guard flag.
- **Force / optional update UX:**
  - Evaluated via `UpdatePolicy.evaluate(currentVersion, minSupportedVersion, latestVersion)` using robust segment-by-segment integer comparison.
  - **Force update (`UpdateRequirement.required`)**: Replaces the app view with `ForceUpdateScreen` using `PopScope(canPop: false)`. The screen is non-dismissible, presents the update reason, and provides a direct button to `config.updateUrl`. It reacts live mid-session if ops raises `min_supported_version`.
  - **Optional update (`UpdateRequirement.optional`)**: Renders a dismissible informational banner at the top of the home screen. Once dismissed by the user, local state (`_dismissedOptionalVersion`) remembers the dismissal and prevents nagging for the same version.
- **Store closed UX:**
  - When `store_open == false`:
    - A prominent warning banner appears on the home screen and cart screen displaying `config.storeClosedMessage`.
    - Customers can freely browse categories, search products, and add items to their cart.
    - Checkout is blocked: `CheckoutController.placeOrder()` returns `CheckoutFailure(storeClosedMessage, canRetry: false)` immediately without sending network requests.
    - When operations re-opens the store via config publish, the app reactively unlocks checkout without requiring a restart.
- **Server-driven home: robustness to bad config:**
  - `HomeLayout.parse()` handles null, empty, non-array JSON, or strings containing unknown sections.
  - Unknown section types are safely skipped (protecting older app builds when backend adds new widgets).
  - Duplicate sections are removed (first occurrence wins).
  - Any fatal parsing failure or zero-known-section result falls back to `HomeLayout.defaultSections` (`[categories, allProducts]`).
  - Colors and banners are guarded with `try-catch` blocks and hex fallbacks. Bad console config never breaks the home screen.

## 4. Feature 3 (if attempted)

- **Status**: Not attempted.
- **Rationale**: Strict compliance with Section 13 of the assignment brief ("Strict Gate: Do not start live order tracking until Part A is complete, Part B is complete, Part C is complete, required documentation is complete, required tests have been executed successfully... A broken optional feature is worse than a correct required submission"). Focused all engineering effort on delivering exceptional correctness, rock-solid tests, and complete documentation for Parts A, B, and C.

## 5. Other decisions

- **Packages added (and why):**
  - No new external packages added. Utilized existing project dependencies (`flutter_riverpod: ^2.6.1`, `shared_preferences: ^2.3.2`, `uuid: ^4.5.1`, `flutter_test`). Keeping dependencies minimal reduces binary size, avoids supply chain vulnerabilities, and aligns with the existing architecture.
- **Refactors you made to the existing code (and why):**
  - *`CategoryScreen` refactored to `ConsumerWidget`*: Eliminated stateful lifecycle listener that caused memory leaks and unmounted `setState` exceptions (BUG-8).
  - *`ApiClient.get` augmented with `forceRefresh` and `invalidateCache`*: Addressed QK-102 without altering the public contract.
  - *`ApiClient` excluded `/v1/orders` from response cache*: Prevented mutable order endpoints from returning stale status when orders advance on the server externally without client POST (Priority 3 / BUG-13).
  - *`formatMoney` negative sign handling*: Ensured negative fractional amounts (e.g. `-50` paise) retain their negative sign (`-₹0.50`) instead of formatting as positive currency (Priority 5 / BUG-15).
  - *`ProductDto.fromJson` null-safety and string type handling*: Allowed safe parsing of legacy catalog items without throwing `TypeError` (BUG-4).
  - *`rupeesToPaise` precision fix*: Switched `.toInt()` to `.round()` to fix IEEE-754 precision loss that was generating false 409 errors (BUG-5).
  - *`CartPricing.compute` boundary fix*: Replaced strict inequality with `>=` to ensure orders at exactly the ₹199 threshold receive free delivery (BUG-3).

## 6. Looking ahead

- **What would you do with one more week?**
  - Implement full offline optimistic cart synchronization queue with conflict resolution.
  - Implement Part D (Live order tracking via FCM foreground push notifications and Firestore snapshot streams).
  - Add end-to-end integration tests using `integration_test` package running on headless emulator.
  - Implement localized currency formatting and accessibility (semantics, screen reader support, dynamic text scaling).
- **What breaks first at 10× users (10k DAU)? What would you change?**
  - **Thundering herd on Remote Config / Catalog**: If thousands of users open the app simultaneously, caching only on the client will hammer the catalog endpoint. Introduce HTTP Cache-Control headers (`stale-while-revalidate`), CDN edge caching (Cloudflare / Fastly), and conditional HTTP requests (`ETag` / `If-None-Match`).
  - **In-memory MockServer / Single Database Lock**: Migrate the mock backend transport to a distributed REST/gRPC backend backed by PostgreSQL with row-level locks on product stock (`SELECT ... FOR UPDATE`) to prevent inventory overselling during flash sales.
- **How would you ship a hotfix for a critical bug without a store release?**
  - Use server-driven remote configuration kill switches (`store_open: false`, `min_supported_version` gate) to block or redirect affected users immediately.
  - Use Shorebird (code push for Flutter) to deliver compiled Dart AOT byte-code patches directly to devices within minutes, bypassing the 2-3 day Google Play / App Store review cycles.
