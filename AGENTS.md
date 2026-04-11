# Crafting Orders++ Agent Guide

This file is the working contract for anyone editing this addon.

If you are making changes, read this first. The addon has a lot of subtle UI and lifecycle behavior, and several bugs were caused by "reasonable" changes that ignored how Blizzard's professions UI actually loads and refreshes.

## Purpose

Crafting Orders++ is a Blizzard-native-style rewrite of the Patron crafting orders browse list for World of Warcraft Retail, updated for Midnight-era professions.

The addon's job is to make Patron orders faster to evaluate without replacing the rest of Blizzard's crafting flow:

- show a useful Patron list with `Cost`, `Reward`, `Profit`, and `Time`
- value rewards and supplied materials using optional pricing addons
- simulate target quality in a practical way
- help the player buy only the missing materials they actually want to buy
- leave the detail/draft order view as native Blizzard UI

## Non-Negotiable Product Rules

- Keep the detail pane Blizzard-native.
  Do not reintroduce mirrored action buttons, custom cast bars, concentration mirrors, or hidden native buttons. `OrderView.lua` was intentionally removed.
- The custom UI exists only for the Patron browse/list pane.
- Match Blizzard visual language.
  Prefer Blizzard templates, atlas icons, font objects, and colors over custom styling.
- Do not copy code from reference addons.
  Similar behavior is fine. Clean rewrite only.
- The addon should remain useful even with no pricing addon installed.
- Optional pricing support must be additive, not a hard dependency.

## Current File Map

- [Core.lua](G:\World of Warcraft\_retail_\Interface\AddOns\CraftingOrders++\Core.lua)
  Addon bootstrap, saved variables, config helpers, utility helpers, safe addon metadata wrappers, locale-aware chat prefix.
- [Locale.lua](G:\World of Warcraft\_retail_\Interface\AddOns\CraftingOrders++\Locale.lua)
  Localization registry and formatting helpers.
- [Locales\enUS.lua](G:\World of Warcraft\_retail_\Interface\AddOns\CraftingOrders++\Locales\enUS.lua)
  Source of truth for all user-facing strings.
- [Locales\*.lua](G:\World of Warcraft\_retail_\Interface\AddOns\CraftingOrders++\Locales)
  Locale-specific override files. Most are currently stubs and fall back to `enUS`.
- [Pricing.lua](G:\World of Warcraft\_retail_\Interface\AddOns\CraftingOrders++\Pricing.lua)
  Pricing provider detection, price lookup, Auctionator shopping-list export, Auctioneer Snatch export.
- [Options.lua](G:\World of Warcraft\_retail_\Interface\AddOns\CraftingOrders++\Options.lua)
  Blizzard Settings panel.
- [BrowsePane.lua](G:\World of Warcraft\_retail_\Interface\AddOns\CraftingOrders++\BrowsePane.lua)
  The custom Patron pane, row rendering, tooltips, material planning, quality simulation, request lifecycle, detail warnings, opening behavior.
- [CraftingOrders++_Mainline.toc](G:\World of Warcraft\_retail_\Interface\AddOns\CraftingOrders++\CraftingOrders++_Mainline.toc)
  Load order. Locale files must stay before runtime files.

## UI and Visual Style Rules

### General feel

- The addon should feel like Blizzard shipped it.
- Favor practical clarity over decoration.
- Avoid flashy custom art or invented UI patterns.
- Use Blizzard atlas icons where possible:
  - clock header icon
  - quality checkmarks
  - favorite star badges
  - warning icons
  - money icons

### Patron list layout

- The pane is anchored like the reference behavior, not stretched to fill the whole `BrowseFrame`.
- Do not use `SetAllPoints()` for the custom pane root.
- Current layout uses a fixed-size root anchored bottom-right to Blizzard's browse frame.
- Be careful around the top edge:
  - too low creates an ugly gap under the tabs
  - too high overlaps Blizzard's tab UI
- The existing alignment is deliberate. Adjust only with screenshot-driven validation.

### Row design conventions

- Unknown recipes are greyed out. Do not show a subtitle like "unknown recipe".
- Patron names are intentionally removed from the list.
- The final column is time only.
- The clock icon belongs in the header, not every row.
- Time text is short and rounded:
  - `2d`
  - `4h`
  - `15m`
- Time colors should match Blizzard-style urgency thresholds.
- Item status icons belong on the item-name line.
- Do not show the text `First craft`.
- Do not show a quality badge when the requested quality is only the craft's true minimum.
  This includes recipes whose minimum is not bronze.
- Quality reachability is shown with Blizzard-native checkmark icons:
  - green = reachable with lowest-quality ingredients and no concentration
  - amber = reachable, but needs stronger materials and/or concentration
- No extra "achieved quality" icon should be shown in the row.

### Money display conventions

- In list cells, money is gold-only by default and uses the Blizzard gold icon.
- Silver/copper in list cells is controlled by a setting.
- Tooltips always show full money formatting.
- Negative profit uses Blizzard red.
- `None` in sortable money columns must sort as numeric `0`.
- Cost column conventions:
  - fully patron-supplied => `None` + `All provided`
  - no auctionable market value at all => `None` + `Not marketable`
  - missing data => `None` + `No market data`

### Reward conventions

- No `Knowledge: X` subtitle under reward icons.
- If a reward grants more than 1 knowledge point, add a small star badge to the reward icon.
- Reward valuation can include reward items if marketable and priced.
- Bound or non-marketable rewards must not be treated as "no market data".

### Buttons and toolbar

- The shopping-list action is intentionally a compact `+` button.
- Do not add large toolbar buttons that consume vertical space.
- Tooltip text explains what the `+` button does depending on provider state and selection state.

### Detail-view warnings

- The detail pane remains Blizzard-native, but small additive warnings are allowed.
- Expensive-ingredient warnings exist in two places:
  - a summary warning aligned on the same row as `Use Best Quality Reagents`
  - a small warning badge over affected reagent slots
- The slot warning should overlap the reagent like a badge, not float above it.
- The warning tooltip should focus on:
  - selected cost
  - cheaper alternative
  - savings
- Do not clutter the tooltip with redundant threshold restatement on the per-item badge.

## Localization Rules

This addon now has a real localization system. Do not regress it.

### Required workflow for new strings

- Every user-facing string must go through localization.
- Add the source string to [Locales\enUS.lua](G:\World of Warcraft\_retail_\Interface\AddOns\CraftingOrders++\Locales\enUS.lua).
- Use:
  - `L.KEY` for direct string lookup
  - `ns.LF("KEY", ...)` or local `LF(...)` helper for formatted strings
- Never hardcode new English strings inside:
  - tooltips
  - button text
  - options labels
  - empty states
  - chat output
  - status hints

### Formatting guidance

- If a sentence contains interpolation, put the whole sentence in the locale file.
- Do not build English grammar by concatenating pieces in code.
- Prefer locale keys like:
  - `"%d items"`
  - `"Reward total"`
  - `"%s: %s%s"`
  instead of hardcoded inline formatting.

### Safety behavior

- `ns.LF` already has a safe fallback:
  - it tries the active locale
  - if formatting fails, it falls back to `enUS`
- Keep using `ns.LF` instead of raw `:format()` on localized strings.

### Locale file expectations

- `enUS.lua` is the required source of truth.
- Other locale files may stay sparse and fall back to English until translated.
- When adding a new key, it must exist in `enUS.lua`.
- Locale files must stay loaded before runtime files in the TOC.

## Load Order and Lifecycle Rules

The addon is `LoadOnDemand` and loaded with `Blizzard_Professions`. Timing matters.

### Initialization

- `Core.lua` initializes the database on `ADDON_LOADED`.
- Module initialization may happen before the professions UI is fully ready.
- `ns.InitializeModules()` already retries if Blizzard professions UI is not ready.
- `BrowsePane:Initialize()` and hook setup are also retry-driven.
- Do not assume frames/methods exist the first time code runs.
- Always nil-check Blizzard methods before hooking or calling them.

### Patron tab activation

- Do not assume `SetCraftingOrderType()` will always fire.
- The professions window can open with the Patron tab already selected.
- `BrowsePane:SyncCurrentOrderType("initial-state")` exists for exactly this reason.
- Any new tab-specific behavior must work both when:
  - the user clicks into Patron
  - the UI opens directly on Patron

### Request lifecycle

Patron order fetching is one of the most failure-prone parts of the addon.

- The pane uses a stale-while-revalidate model.
- If same-profession cached orders exist, keep them visible while a refresh is in flight.
- Do not replace valid visible cache with an empty list mid-request.
- `UpdateEmptyState()` must distinguish:
  - loading
  - truly empty
- Long patron lists can respond slowly.
- `REQUEST_TIMEOUT` is intentionally more forgiving now.
- `request-timeout` must remain a request-triggering reason.
  If it stops counting as a request reason, the pane can falsely show `No orders`.
- Late successful callbacks for the current profession must still be allowed to refresh the list.
  Do not discard them just because the original request timed out.
- Clear request state when:
  - profession changes
  - pane hides
  - active request no longer matches current context

### Event coalescing

- Blizzard sends many noisy events while item/reward data streams in.
- `QueueDeferredDirty()` exists to batch them.
- Prefer batched refreshes over immediate full rebuilds for:
  - item data loads
  - reward updates
  - order-count churn

## Material Planning Rules

This addon has one core planning principle:

- use one canonical material plan

Do not split the truth across multiple competing structures again.

### Current rule

- `materialPlan.entries` is the source of truth for:
  - row reagent icons
  - material cost
  - profit
  - shopping-list export
  - reagent tooltips

### Planning behavior

- The default plan is the cheapest valid mix, not the highest quality mix.
- Costing, shopping export, and quality simulation must stay aligned.
- Mixed reagent qualities within a slot are allowed and sometimes necessary.
- Required non-quality reagents must be included in the same plan.
  They were previously lost by only tracking mutable slots.

### Inventory accounting

- Reagent ownership is quality-aware.
- If the player owns the reagent only in other qualities, show amber counts and explain it in the tooltip.
- Shopping-list export subtracts owned count for the selected quality only.
- Do not subtract the total reagent family count when export is quality-specific.

## Patron Order Opening Behavior

When opening a Patron order from the custom list:

- default behavior can be "do nothing"
- optional behavior can:
  - turn off `Use Best Quality`
  - mark the transaction manually allocated
  - apply the planned reagent mix
  - preserve mixed allocations
  - apply planned concentration usage

Important:

- This logic only applies when opening from this addon's Patron list.
- Blizzard's native `Use Best Quality` can override the plan if left on.
- If you touch this area, keep the setting-driven behavior intact.

## Pricing and Market Rules

### Supported providers

- Auctionator
- Auctioneer

Only one pricing provider is selected at a time.

### Options behavior

- Only detected supported addons should be shown in the options radio list.
- If no supported addons are detected, show an informational block instead of dead controls.

### Marketability

- Bound or otherwise non-marketable items are `not marketable`.
- That is different from `no market data`.
- Do not lump those states together.
- Reward totals, material costs, and profit should ignore items that can never be traded.

### Export behavior

- Auctionator export creates a shopping list.
- Auctioneer export adds entries to Snatch.
- Export feedback in chat should include:
  - quantity added
  - expected cost
  - whether pricing is partial or unknown

## Saved Variables and Settings

Current meaningful settings include:

- `pricingSource`
- `dontBuyItems`
- `dontBuyItemsByCharacter`
- `dontBuyPerCharacter`
- `openPatronOrderBehavior`
- `warnExpensiveIngredients`
- `expensiveIngredientThresholdPercent`
- `greyUnknownRecipes`
- `showSilverCopperInList`

Rules:

- If you add a setting:
  - add a default in `Core.lua`
  - expose it in `Options.lua` if user-facing
  - make sure the browse pane refreshes if needed
- If you replace or simplify an old setting:
  - provide migration logic in `MigrateDatabase()` where appropriate

### Don't Buy behavior

- The `Don't Buy` list persists through logout.
- Default scope is shared across characters.
- There is a setting to switch to per-character storage.
- The only functional effect of `Don't Buy` is shopping export.
  It must not affect cost, reward, profit, or quality simulation.

## Detail Pane Rules

Repeat this to yourself before editing anything around the order form:

- do not customize the detail view unless absolutely necessary
- do not add custom action buttons
- do not hide Blizzard buttons
- do not add custom cast bars
- do not mirror concentration UI

The current accepted detail-view additions are warning adornments only.

## Midnight and Profession-Specific Notes

- The addon is intended to be Midnight-compatible.
- Reward knowledge item handling includes explicit reward item IDs.
- If expansion changes introduce new patron reward items or profession-quality behavior, update the relevant lookup tables and quality logic.
- When determining whether a requested quality is meaningful, use the recipe's true minimum quality, not an assumed bronze minimum.

## Code Style Rules for This Addon

- Use Blizzard-safe defensive coding:
  - `type(method) == "function"` checks
  - `pcall` or `securecall` around unstable APIs
  - nil-safe frame access
- Do not create static data lookup tables unless the user explicitly asks for them.
  This includes bundled spell-to-item maps, handcrafted recipe source databases, and copied data extracts from other addons or datamined sources.
- Why this rule exists:
  WoW profession data changes over time, especially across expansions, patches, seasons, hotfixes, and client API updates.
  Static lookup tables go stale silently, are easy to forget to update, increase addon size and maintenance burden, and can create misleading UI that looks authoritative but is wrong.
  Prefer live Blizzard APIs first, then clearly-declared optional dependencies when live data is incomplete.
  If a static table is ever explicitly requested, document the source, scope, and update risk in the README and settings where relevant.
- Avoid storing heavyweight raw Blizzard data on cached orders if it is not needed after preparation.
- Prefer clear helper functions over deeply nested inline logic.
- Keep row rendering and tooltip behavior data-driven where possible.
- Use existing helpers before adding new parallel ones.
- If a helper already exists for formatting or state checks, extend it instead of duplicating logic elsewhere.

## Regression Hotspots

These areas have broken before:

- opening the professions window directly on Patron
- long Patron lists timing out and showing `No orders`
- stale cache being cleared too early
- wrong anchor causing overlap with Blizzard tabs or sidebar
- known recipes showing unknown-recipe tooltip text
- quality minimum suppression for recipes whose minimum is not bronze
- shopping list using wrong reagent quality
- counts subtracting the wrong owned quality
- `Don't Buy` overlay Z-order being hidden by counts
- detail pane concentration/action UI being broken by custom code
- bound rewards showing as missing market data instead of not marketable

If you touch one of these areas, be extra conservative.

## Testing Checklist

Before considering a change "safe", try to cover as many of these as possible in-game:

- fresh install with no saved variables
- client opened directly on Patron tab
- switch away from Patron and back
- long Patron list with slow loading
- no pricing addon installed
- Auctionator only
- Auctioneer only
- unknown recipe rows and tooltip metadata
- cost/profit sort when values show `None`
- `All provided` orders
- non-marketable reward or reagent cases
- multi-select shopping export
- `Don't Buy` toggle and persistence
- per-character `Don't Buy` mode
- expensive ingredient warning summary and slot badges
- opening behavior with `Use Best Quality` left on vs apply-plan mode
- non-English locale fallback behavior

## If You Add Features

Ask these before merging the design:

- Does this belong in the Patron list, or am I accidentally customizing the detail view?
- Is the text localized?
- Does it respect Blizzard's visual language?
- Does it work without a pricing addon?
- Does it preserve same-profession cache behavior?
- Could it break when Patron is selected on initial load?
- Does it keep cost, export, and quality planning aligned?

If the answer to any of those is "maybe not", rethink the implementation before shipping it.
