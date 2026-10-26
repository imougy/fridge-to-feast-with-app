import Foundation

/// What kind of kitchen photo this is. Spices are a first-class input, not
/// an afterthought: they decide what a dish can become.
public enum PhotoKind: String, Codable, Sendable {
    case fridge
    case spices
    case pantry
}

/// One photo the user took during capture, OR one selected frame from a
/// sweep video (`videoTimestamp` set in that case). The image bytes ride
/// along in memory only; this type is deliberately not Codable.
public struct CapturedPhoto: Identifiable, Sendable {
    public var id: UUID
    public var kind: PhotoKind
    public var imageData: Data
    /// Seconds into the source video when this photo is a video frame.
    public var videoTimestamp: Double?
    /// Groups the frames of one sweep video together; nil for still photos.
    public var sourceID: UUID?

    public init(id: UUID = UUID(), kind: PhotoKind, imageData: Data,
                videoTimestamp: Double? = nil, sourceID: UUID? = nil) {
        self.id = id
        self.kind = kind
        self.imageData = imageData
        self.videoTimestamp = videoTimestamp
        self.sourceID = sourceID
    }
}

/// A normalized rectangle (0...1 coordinates) so the core package never
/// depends on CoreGraphics. The app layer converts to CGRect for display.
public struct NormalizedRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// One region SAM 3.1 cut out of one photo, before it is named.
/// `rawLabel` is whatever the segmentation step proposes; Muse Spark
/// confirms or corrects it against the images in the identify step,
/// and dedupes the same item appearing in two photos.
public struct SegmentedItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var photoID: UUID
    public var rawLabel: String
    public var box: NormalizedRect
    public var confidence: Double

    public init(id: UUID = UUID(), photoID: UUID, rawLabel: String,
                box: NormalizedRect, confidence: Double) {
        self.id = id
        self.photoID = photoID
        self.rawLabel = rawLabel
        self.box = box
        self.confidence = confidence
    }
}

/// A confirmed entry in the kitchen inventory. This is the only thing
/// recipe generation sees, and only after the user has had the chance
/// to correct the list.
public struct Ingredient: Codable, Identifiable, Equatable, Sendable {
    public enum Category: String, Codable, Sendable {
        case ingredient
        case spice
    }

    public enum Source: String, Codable, Sendable {
        case detected
        case userAdded
    }

    public var id: UUID
    public var name: String
    public var category: Category
    public var quantityNote: String?
    public var source: Source

    public init(id: UUID = UUID(), name: String, category: Category = .ingredient,
                quantityNote: String? = nil, source: Source = .detected) {
        self.id = id
        self.name = name
        self.category = category
        self.quantityNote = quantityNote
        self.source = source
    }
}

public enum Difficulty: String, Codable, Sendable {
    case easy, medium, hard
}

/// Which group a recipe belongs to. The distinction is a promise:
/// a cookNow recipe uses only the confirmed inventory plus staples,
/// a needsBuys recipe lists every missing item in `shoppingList`.
public enum RecipeKind: String, Codable, Sendable {
    case cookNow
    case needsBuys
}

/// One item the user does not have, with the model's estimated price.
/// Estimates are typical US grocery prices and are ALWAYS presented to
/// the user as estimates — never as store-accurate quotes.
public struct ShoppingItem: Codable, Equatable, Sendable {
    public var name: String
    public var estimatedCostUSD: Double

    public init(name: String, estimatedCostUSD: Double) {
        self.name = name
        self.estimatedCostUSD = estimatedCostUSD
    }
}

/// Kitchen equipment a step occupies. The backward scheduler treats
/// each resource as capacity 1 (one oven, one cook's attention) unless
/// the step is passive.
public enum KitchenResource: String, Codable, Sendable {
    case oven
    case stovetop
    case counter
    case none
}

/// One cooking step, structured so a scheduler can plan it — this is the
/// shape Ilam's Cooking app backward scheduling core consumes: text for
/// the human, minutes + resource + passivity for the machine.
public struct RecipeStep: Codable, Equatable, Sendable {
    public var text: String
    public var minutes: Int
    public var resource: KitchenResource
    /// Passive steps (simmering, baking, resting) occupy their resource
    /// but NOT the cook, so other dishes can advance meanwhile.
    public var isPassive: Bool

    public init(text: String, minutes: Int, resource: KitchenResource = .counter,
                isPassive: Bool = false) {
        self.text = text
        self.minutes = minutes
        self.resource = resource
        self.isPassive = isPassive
    }
}

/// One generated recipe. Decoded from Muse Spark's strict-JSON response;
/// if a response does not match this schema it is rejected, never parsed loosely.
public struct Recipe: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var summary: String
    public var minutes: Int
    public var difficulty: Difficulty
    public var kind: RecipeKind
    /// How many people this recipe, as written, serves.
    public var servings: Int
    /// Inventory items (ingredients and spices) this recipe uses.
    public var usedIngredients: [String]
    /// Items to buy. MUST be empty when kind == .cookNow, and MUST list
    /// every missing item when kind == .needsBuys. Validated after decoding.
    public var shoppingList: [ShoppingItem]
    /// Nice-to-have items already in the kitchen. Never required.
    public var optionalIngredients: [String]
    public var steps: [RecipeStep]
    /// Prompt handed to Muse Image to render the finished plate.
    public var imagePrompt: String

    public init(id: UUID = UUID(), title: String, summary: String, minutes: Int,
                difficulty: Difficulty, kind: RecipeKind, servings: Int = 2,
                usedIngredients: [String], shoppingList: [ShoppingItem],
                optionalIngredients: [String], steps: [RecipeStep], imagePrompt: String) {
        self.id = id
        self.title = title
        self.summary = summary
        self.minutes = minutes
        self.difficulty = difficulty
        self.kind = kind
        self.servings = servings
        self.usedIngredients = usedIngredients
        self.shoppingList = shoppingList
        self.optionalIngredients = optionalIngredients
        self.steps = steps
        self.imagePrompt = imagePrompt
    }

    /// The honesty check the brief promises: groups must match their buy lists.
    public var isHonest: Bool {
        switch kind {
        case .cookNow: return shoppingList.isEmpty
        case .needsBuys: return !shoppingList.isEmpty
        }
    }

    /// Sum of the estimated buy prices.
    public var buyCostUSD: Double {
        shoppingList.reduce(0) { $0 + $1.estimatedCostUSD }
    }

    /// Total scheduled time across steps (what the scheduler plans with).
    public var scheduledMinutes: Int {
        steps.reduce(0) { $0 + $1.minutes }
    }
}

/// A dinner-party request: the scenario that turns recipes into a plan.
/// "6 friends coming, $30 max, food on the table at 7:30."
public struct PartyPlan: Codable, Equatable, Sendable {
    public var guests: Int
    /// Hard cap on the TOTAL estimated cost of all buys across the menu.
    public var budgetUSD: Double
    /// When the food must be on the table.
    public var serveAt: Date

    public init(guests: Int, budgetUSD: Double, serveAt: Date) {
        self.guests = guests
        self.budgetUSD = budgetUSD
        self.serveAt = serveAt
    }
}

/// One task placed on the cooking timeline by the backward scheduler.
public struct ScheduledTask: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var recipeTitle: String
    public var stepText: String
    public var start: Date
    public var minutes: Int
    public var resource: KitchenResource
    public var isPassive: Bool

    public init(id: UUID = UUID(), recipeTitle: String, stepText: String,
                start: Date, minutes: Int, resource: KitchenResource, isPassive: Bool) {
        self.id = id
        self.recipeTitle = recipeTitle
        self.stepText = stepText
        self.start = start
        self.minutes = minutes
        self.resource = resource
        self.isPassive = isPassive
    }

    public var end: Date { start.addingTimeInterval(TimeInterval(minutes * 60)) }
}

/// The scheduler's output: every task across every dish, laid backward
/// from the serve time, plus when the cook must start and any conflicts
/// it could not resolve (surfaced, never hidden).
public struct CookingTimeline: Sendable {
    public var tasks: [ScheduledTask]
    public var startCookingAt: Date
    public var serveAt: Date
    public var warnings: [String]

    public init(tasks: [ScheduledTask], startCookingAt: Date, serveAt: Date, warnings: [String]) {
        self.tasks = tasks
        self.startCookingAt = startCookingAt
        self.serveAt = serveAt
        self.warnings = warnings
    }
}

/// A complete party plan: the menu, what it costs, and the timeline
/// that gets it all on the table together.
public struct MenuPlan: Sendable {
    public var party: PartyPlan
    public var recipes: [Recipe]
    public var timeline: CookingTimeline

    public init(party: PartyPlan, recipes: [Recipe], timeline: CookingTimeline) {
        self.party = party
        self.recipes = recipes
        self.timeline = timeline
    }

    public var totalBuyCostUSD: Double {
        recipes.reduce(0) { $0 + $1.buyCostUSD }
    }

    public var allBuys: [ShoppingItem] {
        recipes.flatMap(\.shoppingList)
    }

    public var fitsBudget: Bool { totalBuyCostUSD <= party.budgetUSD }
}

/// Household preferences, set with toggles on the home screen.
/// Stored locally by the app; no account, no server.
public struct Preferences: Codable, Equatable, Sendable {
    public var vegetarian: Bool
    public var allergies: [String]
    public var favoriteCuisines: [String]
    public var maxMinutes: Int
    /// How many "quick buy" items a needsBuys recipe may require (solo mode).
    /// Zero disables the needsBuys group entirely.
    public var maxBuyItems: Int

    public init(vegetarian: Bool = false, allergies: [String] = [],
                favoriteCuisines: [String] = [], maxMinutes: Int = 45,
                maxBuyItems: Int = 3) {
        self.vegetarian = vegetarian
        self.allergies = allergies
        self.favoriteCuisines = favoriteCuisines
        self.maxMinutes = maxMinutes
        self.maxBuyItems = maxBuyItems
    }
}

/// Everything one full solo run of the pipeline produces.
public struct FlowResult: Sendable {
    public var items: [SegmentedItem]
    public var inventory: [Ingredient]
    public var recipes: [Recipe]

    public init(items: [SegmentedItem], inventory: [Ingredient], recipes: [Recipe]) {
        self.items = items
        self.inventory = inventory
        self.recipes = recipes
    }

    public var cookNowRecipes: [Recipe] { recipes.filter { $0.kind == .cookNow } }
    public var quickBuyRecipes: [Recipe] { recipes.filter { $0.kind == .needsBuys } }
}

// MARK: - Tolerant decoding for model-produced JSON
//
// Muse Spark returns JSON in the shapes the prompts request: it invents
// content fields, never UUIDs or provenance. These decoders fill the
// app-owned fields with defaults so model JSON decodes straight into the
// core models. (Declared in extensions so the memberwise initializers
// the mock client and tests use stay available.)

extension Ingredient {
    private enum CodingKeys: String, CodingKey {
        case id, name, category, quantityNote, source
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        category = try c.decodeIfPresent(Category.self, forKey: .category) ?? .ingredient
        quantityNote = try c.decodeIfPresent(String.self, forKey: .quantityNote)
        source = try c.decodeIfPresent(Source.self, forKey: .source) ?? .detected
    }
}

extension Recipe {
    private enum CodingKeys: String, CodingKey {
        case id, title, summary, minutes, difficulty, kind, servings,
             usedIngredients, shoppingList, optionalIngredients, steps, imagePrompt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decode(String.self, forKey: .summary)
        minutes = try c.decode(Int.self, forKey: .minutes)
        difficulty = try c.decode(Difficulty.self, forKey: .difficulty)
        kind = try c.decode(RecipeKind.self, forKey: .kind)
        servings = try c.decodeIfPresent(Int.self, forKey: .servings) ?? 2
        usedIngredients = try c.decode([String].self, forKey: .usedIngredients)
        shoppingList = try c.decodeIfPresent([ShoppingItem].self, forKey: .shoppingList) ?? []
        optionalIngredients = try c.decodeIfPresent([String].self, forKey: .optionalIngredients) ?? []
        steps = try c.decode([RecipeStep].self, forKey: .steps)
        imagePrompt = try c.decode(String.self, forKey: .imagePrompt)
    }
}
