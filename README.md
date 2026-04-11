# Crafting Orders++

## TL;DR

Crafting Orders++ upgrades WoW's Patron crafting-orders tab with a cleaner list, reagent cost and reward value tracking, profit estimates, quality planning, shopping-list export, and better handling for unknown recipes. It is built for players who want to decide faster which patron orders are worth crafting and which materials they actually need to buy or save.

## CurseForge Overview

Crafting Orders++ is a focused rewrite of WoW's Patron crafting-orders list for players who want to make faster, smarter decisions at the crafting table.

Instead of treating patron orders like a plain queue, it helps you answer the questions that actually matter:

- Which orders are worth doing?
- Which reagents will I need to supply?
- What will those reagents cost?
- What is the reward really worth?
- Will this order make gold or lose gold?
- Can I hit the requested quality with cheap materials, or will it need better reagents or concentration?

The addon is built to feel native to Blizzard's UI while making the Patron tab far more useful for everyday play, especially in Midnight-era professions where reagent quality and reward value matter a lot.

### What It Adds

- A cleaner Patron orders list with columns for `Cost`, `Reward`, `Profit`, and `Time`
- Helpful tooltip info for unlearned recipes, including Blizzard source text when available
- Quality indicators that show when a target quality is actually meaningful, and whether you can reach it with cheap materials or need a stronger setup
- Reward value support that includes both gold and market-priced reward items
- Profit calculation based on your supplied materials versus the total reward value
- Multi-select patron orders and export missing reagents to a shopping list
- Optional Auctionator or Auctioneer support for reagent pricing and reward valuation
- A persistent `Don't Buy` reagent toggle so you can exclude items from shopping-list exports

### Why It Is Useful

Patron orders often look attractive until you account for reagent quality, supplied materials, and the real market value of the reward. Crafting Orders++ puts that information directly in the list so you do not need to click into every order, check multiple tooltips, or guess whether a craft is worth your time.

It is especially helpful if you:

- farm patron orders for knowledge or acuity
- want to avoid wasting high-quality reagents on low-value orders
- use Auctionator or Auctioneer and want shopping-list export built into your workflow
- regularly compare multiple patron orders before choosing what to craft
- want a cleaner way to handle unlearned recipes and material planning

### Key Settings

These are the settings most players will care about:

- `Pricing Addon`
  Choose which detected addon should be used for pricing information. Only supported addons that are actually installed are shown.

- `Grey out unknown patron recipes`
  Keeps unlearned recipes visible, but dims them clearly so they do not blend in with craftable orders.

- `Show silver and copper in list money columns`
  By default the list stays compact and shows gold only. Enable this if you want full gold, silver, and copper values in the table.

- `Patron Order Opening`
  Choose whether the addon should leave Blizzard's native reagent allocation alone or automatically turn off `Use Best Quality` and apply the planned material mix when opening a patron order from this list.

- `Keep Don't Buy ingredient list per character`
  By default your `Don't Buy` exclusions are shared across characters. Turn this on if you want each character to manage their own list.

### Optional Pricing Support

Crafting Orders++ works without pricing addons, but pricing-aware features are much more useful when one is installed.

- `Auctionator`
  Supports reagent cost, reward valuation, profit display, and shopping-list creation.

- `Auctioneer`
  Supports reagent cost, reward valuation, profit display, and shopping export to Snatch when available.

If no supported pricing addon is detected, the addon still improves the Patron list and recipe visibility, but price-based columns and shopping export will be limited.

### In Practice

Open the crafting table, switch to the Patron tab, and you can quickly spot:

- orders that are fully supplied by the patron
- orders that require your own materials
- orders that are profitable
- orders that are only worth doing for knowledge or acuity
- orders that need better reagents or concentration to meet quality
- orders you cannot currently craft because the recipe is unknown

The result is a Patron list that is much better for planning, triage, and making gold-aware decisions without leaving the Blizzard professions UI.
