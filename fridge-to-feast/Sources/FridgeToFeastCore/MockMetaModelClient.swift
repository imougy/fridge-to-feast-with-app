import Foundation

/// A MetaModelClient that answers with canned, realistic data and never
/// touches the network. This is the demo safety net: the full app flow must
/// run in mock mode with zero connectivity (see the project brief).
///
/// The canned kitchen matches the demo script: a fridge with eggs, peppers,
/// tomatoes and greens, and a spice cabinet with cumin and smoked paprika,
/// which is what makes the shakshuka the hero recipe. The mock party menu
/// (6 guests, $30) costs $6.50 in buys — most of the menu is already home.
public final class MockMetaModelClient: MetaModelClient, @unchecked Sendable {
    /// Artificial latency so loading states get exercised in mock mode too.
    public var simulatedDelay: Duration

    public init(simulatedDelay: Duration = .milliseconds(600)) {
        self.simulatedDelay = simulatedDelay
    }

    private func pause() async {
        try? await Task.sleep(for: simulatedDelay)
    }

    // MARK: Segmentation — plausible boxes per photo kind

    public func segment(photo: CapturedPhoto) async throws -> [SegmentedItem] {
        await pause()
        let labels: [(String, NormalizedRect, Double)]
        switch photo.kind {
        case .fridge:
            labels = [
                ("eggs",        NormalizedRect(x: 0.08, y: 0.10, width: 0.30, height: 0.22), 0.97),
                ("bell pepper", NormalizedRect(x: 0.45, y: 0.12, width: 0.22, height: 0.25), 0.93),
                ("tomatoes",    NormalizedRect(x: 0.70, y: 0.10, width: 0.25, height: 0.20), 0.95),
                ("onion",       NormalizedRect(x: 0.12, y: 0.45, width: 0.18, height: 0.18), 0.90),
                ("garlic",      NormalizedRect(x: 0.35, y: 0.48, width: 0.14, height: 0.14), 0.88),
                ("spinach",     NormalizedRect(x: 0.55, y: 0.42, width: 0.30, height: 0.24), 0.91),
                ("milk",        NormalizedRect(x: 0.10, y: 0.70, width: 0.16, height: 0.26), 0.94),
                ("cheddar",     NormalizedRect(x: 0.32, y: 0.72, width: 0.24, height: 0.16), 0.89),
                ("carrots",     NormalizedRect(x: 0.62, y: 0.70, width: 0.30, height: 0.18), 0.92),
            ]
        case .spices:
            labels = [
                ("cumin jar",         NormalizedRect(x: 0.06, y: 0.15, width: 0.16, height: 0.55), 0.96),
                ("smoked paprika jar", NormalizedRect(x: 0.26, y: 0.15, width: 0.16, height: 0.55), 0.95),
                ("turmeric jar",      NormalizedRect(x: 0.46, y: 0.15, width: 0.16, height: 0.55), 0.94),
                ("chili flakes jar",  NormalizedRect(x: 0.66, y: 0.15, width: 0.16, height: 0.55), 0.93),
                ("oregano jar",       NormalizedRect(x: 0.84, y: 0.15, width: 0.14, height: 0.55), 0.90),
            ]
        case .pantry:
            labels = [
                ("rice bag",  NormalizedRect(x: 0.10, y: 0.20, width: 0.30, height: 0.50), 0.92),
                ("pasta box", NormalizedRect(x: 0.50, y: 0.18, width: 0.22, height: 0.55), 0.91),
            ]
        }
        return labels.map { SegmentedItem(photoID: photo.id, rawLabel: $0.0, box: $0.1, confidence: $0.2) }
    }

    // MARK: Identify — the merged, deduped inventory

    public func identify(items: [SegmentedItem], photos: [CapturedPhoto]) async throws -> [Ingredient] {
        await pause()
        // In mock mode the inventory is fixed (it describes the canned
        // kitchen), but the shape honors the contract: spices flagged,
        // jar suffixes cleaned, duplicates merged.
        return [
            Ingredient(name: "eggs", quantityNote: "6 left"),
            Ingredient(name: "bell peppers", quantityNote: "2"),
            Ingredient(name: "tomatoes", quantityNote: "4"),
            Ingredient(name: "onion"),
            Ingredient(name: "garlic"),
            Ingredient(name: "spinach", quantityNote: "1 bag"),
            Ingredient(name: "milk", quantityNote: "half full"),
            Ingredient(name: "cheddar"),
            Ingredient(name: "carrots", quantityNote: "5"),
            Ingredient(name: "cumin", category: .spice),
            Ingredient(name: "smoked paprika", category: .spice),
            Ingredient(name: "turmeric", category: .spice),
            Ingredient(name: "chili flakes", category: .spice),
            Ingredient(name: "oregano", category: .spice),
        ]
    }

    // MARK: Solo recipes — both groups, honest by construction

    public func generateRecipes(inventory: [Ingredient], preferences: Preferences) async throws -> [Recipe] {
        await pause()
        let recipes: [Recipe] = [
            Recipe(
                title: "Shakshuka",
                summary: "Eggs poached in a smoky, cumin-spiced tomato and pepper sauce, straight from the skillet.",
                minutes: 25, difficulty: .easy, kind: .cookNow, servings: 2,
                usedIngredients: ["eggs", "tomatoes", "bell peppers", "onion", "garlic", "cumin", "smoked paprika", "chili flakes"],
                shoppingList: [],
                optionalIngredients: ["cheddar"],
                steps: [
                    RecipeStep(text: "Soften the onion and bell peppers in olive oil.", minutes: 6, resource: .stovetop),
                    RecipeStep(text: "Add garlic, cumin, smoked paprika, and a pinch of chili flakes; stir.", minutes: 1, resource: .stovetop),
                    RecipeStep(text: "Add the tomatoes, crush them in the pan, and simmer until thick.", minutes: 10, resource: .stovetop, isPassive: true),
                    RecipeStep(text: "Make wells, crack in the eggs, cover, and cook until the whites set.", minutes: 6, resource: .stovetop, isPassive: true),
                    RecipeStep(text: "Rest, then serve in the skillet with any bread you have.", minutes: 2, resource: .none, isPassive: true),
                ],
                imagePrompt: "Overhead food photograph of shakshuka, eggs poached in rich red tomato and pepper sauce in a cast iron skillet, on a wooden home kitchen table, natural window light, realistic home cooking, no text, no people."
            ),
            Recipe(
                title: "Creamy Garlic Spinach Pasta",
                summary: "Pantry pasta folded through a quick garlic, spinach, and cheddar cream sauce.",
                minutes: 20, difficulty: .easy, kind: .cookNow, servings: 2,
                usedIngredients: ["garlic", "spinach", "milk", "cheddar", "oregano"],
                shoppingList: [],
                optionalIngredients: ["chili flakes"],
                steps: [
                    RecipeStep(text: "Boil pasta in well-salted water; save a mug of the pasta water.", minutes: 9, resource: .stovetop, isPassive: true),
                    RecipeStep(text: "Sizzle sliced garlic in butter until golden at the edges.", minutes: 3, resource: .stovetop),
                    RecipeStep(text: "Add spinach by the handful until wilted, then the milk; simmer.", minutes: 4, resource: .stovetop),
                    RecipeStep(text: "Off the heat, stir in grated cheddar and oregano until glossy.", minutes: 2, resource: .counter),
                    RecipeStep(text: "Toss the pasta through with splashes of pasta water and serve.", minutes: 2, resource: .counter),
                ],
                imagePrompt: "Overhead food photograph of creamy garlic spinach pasta in a wide bowl, glossy cheddar sauce and wilted spinach, on a wooden home kitchen table, natural window light, realistic home cooking, no text, no people."
            ),
            Recipe(
                title: "Golden Carrot & Lentil Soup",
                summary: "A turmeric-gold soup that turns the carrots and onion you have into the best thing on this list, for the price of lentils and a lemon.",
                minutes: 35, difficulty: .easy, kind: .needsBuys, servings: 2,
                usedIngredients: ["carrots", "onion", "garlic", "turmeric", "cumin"],
                shoppingList: [ShoppingItem(name: "red lentils", estimatedCostUSD: 2.50),
                               ShoppingItem(name: "lemon", estimatedCostUSD: 1.00)],
                optionalIngredients: ["spinach"],
                steps: [
                    RecipeStep(text: "Soften onion and carrots in oil.", minutes: 8, resource: .stovetop),
                    RecipeStep(text: "Add garlic, turmeric, and cumin; stir.", minutes: 1, resource: .stovetop),
                    RecipeStep(text: "Add rinsed red lentils and 1.2 L water; simmer.", minutes: 20, resource: .stovetop, isPassive: true),
                    RecipeStep(text: "Blend half the soup and stir it back in for body.", minutes: 4, resource: .counter),
                    RecipeStep(text: "Finish with lemon juice and salt; rest before serving.", minutes: 2, resource: .none, isPassive: true),
                ],
                imagePrompt: "Overhead food photograph of golden carrot and red lentil soup in a ceramic bowl with a lemon wedge beside it, on a wooden home kitchen table, natural window light, realistic home cooking, no text, no people."
            ),
            Recipe(
                title: "Smoky Pepper & Bean Tacos",
                summary: "Charred peppers and onions with paprika black beans in warm tortillas, cheddar over the top.",
                minutes: 30, difficulty: .medium, kind: .needsBuys, servings: 2,
                usedIngredients: ["bell peppers", "onion", "garlic", "smoked paprika", "cumin", "cheddar"],
                shoppingList: [ShoppingItem(name: "black beans (1 can)", estimatedCostUSD: 1.50),
                               ShoppingItem(name: "corn tortillas", estimatedCostUSD: 2.50)],
                optionalIngredients: ["chili flakes"],
                steps: [
                    RecipeStep(text: "Char the peppers and onion in a dry hot pan until blistered at the edges.", minutes: 8, resource: .stovetop),
                    RecipeStep(text: "Add garlic, smoked paprika, and cumin; stir.", minutes: 1, resource: .stovetop),
                    RecipeStep(text: "Add drained black beans with a splash of water; simmer, lightly mashing a few.", minutes: 8, resource: .stovetop, isPassive: true),
                    RecipeStep(text: "Warm the tortillas directly over a flame or in the pan.", minutes: 3, resource: .stovetop),
                    RecipeStep(text: "Fill, top with cheddar, and rest so it melts through.", minutes: 2, resource: .none, isPassive: true),
                ],
                imagePrompt: "Overhead food photograph of smoky pepper and black bean tacos with melted cheddar on a ceramic plate, on a wooden home kitchen table, natural window light, realistic home cooking, no text, no people."
            ),
        ]
        // Honor the user's buy cap the same way the live path must.
        return recipes.filter { $0.kind == .cookNow || $0.shoppingList.count <= preferences.maxBuyItems }
    }

    // MARK: Party menu — 3 dishes for the demo scenario
    // (6 guests, $30 budget, $6.50 of buys: the feast is already home.)

    public func generateMenu(inventory: [Ingredient], party: PartyPlan,
                             preferences: Preferences) async throws -> [Recipe] {
        await pause()
        let guests = party.guests
        return [
            Recipe(
                title: "Golden Carrot & Lentil Soup",
                summary: "Starter: a turmeric-gold soup that stretches five carrots into a first course for \(guests).",
                minutes: 35, difficulty: .easy, kind: .needsBuys, servings: guests,
                usedIngredients: ["carrots", "onion", "garlic", "turmeric", "cumin"],
                shoppingList: [ShoppingItem(name: "red lentils", estimatedCostUSD: 2.50),
                               ShoppingItem(name: "lemon", estimatedCostUSD: 1.00)],
                optionalIngredients: ["spinach"],
                steps: [
                    RecipeStep(text: "Soften onion and carrots in oil.", minutes: 8, resource: .stovetop),
                    RecipeStep(text: "Add garlic, turmeric, and cumin; stir.", minutes: 1, resource: .stovetop),
                    RecipeStep(text: "Add lentils and water; simmer while you work on the other dishes.", minutes: 20, resource: .stovetop, isPassive: true),
                    RecipeStep(text: "Blend half, stir back in, finish with lemon and salt.", minutes: 4, resource: .counter),
                    RecipeStep(text: "Hold warm until serving.", minutes: 2, resource: .none, isPassive: true),
                ],
                imagePrompt: "Overhead food photograph of golden carrot and red lentil soup served for a dinner party, ceramic bowls on a set table, natural light, realistic home cooking, no text, no people."
            ),
            Recipe(
                title: "Shakshuka for a Crowd",
                summary: "Main: the big skillet goes to the middle of the table. Smoky tomato and pepper sauce, eggs poached in it, bread for swiping.",
                minutes: 30, difficulty: .easy, kind: .cookNow, servings: guests,
                usedIngredients: ["eggs", "tomatoes", "bell peppers", "onion", "garlic", "cumin", "smoked paprika", "chili flakes"],
                shoppingList: [],
                optionalIngredients: ["cheddar"],
                steps: [
                    RecipeStep(text: "Soften the onion and bell peppers in olive oil in your largest skillet.", minutes: 7, resource: .stovetop),
                    RecipeStep(text: "Add garlic, cumin, smoked paprika, and chili flakes; stir.", minutes: 1, resource: .stovetop),
                    RecipeStep(text: "Add the tomatoes, crush, and simmer until thick.", minutes: 12, resource: .stovetop, isPassive: true),
                    RecipeStep(text: "Make wells and crack in the eggs; cover until the whites set.", minutes: 7, resource: .stovetop, isPassive: true),
                    RecipeStep(text: "Rest, then carry the skillet straight to the table.", minutes: 3, resource: .none, isPassive: true),
                ],
                imagePrompt: "Overhead food photograph of a large skillet of shakshuka for a dinner party, eggs poached in rich red sauce, set table, natural light, realistic home cooking, no text, no people."
            ),
            Recipe(
                title: "Crispy Smoked Paprika Potato Wedges",
                summary: "Side: the oven does this one alone. Smoked paprika and a hard roast make plain potatoes taste like the plan all along.",
                minutes: 45, difficulty: .easy, kind: .needsBuys, servings: guests,
                usedIngredients: ["smoked paprika", "garlic", "oregano"],
                shoppingList: [ShoppingItem(name: "potatoes (3 lb)", estimatedCostUSD: 3.00)],
                optionalIngredients: ["cheddar"],
                steps: [
                    RecipeStep(text: "Heat the oven to 425°F. Cut potatoes into wedges; toss with oil, smoked paprika, garlic, oregano, and salt.", minutes: 8, resource: .counter),
                    RecipeStep(text: "Roast, undisturbed.", minutes: 20, resource: .oven, isPassive: true),
                    RecipeStep(text: "Turn the wedges once.", minutes: 2, resource: .oven),
                    RecipeStep(text: "Roast until crisp at the edges.", minutes: 13, resource: .oven, isPassive: true),
                    RecipeStep(text: "Rest on the tray; they crisp further as they sit.", minutes: 2, resource: .none, isPassive: true),
                ],
                imagePrompt: "Overhead food photograph of crispy smoked paprika potato wedges on a baking tray at a dinner party table, natural light, realistic home cooking, no text, no people."
            ),
        ]
    }

    // MARK: Dish render — mock returns no bytes; the UI shows its
    // labeled placeholder in mock mode (by design, see README).

    public func renderDish(recipe: Recipe) async throws -> Data {
        await pause()
        return Data()
    }
}
