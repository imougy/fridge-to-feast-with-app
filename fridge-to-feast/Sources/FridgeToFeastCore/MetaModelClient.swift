import Foundation

/// The seam between Fridge-to-Feast and Meta's models. Every model call in
/// the app goes through this protocol, which is what makes mock mode (and
/// swapping an endpoint at kickoff) a one-file change.
///
/// Pipeline contract:
/// 1. `segment` runs once per photo (SAM 3.1).
/// 2. `identify` runs once over ALL photos' items together (Muse Spark),
///    so cross-photo duplicates merge and spices are flagged as spices.
/// 3. Solo: `generateRecipes` runs on the user-confirmed inventory only.
///    Party: `generateMenu` composes a multi-dish menu for the guest
///    count, with the total buy cost capped by the party budget.
/// 4. `renderDish` runs per recipe card (Muse Image).
public protocol MetaModelClient: Sendable {
    func segment(photo: CapturedPhoto) async throws -> [SegmentedItem]
    func identify(items: [SegmentedItem], photos: [CapturedPhoto]) async throws -> [Ingredient]
    func generateRecipes(inventory: [Ingredient], preferences: Preferences) async throws -> [Recipe]
    func generateMenu(inventory: [Ingredient], party: PartyPlan, preferences: Preferences) async throws -> [Recipe]
    func renderDish(recipe: Recipe) async throws -> Data
}

public enum MetaModelError: Error, Sendable {
    /// Live client used before kickoff configuration (endpoint / API key).
    case notConfigured(String)
    case httpStatus(Int)
    case malformedResponse(String)
    /// A decoded recipe broke its group promise (see Recipe.isHonest).
    case dishonestRecipe(String)
    /// A decoded party menu's total buy cost exceeded the party budget.
    case overBudget(total: Double, budget: Double)
}

// MARK: - Live client (skeleton — wired at kickoff)

/// Talks to the Meta Model API.
///
/// KICKOFF TODO (Oct 26, first hour):
/// - Confirm the real base URL, model identifiers, and auth header from the
///   hackathon's developer docs / Discord. The values below are placeholders
///   with the right shape, not verified endpoints.
/// - Put the API key in the app via an unbundled config (never commit it).
/// Nothing outside this file should need to change when the real values land.
public final class LiveMetaModelClient: MetaModelClient {
    public struct Configuration: Sendable {
        public var baseURL: URL
        public var apiKey: String
        public var sparkModel: String
        public var samModel: String
        public var imageModel: String

        public init(baseURL: URL, apiKey: String,
                    sparkModel: String = "muse-spark",       // TODO kickoff: verify
                    samModel: String = "sam-3.1",             // TODO kickoff: verify
                    imageModel: String = "muse-image") {      // TODO kickoff: verify
            self.baseURL = baseURL
            self.apiKey = apiKey
            self.sparkModel = sparkModel
            self.samModel = samModel
            self.imageModel = imageModel
        }
    }

    private let config: Configuration?
    private let session: URLSession

    /// Pass nil configuration to get a client that fails loudly with
    /// `notConfigured` instead of silently falling back. The app chooses
    /// mock vs live explicitly; this client never guesses.
    public init(configuration: Configuration?, session: URLSession = .shared) {
        self.config = configuration
        self.session = session
    }

    private func requireConfig() throws -> Configuration {
        guard let config else {
            throw MetaModelError.notConfigured(
                "Meta Model API is not configured. Use MockMetaModelClient until kickoff credentials land.")
        }
        return config
    }

    public func segment(photo: CapturedPhoto) async throws -> [SegmentedItem] {
        let config = try requireConfig()
        _ = config
        // TODO kickoff: POST the photo to the SAM 3.1 segmentation endpoint,
        // map returned masks to SegmentedItem with photoID = photo.id.
        throw MetaModelError.notConfigured("segment: endpoint mapping pending kickoff docs")
    }

    public func identify(items: [SegmentedItem], photos: [CapturedPhoto]) async throws -> [Ingredient] {
        let config = try requireConfig()
        _ = config
        // TODO kickoff: send all photos + item labels to Muse Spark with
        // Prompts.identifyPrompt; decode [Ingredient] as strict JSON.
        throw MetaModelError.notConfigured("identify: endpoint mapping pending kickoff docs")
    }

    public func generateRecipes(inventory: [Ingredient], preferences: Preferences) async throws -> [Recipe] {
        let config = try requireConfig()
        _ = config
        // TODO kickoff: send Prompts.recipePrompt(inventory:preferences:) to
        // Muse Spark, decode [Recipe] as strict JSON, then validate:
        //   - drop any recipe where !isHonest
        //   - drop needsBuys recipes whose shoppingList.count > preferences.maxBuyItems
        //   - one repair retry on malformed JSON, then throw malformedResponse
        throw MetaModelError.notConfigured("generateRecipes: endpoint mapping pending kickoff docs")
    }

    public func generateMenu(inventory: [Ingredient], party: PartyPlan, preferences: Preferences) async throws -> [Recipe] {
        let config = try requireConfig()
        _ = config
        // TODO kickoff: send Prompts.menuPrompt(inventory:party:preferences:)
        // to Muse Spark, decode [Recipe] as strict JSON, then validate:
        //   - drop any recipe where !isHonest
        //   - the MENU is over budget if the total buy cost exceeds
        //     party.budgetUSD; ask once for a cheaper revision, then throw
        //   - every recipe's servings must equal party.guests
        throw MetaModelError.notConfigured("generateMenu: endpoint mapping pending kickoff docs")
    }

    public func renderDish(recipe: Recipe) async throws -> Data {
        let config = try requireConfig()
        _ = config
        // TODO kickoff: send recipe.imagePrompt to Muse Image, return image bytes.
        throw MetaModelError.notConfigured("renderDish: endpoint mapping pending kickoff docs")
    }
}
