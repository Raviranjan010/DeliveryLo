# Bugs found & fixed

> One section per bug. Order doesn't matter. Keep each one short and precise.
> Commit the reproducing test **before** the fix.

---

## BUG-1: Cart mutations not persisted on decrement and removal (QK-101)

- **Symptom:** Items removed by the user return after reopening the application, and decremented quantities revert to their higher previous values. The cart badge displays an incorrect count after restart.
- **Steps to reproduce:**
  1. Add 2 units of an item (e.g. Robusta Banana) and 1 unit of another item (e.g. Shimla Apple) to the cart.
  2. In the cart screen, decrement Banana to 1 and remove Apple.
  3. Close/kill the application and reopen it.
  4. Notice Apple has returned and Banana has reverted to 2.
- **Root cause:** In `lib/features/cart/application/cart_controller.dart`, `decrement()`, `remove()`, and `removeCoupon()` updated in-memory `state` via `updateQuantity()`, `removeLine()`, and `withoutCoupon()`, but omitted `await _storage.save(updated)`. Only `add()`, `increment()`, and `applyCoupon()` persisted to storage. On app restart, `main.dart` hydrated the cart from `CartStorage.load()`, which loaded the stale un-persisted snapshot.
- **Fix:** Added `await _storage.save(updated)` immediately following state updates in `decrement()`, `remove()`, and `removeCoupon()`.
- **Test:** `test/cart_persistence_test.dart` → `reproduce QK-101: decrement, remove, and removeCoupon persist across restart`
- **Commits:** test `da42288` → fix `e29034b`

---

## BUG-2: Stale GET cache blocks price refreshes and hides newly placed orders (QK-102)

- **Symptom:** Pull-to-refresh on catalog views continues showing outdated prices even when updated on the backend. Newly placed orders do not appear on the "My orders" screen until the app process is restarted.
- **Steps to reproduce:**
  1. Open the catalog or "My orders" screen.
  2. Update a product price via Dev Tools (or place a new order).
  3. Perform pull-to-refresh on the catalog or navigate back to "My orders".
  4. The price remains unchanged and the orders list remains empty until restarting the app.
- **Root cause:** In `lib/core/network/api_client.dart`, `ApiClient` unconditionally cached all `GET` responses in `_responseCache` for `responseCacheTtl = const Duration(minutes: 10)`. Pull-to-refresh invoked `_client.get()` with identical URLs, hitting the 10-minute cache without reaching the transport. Similarly, `/v1/orders` GET requests were cached for 10 minutes and never invalidated upon `POST /v1/orders` completion, and `CheckoutController` failed to invalidate `ordersProvider`.
- **Fix:** Enhanced `ApiClient.get` with a `forceRefresh` parameter that skips and updates the cache. Added `ApiClient.invalidateCache()` and automatically cleared the `/v1/orders` cache upon successful `POST /v1/orders`. Updated `CatalogRepository.getPage` and `CatalogController.refresh()` to pass `forceRefresh: true` on user refresh, and updated `CheckoutController` to invalidate `ordersProvider` upon order completion.
- **Test:** `test/stale_cache_test.dart` → `reproduce QK-102 (part 1): catalog refresh must reflect updated prices from server` and `reproduce QK-102 (part 2): newly placed order must appear in orders list without restart`
- **Commits:** test `35d615f` → fix `85cc1c3`

---

## BUG-3: Delivery fee erroneously charged at exact free delivery threshold (BUG-3)

- **Symptom:** A customer ordering goods totaling exactly ₹199 (19,900 paise) is charged a ₹25 delivery fee and the order is subsequently rejected by the backend with a `409 TOTAL_MISMATCH` error.
- **Steps to reproduce:**
  1. Build a cart whose payable amount after discounts is exactly ₹199 (e.g. 1 unit of a ₹199 item).
  2. View the bill details in the cart screen. Notice delivery fee is shown as ₹25 instead of FREE.
  3. Attempt checkout. The server computes free delivery (delivery fee 0) and rejects the request because `expectedTotalPaise` does not match the server total.
- **Root cause:** In `lib/features/cart/domain/cart_pricing.dart` (line 43), the threshold check was implemented with strict inequality: `final deliveryFee = payable > threshold ? 0 : config.deliveryFeePaise;`. According to `docs/BUSINESS_RULES.md § 2`, orders of ₹199 or more qualify for free delivery (`payable >= threshold`).
- **Fix:** Changed the condition to `payable >= threshold ? 0 : config.deliveryFeePaise;`.
- **Test:** `test/pricing_boundary_test.dart` → `reproduce BUG-3: cart of exactly ₹199 (19900 paise) gets free delivery`
- **Commits:** test `2374ad4` → fix `bb311c4`

---

## BUG-4: Legacy catalog product deserialization TypeError crash (BUG-4)

- **Symptom:** Browsing the "Dairy, Bread & Eggs" category or "All products" crashes with an unhandled `TypeError` ("Null is not a subtype of type num" or "type String is not a subtype of type int").
- **Steps to reproduce:**
  1. Launch the application.
  2. Tap on the "Dairy, Bread & Eggs" category on the home screen.
  3. The catalog screen shows a failure error rather than displaying products.
- **Root cause:** In `lib/features/catalog/data/product_dto.dart`, `ProductDto.fromJson` strictly cast `json['mrp'] as num` and `json['stock'] as int`. The seed catalog contains legacy products (`dairy-00`, `dairy-02`, `snacks-09`) where the backend legacy format omits `mrp` (`null`) when equal to price and returns `stock` as a `String` (e.g. `'120'`).
- **Fix:** Handled nullable `mrp` by defaulting `mrpPaise` to `pricePaise` when `mrp == null`, and parsed `stock` whether delivered as `int` or `String` (`rawStock is int ? rawStock : int.parse(rawStock as String)`).
- **Test:** `test/product_dto_legacy_test.dart` → `reproduce BUG-4: ProductDto.fromJson crashes on legacy product with null mrp and string stock`
- **Commits:** test `70e5440` → fix `b78bef9`

---

## BUG-5: Floating-point truncation in `rupeesToPaise` causing off-by-one paisa errors (BUG-5)

- **Symptom:** Products priced with decimal paise (e.g. Hybrid Tomato at ₹19.99, Green Grapes at ₹79.99) are rejected during checkout with `409 PRICE_CHANGED` even when catalog prices have not drifted.
- **Steps to reproduce:**
  1. Add Hybrid Tomato (₹19.99) to the cart.
  2. Attempt to place an order.
  3. The server rejects the order with `409 PRICE_CHANGED: expected 1998, current 1999`.
- **Root cause:** In `lib/core/utils/money.dart`, `rupeesToPaise(num rupees) => (rupees * 100).toInt();`. Under IEEE-754 double precision representation, `19.99 * 100` evaluates to `1998.9999999999997`. Calling `.toInt()` truncates towards zero, producing `1998` instead of `1999`.
- **Fix:** Changed `(rupees * 100).toInt()` to `(rupees * 100).round()`.
- **Test:** `test/money_precision_test.dart` → `reproduce BUG-5: 49.99 rupees converts to 4999 paise without off-by-one truncation`
- **Commits:** test `aaf4e74` → fix `b2dd756`

---

## BUG-6: `formatMoney` truncating non-zero paise from price labels (BUG-6)

- **Symptom:** Decimal prices are truncated to round rupees. A ₹19.99 tomato is displayed as `₹19`, and ₹79.99 grapes are displayed as `₹79`, misleading customers.
- **Steps to reproduce:**
  1. Inspect Hybrid Tomato (price 1999 paise) in the catalog or cart.
  2. Notice the UI displays `₹19` instead of `₹19.99`.
- **Root cause:** In `lib/core/utils/money.dart`, `formatMoney` performed integer division: `final rupees = paise ~/ 100; return '₹$rupees';`, completely discarding the remainder paise. This violates `docs/BUSINESS_RULES.md § 1` ("Prices are shown in rupees, with paise only when there are any: ₹50, ₹49.99").
- **Fix:** Formatted paise with zero-padded two decimals when `paise % 100 != 0` (`₹$rupees.${remainder.toString().padLeft(2, '0')}`), while retaining round rupee format when paise is 0 (`₹$rupees`).
- **Test:** `test/format_money_test.dart` → `reproduce BUG-6: formatMoney shows paise only when non-zero per business rules`
- **Commits:** test `38102a1` → fix `a0d8290`

---

## BUG-7: Catalog cache key collision between different categories in offline fallback (BUG-7)

- **Symptom:** Browsing categories while offline displays products belonging to a completely different category.
- **Steps to reproduce:**
  1. While online, browse "Dairy, Bread & Eggs" (caches the first page).
  2. While online, browse "Cold Drinks & Juices".
  3. Turn on airplane mode / offline mode in Dev Tools.
  4. Navigate to "Dairy, Bread & Eggs". Products shown are cold drinks rather than dairy products.
- **Root cause:** In `lib/features/catalog/data/catalog_repository.dart` (line 46), the cache key was constructed without `categoryId`: `final cacheKey = 'page.${cursor ?? 'first'}';`. Every category first-page fetch overwrote `'page.first'`, creating cache cross-talk.
- **Fix:** Scoped the cache key to the category: `final cacheKey = 'category.$categoryId.page.${cursor ?? 'first'}';`.
- **Test:** `test/catalog_cache_collision_test.dart` → `reproduce BUG-7: offline cached page does not collide between categories`
- **Commits:** test `7b7c538` → fix `3b06c30`

---

## BUG-8: Unmanaged stream subscription leak and unmounted setState in CategoryScreen (BUG-8)

- **Symptom:** Memory leak and `setState() called after dispose()` exceptions when navigating between category screens while remote config updates are broadcast.
- **Steps to reproduce:**
  1. Open a category screen and press back.
  2. Repeat navigation multiple times.
  3. Inspect `MockServer.configListenerCount` via Dev Tools or publish remote config.
  4. Each visit permanently leaks an active stream subscription.
- **Root cause:** In `lib/features/catalog/presentation/category_screen.dart`, `_CategoryScreenState.initState` directly listened to `ref.read(configRepositoryProvider).remoteUpdates` without storing or cancelling the `StreamSubscription` in `dispose()`.
- **Fix:** Refactored `CategoryScreen` to a declarative `ConsumerWidget` that observes `ref.watch(appConfigControllerProvider).freeDeliveryThresholdPaise`, eliminating manual stream lifecycle management and ensuring automatic cleanup through Riverpod.
- **Test:** `test/category_screen_leak_test.dart` → `reproduce BUG-8: CategoryScreen does not leak config listener after dispose`
- **Commits:** test `ccc5198` → fix `fa33b5e`

---

## BUG-9: Single-character search crash and asynchronous query race condition (BUG-9)

- **Symptom:** Typing the first character in the search box immediately surfaces an error banner ("Search query must have at least 2 characters"). Rapid typing occasionally results in earlier search results replacing the newer results.
- **Steps to reproduce:**
  1. Tap the search bar and type "m". An error banner appears immediately.
  2. Type "milk" quickly. The results for "mi" or "mil" occasionally flash and overwrite the final results.
- **Root cause:** In `lib/features/search/search_controller.dart`, `search()` called the API for queries with fewer than 2 characters, violating the backend constraint (`400 QUERY_TOO_SHORT`). Additionally, concurrent asynchronous search futures did not track request sequencing, allowing out-of-order completions to overwrite newer results.
- **Fix:** Short-circuited search execution when `trimmed.length < 2` (clearing results without an error banner), and added request sequence tracking (`_searchSequence`) so that completions from earlier queries are discarded.
- **Test:** `test/search_controller_test.dart` → `reproduce BUG-9: 1-character query does not call API and trigger 400 error` and `reproduce BUG-9: out-of-order query responses do not overwrite newer results`
- **Commits:** test `c02456a` → fix `e021b1c`

---

## BUG-10: Double-tap duplicate order placement on checkout button (BUG-10)

- **Symptom:** Double-tapping "Place order" sends concurrent checkout requests to the backend, resulting in duplicate order creation.
- **Steps to reproduce:**
  1. Add items to the cart and navigate to the cart screen.
  2. Rapidly tap the "Place order" button twice.
  3. Check "My orders" or server order count. Two identical orders are created.
- **Root cause:** In `lib/features/cart/presentation/cart_screen.dart`, `onPressed` on `_PlaceOrderBar` did not disable the button during submission (`onPressed: () => _placeOrder(...)` instead of `placing ? null : ...`). In addition, `CheckoutController.placeOrder()` did not check `state.isPlacingOrder` before initiating submission.
- **Fix:** Disabled the button when `isPlacingOrder` is true, and added a guard in `CheckoutController.placeOrder()` that rejects concurrent order placement while an order is in progress.
- **Test:** `test/concurrent_checkout_test.dart` → `reproduce BUG-10: concurrent placeOrder invocations do not create duplicate orders`
- **Commits:** test `d8011b8` → fix `22418c7`

---

## Suspicious but NOT a bug

- **`MockServer._maybeDriftPrice()` random price drift during catalog listing:**
  Investigated whether background price changes on `GET /v1/products` were a bug in the mock server. Concluded this is intended chaos behavior to simulate production price drift and validate cart reconciliation before checkout.
- **`Coupon.minOrderPaise` not validated in `POST /v1/coupons/validate`:**
  Investigated whether the validation endpoint should reject coupons when the current cart is below the minimum threshold. Per `docs/API_CONTRACT.md` and `docs/BUSINESS_RULES.md § 3`, minimum order value is evaluated at checkout, not at coupon application; coupons below threshold remain applied but grant ₹0 discount until more items are added.
- **Catalog prices sent as decimal rupees while cart requests use paise:**
  Investigated the dual-currency units. Per `docs/API_CONTRACT.md`, the catalog endpoint legacy format outputs rupees as decimals, while orders and checkout strictly require integer paise. This is an intentional backend contract and must be mapped cleanly via `ProductDto` and `rupeesToPaise`.
