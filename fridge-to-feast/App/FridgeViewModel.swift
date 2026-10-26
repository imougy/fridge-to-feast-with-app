import Foundation
import FridgeToFeastCore

/// Set to true at kickoff once LiveMetaModelClient has real credentials.
/// Until then the app runs entirely on the mock client, which is also
/// the permanent demo safety net (see the project brief).
private let useLiveAPI = false

@MainActor
final class FridgeViewModel: ObservableObject {
    enum Stage {
        case capture
        case working(String)
        case confirm
        case recipes
        case menu
        case cooking(Recipe)
    }

    @Published var stage: Stage = .capture
    @Published var photos: [CapturedPhoto] = []
    @Published var items: [SegmentedItem] = []
    @Published var inventory: [Ingredient] = []
    /// Items the user typed in themselves. Kept apart from the detected
    /// inventory so a re-analysis never wipes them, and so they get
    /// their own section instead of getting lost among detections.
    @Published var userAdded: [Ingredient] = []
    @Published var recipes: [Recipe] = []
    @Published var menuPlan: MenuPlan?
    @Published var dishImages: [UUID: Data] = [:]
    @Published var preferences = Preferences()
    @Published var errorMessage: String?
    /// True while a sweep video is being turned into frames.
    @Published var isExtracting = false

    // Party mode inputs. When `hosting` is on, the confirm screen plans
    // a menu + timeline instead of solo recipes.
    @Published var hosting = false
    @Published var guests = 6
    @Published var budgetUSD = 30.0
    @Published var serveAt = FridgeViewModel.defaultServeTime()

    private let pipeline: FridgePipeline

    init() {
        let client: any MetaModelClient = useLiveAPI
            ? LiveMetaModelClient(configuration: nil) // TODO kickoff: real configuration
            : MockMetaModelClient()
        self.pipeline = FridgePipeline(client: client)
    }

    /// Tonight at 7:30 PM local — the demo scenario's serve time.
    static func defaultServeTime() -> Date {
        var cal = Calendar.current
        cal.timeZone = .current
        return cal.date(bySettingHour: 19, minute: 30, second: 0, of: Date()) ?? Date()
    }

    var cookNowRecipes: [Recipe] { recipes.filter { $0.kind == .cookNow } }
    var quickBuyRecipes: [Recipe] { recipes.filter { $0.kind == .needsBuys } }

    /// True while the app runs on canned mock data instead of the live API.
    var isMockMode: Bool { !useLiveAPI }

    /// Back is available on every stage after capture.
    var canGoBack: Bool {
        switch stage {
        case .capture, .working: false
        default: true
        }
    }

    /// Step back one stage, keeping photos, items, and inventory intact.
    func goBack() {
        switch stage {
        case .confirm: stage = .capture
        case .recipes, .menu: stage = .confirm
        case .cooking: stage = menuPlan != nil ? .menu : .recipes
        default: break
        }
    }

    /// Remove one detected box, and the matching inventory ingredient
    /// (if any) so a fix here flows through to the recipes.
    func removeSegmentedItem(_ item: SegmentedItem) {
        items.removeAll { $0.id == item.id }
        let target = Self.normalized(item.rawLabel)
        inventory.removeAll { Self.normalized($0.name) == target }
    }

    /// Matches a detected label to an inventory name: "cumin jar" to
    /// "cumin", "bell pepper" to "bell peppers", "tomatoes" to "tomatoes".
    private static func normalized(_ name: String) -> String {
        var n = name.lowercased()
        if n.hasSuffix(" jar") { n = String(n.dropLast(4)) }
        if n.hasSuffix("oes") { n = String(n.dropLast(2)) }
        else if n.hasSuffix("s") { n = String(n.dropLast(1)) }
        return n
    }

    // MARK: Flow

    func addPhoto(kind: PhotoKind, data: Data) {
        photos.append(CapturedPhoto(kind: kind, imageData: data))
    }

    func removePhoto(_ photo: CapturedPhoto) {
        photos.removeAll { $0.id == photo.id }
    }

    /// Turns a sweep video into stills (sharpest frames only, on device)
    /// and adds them as photos of the given kind.
    func addSweepVideo(kind: PhotoKind, url: URL) {
        isExtracting = true
        Task {
            let frames = await VideoFrameExtractor.extract(from: url, kind: kind)
            photos.append(contentsOf: frames)
            isExtracting = false
            if frames.isEmpty {
                errorMessage = "No usable frames in that video. Try a slower sweep, or add still photos."
            }
        }
    }

    /// Stage 1+2: segment all photos, merge into an inventory, then STOP.
    /// The user confirms the inventory before any recipe is generated.
    func analyze() {
        Task {
            stage = .working("Reading your kitchen…")
            do {
                items = try await pipeline.segment(photos: photos)
                stage = .working("Naming what it found…")
                inventory = try await pipeline.identify(items: items, photos: photos)
                stage = .confirm
            } catch {
                errorMessage = error.localizedDescription
                stage = .capture
            }
        }
    }

    func removeIngredient(_ ingredient: Ingredient) {
        inventory.removeAll { $0.id == ingredient.id }
    }

    func removeUserAdded(_ ingredient: Ingredient) {
        userAdded.removeAll { $0.id == ingredient.id }
    }

    func addIngredient(name: String, category: Ingredient.Category) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        userAdded.append(Ingredient(name: trimmed.lowercased(), category: category, source: .userAdded))
    }

    /// Detected plus user-added: this is what recipes are built from.
    var confirmedInventory: [Ingredient] { inventory + userAdded }

    /// Stage 3, solo: recipes from the confirmed inventory only.
    func makeRecipes() {
        Task {
            stage = .working("Inventing tonight's options…")
            do {
                recipes = try await pipeline.recipes(inventory: confirmedInventory, preferences: preferences)
                stage = .recipes
                loadDishImages(for: recipes)
            } catch {
                errorMessage = error.localizedDescription
                stage = .confirm
            }
        }
    }

    /// Stage 3, party: compose the menu under budget and lay it backward
    /// from the serve time with the scheduler.
    func makeMenu() {
        Task {
            stage = .working("Composing your menu…")
            do {
                let party = PartyPlan(guests: guests, budgetUSD: budgetUSD, serveAt: serveAt)
                let plan = try await pipeline.menu(inventory: confirmedInventory, party: party, preferences: preferences)
                menuPlan = plan
                stage = .menu
                loadDishImages(for: plan.recipes)
            } catch MetaModelError.overBudget(let total, let budget) {
                errorMessage = String(format: "That menu came back at $%.2f of buys, over your $%.0f budget. Try again or raise the budget.", total, budget)
                stage = .confirm
            } catch {
                errorMessage = error.localizedDescription
                stage = .confirm
            }
        }
    }

    /// Stage 4: render each dish in the background; cards show a
    /// placeholder until (and unless) real image bytes arrive.
    private func loadDishImages(for dishes: [Recipe]) {
        for recipe in dishes {
            Task {
                if let data = try? await pipeline.renderDish(recipe: recipe), !data.isEmpty {
                    dishImages[recipe.id] = data
                }
            }
        }
    }

    func startCooking(_ recipe: Recipe) {
        stage = .cooking(recipe)
    }

    func reset() {
        photos = []
        items = []
        inventory = []
        userAdded = []
        recipes = []
        menuPlan = nil
        dishImages = [:]
        stage = .capture
    }
}
