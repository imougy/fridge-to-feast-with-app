import Foundation

/// Prompt templates for the Muse Spark calls. Kept in one file so the
/// wording can be tuned during the event without touching logic.
///
/// Both prompts demand strict JSON that decodes directly into the core
/// models. If a response fails to decode, the caller retries once with
/// the repair suffix appended — it never parses free text.
public enum Prompts {

    public static let jsonRepairSuffix = """

    Your previous reply was not valid JSON for the requested schema.
    Reply again with ONLY the JSON value: no prose, no markdown fences.
    """

    /// Asks Muse Spark to turn raw segmentation labels + the photos into a
    /// clean, deduped inventory. Spices must be categorized as spices:
    /// they steer flavor, they are not main ingredients.
    public static func identifyPrompt(items: [SegmentedItem], photoKinds: [PhotoKind]) -> String {
        let labels = items.map(\.rawLabel).joined(separator: ", ")
        let kinds = photoKinds.map(\.rawValue).joined(separator: ", ")
        return """
        You are the inventory step of a cooking app. The user photographed their kitchen (\(kinds)).
        A segmentation model proposed these item labels: \(labels).

        Look at the photos and produce the true inventory:
        - Correct labels that are wrong (brands, similar-looking items).
        - Merge duplicates: the same physical item photographed twice counts once.
        - Mark anything from a spice photo, and any spice regardless of photo, as category "spice".
        - Add a short quantityNote only when the photo makes it obvious ("half full", "3 left").

        Reply with ONLY a JSON array of objects:
        [{"name": "eggs", "category": "ingredient", "quantityNote": "6 left"}]
        category is "ingredient" or "spice". Omit quantityNote when unsure.
        """
    }

    /// The shared step + recipe JSON contract. Steps are structured
    /// (minutes, resource, passive) because a scheduler consumes them;
    /// buys carry estimated prices because a budget consumes them.
    private static let recipeSchema = """
    [{"title": "...", "summary": "one appetizing sentence", "minutes": 25,
      "difficulty": "easy|medium|hard", "kind": "cookNow|needsBuys", "servings": 2,
      "usedIngredients": ["inventory names used"],
      "shoppingList": [{"name": "red lentils", "estimatedCostUSD": 2.50}],
      "optionalIngredients": [],
      "steps": [{"text": "Soften the onion in oil", "minutes": 6,
                 "resource": "stovetop|oven|counter|none", "isPassive": false}],
      "imagePrompt": "overhead photo-style description of the plated dish"}]
    Rules for steps: every step needs honest minutes; "isPassive": true only
    when the cook's hands are free (simmering, baking, resting, marinating).
    Rules for shoppingList: estimatedCostUSD is a typical US grocery price,
    your best estimate — precision is not claimed.
    """

    private static func constraintText(inventory: [Ingredient], preferences: Preferences) -> String {
        var constraints: [String] = [
            "Assume these staples are always available: salt, black pepper, cooking oil, butter, flour, rice, pasta, sugar."
        ]
        if preferences.vegetarian { constraints.append("All recipes must be vegetarian.") }
        if !preferences.allergies.isEmpty {
            constraints.append("Never use these allergens: \(preferences.allergies.joined(separator: ", ")).")
        }
        if !preferences.favoriteCuisines.isEmpty {
            constraints.append("Lean toward these cuisines when the ingredients allow: \(preferences.favoriteCuisines.joined(separator: ", ")).")
        }
        return constraints.map { "- \($0)" }.joined(separator: "\n")
    }

    private static func inventoryText(_ inventory: [Ingredient]) -> (ingredients: String, spices: String) {
        (inventory.filter { $0.category == .ingredient }.map(\.name).joined(separator: ", "),
         inventory.filter { $0.category == .spice }.map(\.name).joined(separator: ", "))
    }

    /// Solo mode: recipes in the two promised groups.
    /// The honesty rules are stated here AND enforced in code after decoding.
    public static func recipePrompt(inventory: [Ingredient], preferences: Preferences) -> String {
        let inv = inventoryText(inventory)
        return """
        You are the recipe brain of a cooking app. The user's confirmed kitchen inventory:
        Ingredients: \(inv.ingredients)
        Spices: \(inv.spices)

        Constraints:
        \(constraintText(inventory: inventory, preferences: preferences))
        - Every recipe must take at most \(preferences.maxMinutes) minutes.

        Invent exactly 4 recipes in two groups:
        - 2 with "kind": "cookNow" — use ONLY the inventory above plus the assumed staples.
          Their "shoppingList" MUST be an empty array.
        - 2 with "kind": "needsBuys" — use the inventory freely, plus at most \(preferences.maxBuyItems)
          items the user does not have. List EVERY such item in "shoppingList", nothing more.
          Only include a needsBuys recipe if the buys unlock a dish that is clearly
          better than the cookNow options; quality over quota.

        Let the spices steer the cooking: they are the difference between plain
        and memorable, and most apps ignore them. Use them by name in the steps.

        Reply with ONLY a JSON array matching this schema:
        \(recipeSchema)
        """
    }

    /// Party mode: compose ONE menu (not independent recipes) for the
    /// guest count, with the TOTAL buy cost across all dishes capped by
    /// the budget, and steps a scheduler can interleave: dishes should
    /// lean on passive time so one cook can run the whole menu.
    public static func menuPrompt(inventory: [Ingredient], party: PartyPlan,
                                  preferences: Preferences) -> String {
        let inv = inventoryText(inventory)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return """
        You are the menu planner of a cooking app. The user is hosting dinner.
        Guests: \(party.guests). Food on the table at \(formatter.string(from: party.serveAt)).
        Total budget for ALL bought items across the whole menu: $\(String(format: "%.2f", party.budgetUSD)).

        Confirmed kitchen inventory:
        Ingredients: \(inv.ingredients)
        Spices: \(inv.spices)

        Constraints:
        \(constraintText(inventory: inventory, preferences: preferences))
        - Every recipe's "servings" MUST be \(party.guests).
        - Compose a menu of 3 dishes that eat well together (for example a starter,
          a main, and a side). Dishes share ONE shopping list budget: the sum of
          every shoppingList item's estimatedCostUSD across all 3 dishes must be
          at most $\(String(format: "%.2f", party.budgetUSD)). Prefer dishes from
          the inventory; spend the budget only where it clearly upgrades the menu.
        - A dish using only inventory + staples is "kind": "cookNow" with an empty
          shoppingList; a dish needing buys is "kind": "needsBuys" listing them all.
        - ONE cook runs this menu. Design steps so dishes interleave: at least half
          of each dish's total minutes should be passive (oven, simmer, rest).
          Never require two hands-on steps from different dishes at the same time
          in a way a scheduler cannot stagger.
        - Let the spices steer the cooking, by name, in the steps.

        Reply with ONLY a JSON array matching this schema:
        \(recipeSchema)
        """
    }

    /// Muse Image prompt for one recipe card. Built from the recipe so the
    /// render shows the actual dish, styled like food photography a home
    /// cook would trust, not advertising gloss.
    public static func dishImagePrompt(for recipe: Recipe) -> String {
        let mains = recipe.usedIngredients.prefix(5).joined(separator: ", ")
        return """
        Overhead food photograph of \(recipe.title), made with \(mains). \
        Served on a simple ceramic plate on a wooden home kitchen table, \
        natural window light, realistic home cooking, no text, no people.
        """
    }
}
