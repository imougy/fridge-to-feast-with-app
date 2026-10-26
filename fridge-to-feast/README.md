# Fridge-to-Feast — scaffold

Hackathon scaffold for the Meta Global AI Developer Hackathon (indie track).
Concept, schedule, and demo script live in `../../PROJECT_BRIEF.md`.

## Layout

- `Package.swift` + `Sources/FridgeToFeastCore/` — the pipeline as a
  Foundation-only Swift package: models, prompts, keyframe selection for
  sweep videos, the `MetaModelClient` protocol, a live-client skeleton,
  a full mock client, the backward scheduler, and the pipeline
  orchestrator. This is where the hackathon work happens.
- `Tests/FridgeToFeastCoreTests/` — smoke tests over the mock pipeline
  (full flow, buy-cap behavior, prompt contents) and the keyframe
  selector (blur floor, time dedupe, even thinning).
- `App/` — the SwiftUI app shell. These files are NOT in the package;
  copy them into an Xcode iOS app target that depends on the package.
  Includes `VideoFrameExtractor.swift` (AVFoundation frame sampling +
  sharpness scoring) — capture is a sweep video first, still photos second.
- `Mocks/sample_recipes.json` — the mock client's recipes as raw JSON,
  matching the strict schema Muse Spark must return in live mode.

## Run it today (mock mode)

1. Create an iOS App project in Xcode (SwiftUI, iOS 16+).
2. Add this folder's package as a local package dependency.
3. Copy the four files from `App/` into the app target, replacing the
   generated `*_App.swift` and `ContentView.swift`.
4. Build and run. The app defaults to `MockMetaModelClient`
   (`useLiveAPI = false` in `FridgeViewModel.swift`), so both flows —
   solo (sweep or photos → labeled overlay → confirm → both recipe
   groups → cook mode) and party (guests + budget + serve time → menu →
   backward-scheduled timeline) — work with no network and no credentials.

Mock mode is a feature, not a shortcut: it is the demo safety net for the
live finals. Keep it working at all times.

## Going live at kickoff (Oct 26)

1. Get the Meta Model API base URL, model IDs, and auth scheme from the
   hackathon docs; participants get $150 in API credits.
2. Fill in `LiveMetaModelClient.Configuration` and implement the four
   TODO methods in `MetaModelClient.swift`. Nothing else should need
   to change: prompts are in `Prompts.swift`, validation lives in
   `FridgePipeline.recipes`.
3. Flip `useLiveAPI` to `true` in `App/FridgeViewModel.swift`.
4. Never commit the API key.

## Design rules (from the brief — do not break these)

- Recipes are generated ONLY from the user-confirmed inventory.
- A `cookNow` recipe must have an empty shopping list; a `needsBuys`
  recipe must list every missing item and stay within the user's cap.
  Enforced twice: in the prompt and again in `FridgePipeline`.
- In party mode the cap is money: the menu's total estimated buy cost
  must not exceed the party budget, or the pipeline throws `overBudget`.
  Buy prices are always labeled estimates, never store quotes.
- Recipe steps are structured (minutes, resource, passive) because the
  backward scheduler consumes them. The scheduler in this package is a
  scaffold honoring the contract of Ilam's production Cooking app core;
  swap it there without touching pipeline or UI.
- Every model call goes through `MetaModelClient`. No direct networking
  anywhere else.
- If a stage fails, show the error and return to the previous stage.
  Never substitute mock output for a failed live call silently.
