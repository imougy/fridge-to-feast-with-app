import Foundation

/// Runs the pipeline in the order the UI presents it. The steps are
/// separate on purpose: the user confirms the inventory between
/// `identify` and `recipes`, so there is no single "do everything" call
/// in the real flow. `runUntilConfirmation` + `finish` mirror that.
public final class FridgePipeline: Sendable {
    private let client: any MetaModelClient

    public init(client: any MetaModelClient) {
        self.client = client
    }

    /// Stage 1 (SAM 3.1): segment every photo, keeping items tagged
    /// with the photo they came from so the UI can draw the labels.
    public func segment(photos: [CapturedPhoto]) async throws -> [SegmentedItem] {
        var all: [SegmentedItem] = []
        for photo in photos {
            all += try await client.segment(photo: photo)
        }
        return all
    }

    /// Stage 2 (Muse Spark): merge the raw items from all photos into
    /// one deduped inventory. The result goes to the confirm screen;
    /// it is NOT sent on to recipe generation until the user approves it.
    public func identify(items: [SegmentedItem], photos: [CapturedPhoto]) async throws -> [Ingredient] {
        try await client.identify(items: items, photos: photos)
    }

    /// Stage 3 (Muse Spark): recipes for the confirmed inventory.
    /// Enforces the group promises in code, not just in the prompt:
    /// dishonest recipes and over-cap buy lists are dropped here even
    /// if the model produced them.
    public func recipes(inventory: [Ingredient], preferences: Preferences) async throws -> [Recipe] {
        let raw = try await client.generateRecipes(inventory: inventory, preferences: preferences)
        return raw.filter { recipe in
            recipe.isHonest && recipe.shoppingList.count <= preferences.maxBuyItems
        }
    }

    /// Stage 3, party mode (Muse Spark + scheduler): compose a menu for
    /// the party, enforce the budget on the TOTAL buy cost in code, then
    /// lay the menu backward from the serve time. An over-budget menu is
    /// an error the UI can retry from — never a plan the user can't afford.
    public func menu(inventory: [Ingredient], party: PartyPlan,
                     preferences: Preferences) async throws -> MenuPlan {
        let raw = try await client.generateMenu(inventory: inventory, party: party, preferences: preferences)
        let honest = raw.filter(\.isHonest)
        let total = honest.reduce(0) { $0 + $1.buyCostUSD }
        guard total <= party.budgetUSD else {
            throw MetaModelError.overBudget(total: total, budget: party.budgetUSD)
        }
        let timeline = BackwardScheduler.schedule(recipes: honest, serveAt: party.serveAt)
        return MenuPlan(party: party, recipes: honest, timeline: timeline)
    }

    /// Stage 4 (Muse Image): render one recipe's plate.
    /// Empty Data means "no image available" (mock mode); the UI shows
    /// its placeholder rather than treating it as a failure.
    public func renderDish(recipe: Recipe) async throws -> Data {
        try await client.renderDish(recipe: recipe)
    }
}
