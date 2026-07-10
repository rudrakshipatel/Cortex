# Pro plans, discount & lifetime — store setup

The app code is done. Prices, trials, and the lifetime product all live in
**App Store Connect + RevenueCat** — the app just displays whatever the store
returns. These are the out-of-app steps.

**Current decision:** launch all three plans **without free trials** (trials
deferred). The lifetime plan ships now as a limited-time offer.

## 1. App Store Connect — products

Create/adjust these under your app ▸ Subscriptions / In-App Purchases:

| Product | Type | Price now | Free trial (introductory offer) |
|---|---|---|---|
| Monthly Pro | Auto-renewable subscription | **$7.99 / month** | **None for now** (add later) |
| Annual Pro | Auto-renewable subscription | **$49.99 / year** | **None for now** (add later) |
| Lifetime Pro | **Non-consumable** (one-time) | **$69.99** | — (never has a trial) |

- Put the two subscriptions in the **same subscription group** (so a user has one at a time).
- **Free trials are deferred** — do **not** create Introductory Offers yet. When you add them later (type "Free", e.g. 3 days monthly / 1 week annual), the app auto-shows the trial label and switches the button to **Start Free Trial** with no app update.
- The lifetime is a **non-consumable**, not a subscription — that's what makes it "yours forever."

## 2. RevenueCat

1. **Entitlement:** attach all three products to the existing **`pro`** entitlement. (A non-consumable on `pro` grants Pro with no expiry — the app already detects this and shows "Lifetime Pro".)
2. **Offering:** add all three to your current offering as the **Monthly**, **Annual**, and **Lifetime** packages.
3. **Discount / cut prices — offering metadata:** on the current offering, add these metadata keys (this is where the struck-through "original" prices come from):
   - `original_price_monthly` → `$12.99`
   - `original_price_annual` → `$69.99`
   The app renders these struck through above the live $7.99 / $49.99. Leave lifetime without a key (no strikethrough, just a "LIMITED TIME" badge).

   > Note: metadata prices are plain strings you type, so they show the same figures in every region. If you sell in multiple currencies and want per-region "was" prices, that's a limitation of this approach.

## 3. When the promo ends

No app update needed for any of this:

- **Raise prices to $12.99 / $69.99:** change them in App Store Connect (follow Apple's price-increase consent flow for existing subscribers). Then update or clear the `original_price_*` metadata in RevenueCat so the strikethrough reflects the new reality (or remove the keys to drop the strikethrough entirely).
- **Retire the lifetime plan:** remove the Lifetime package from the RevenueCat offering (and mark the product unavailable in App Store Connect). It disappears from the app automatically. **Everyone who already bought it keeps Pro forever** — non-consumables never expire, and the app grants Pro from the `pro` entitlement regardless.

## What the app already does

- Shows the three plans with the annual pre-selected ("BEST VALUE"), lifetime badged "LIMITED TIME".
- Struck-through original price from metadata; live price from StoreKit.
- Button reads **"Subscribe"** for the subscriptions (no trials right now) and **"Buy Lifetime"** for lifetime. If you add a trial later, that plan's button becomes "Start Free Trial" automatically.
- A lifetime owner sees "Lifetime Pro — yours forever" with no manage/cancel button (nothing to cancel).
