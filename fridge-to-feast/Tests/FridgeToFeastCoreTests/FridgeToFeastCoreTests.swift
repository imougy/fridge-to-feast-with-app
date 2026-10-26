import XCTest
@testable import FridgeToFeastCore

/// Smoke tests over the mock pipeline: the whole flow must work offline,
/// and the promises must hold — honest buy lists, the solo buy cap,
/// the party budget, and a timeline that ends at the serve time.
final class FridgeToFeastCoreTests: XCTestCase {

    private func makePipeline() -> FridgePipeline {
        FridgePipeline(client: MockMetaModelClient(simulatedDelay: .zero))
    }

    func testFullMockFlow() async throws {
        let pipeline = makePipeline()
        let photos = [
            CapturedPhoto(kind: .fridge, imageData: Data()),
            CapturedPhoto(kind: .spices, imageData: Data()),
        ]

        let items = try await pipeline.segment(photos: photos)
        XCTAssertFalse(items.isEmpty)
        XCTAssertEqual(Set(items.map(\.photoID)), Set(photos.map(\.id)))

        let inventory = try await pipeline.identify(items: items, photos: photos)
        XCTAssertTrue(inventory.contains { $0.name == "eggs" })
        XCTAssertTrue(inventory.contains { $0.name == "cumin" && $0.category == .spice })

        let recipes = try await pipeline.recipes(inventory: inventory, preferences: Preferences())
        XCTAssertFalse(recipes.filter { $0.kind == .cookNow }.isEmpty)
        XCTAssertFalse(recipes.filter { $0.kind == .needsBuys }.isEmpty)
        XCTAssertTrue(recipes.allSatisfy(\.isHonest))
    }

    func testBuyCapZeroRemovesQuickBuyGroup() async throws {
        let pipeline = makePipeline()
        let inventory = [Ingredient(name: "eggs")]
        let recipes = try await pipeline.recipes(
            inventory: inventory, preferences: Preferences(maxBuyItems: 0))
        XCTAssertTrue(recipes.allSatisfy { $0.kind == .cookNow })
    }

    func testDishImagePromptUsesRecipeIngredients() {
        let recipe = Recipe(
            title: "Shakshuka", summary: "", minutes: 25, difficulty: .easy,
            kind: .cookNow, usedIngredients: ["eggs", "tomatoes"], shoppingList: [],
            optionalIngredients: [], steps: [], imagePrompt: "")
        let prompt = Prompts.dishImagePrompt(for: recipe)
        XCTAssertTrue(prompt.contains("Shakshuka"))
        XCTAssertTrue(prompt.contains("eggs"))
    }

    // MARK: Party mode

    func testMockMenuFitsBudgetAndSchedules() async throws {
        let pipeline = makePipeline()
        let serveAt = Date(timeIntervalSince1970: 1_800_000_000)
        let party = PartyPlan(guests: 6, budgetUSD: 30, serveAt: serveAt)
        let inventory = try await pipeline.identify(items: [], photos: [])

        let plan = try await pipeline.menu(inventory: inventory, party: party, preferences: Preferences())
        XCTAssertEqual(plan.recipes.count, 3)
        XCTAssertTrue(plan.recipes.allSatisfy { $0.servings == 6 })
        XCTAssertTrue(plan.fitsBudget)
        XCTAssertEqual(plan.totalBuyCostUSD, 6.50, accuracy: 0.001)

        let timeline = plan.timeline
        XCTAssertFalse(timeline.tasks.isEmpty)
        XCTAssertTrue(timeline.startCookingAt < serveAt)
        // Every dish's last task ends at (or before) the serve time.
        for recipe in plan.recipes {
            let lastEnd = timeline.tasks.filter { $0.recipeTitle == recipe.title }.map(\.end).max()
            XCTAssertNotNil(lastEnd)
            XCTAssertLessThanOrEqual(lastEnd!, serveAt)
        }
        // One cook: no two active tasks overlap anywhere on the timeline.
        let active = timeline.tasks.filter { !$0.isPassive }
        for i in active.indices {
            for j in active.indices where j > i {
                let overlap = active[i].start < active[j].end && active[j].start < active[i].end
                XCTAssertFalse(overlap, "\(active[i].stepText) overlaps \(active[j].stepText)")
            }
        }
    }

    func testOverBudgetMenuIsRejected() async throws {
        let pipeline = makePipeline()
        let party = PartyPlan(guests: 6, budgetUSD: 5, serveAt: Date())
        do {
            _ = try await pipeline.menu(inventory: [], party: party, preferences: Preferences())
            XCTFail("A $6.50 menu must not pass a $5 budget")
        } catch MetaModelError.overBudget(let total, let budget) {
            XCTAssertEqual(total, 6.50, accuracy: 0.001)
            XCTAssertEqual(budget, 5)
        }
    }

    func testSchedulerShiftsEarlierToResolveOvenConflict() {
        func dish(_ title: String) -> Recipe {
            Recipe(title: title, summary: "", minutes: 30, difficulty: .easy,
                   kind: .cookNow, usedIngredients: [], shoppingList: [],
                   optionalIngredients: [],
                   steps: [RecipeStep(text: "Roast", minutes: 30, resource: .oven, isPassive: true)],
                   imagePrompt: "")
        }
        let serveAt = Date(timeIntervalSince1970: 1_800_000_000)
        let timeline = BackwardScheduler.schedule(recipes: [dish("A"), dish("B")], serveAt: serveAt)
        // Both want the oven for the same 30 minutes; one must move earlier.
        XCTAssertEqual(timeline.tasks.count, 2)
        XCTAssertNotEqual(timeline.tasks[0].start, timeline.tasks[1].start)
        XCTAssertEqual(timeline.startCookingAt, serveAt.addingTimeInterval(-60 * 60))
    }
}

/// Keyframe selection: blur is dropped, duplicates collapse, the cap
/// keeps the whole sweep covered. Pure logic, no media frameworks.
final class KeyframeSelectorTests: XCTestCase {

    private func frame(_ timestamp: Double, _ sharpness: Double) -> FrameCandidate {
        FrameCandidate(timestamp: timestamp, sharpness: sharpness, imageData: Data())
    }

    func testBlurryFramesAreDropped() {
        let frames = [frame(0.0, 100), frame(0.4, 10), frame(2.0, 90)]
        let picked = KeyframeSelector.select(from: frames)
        XCTAssertEqual(picked.map(\.timestamp), [0.0, 2.0])
    }

    func testCloseFramesKeepTheSharperOne() {
        let frames = [frame(0.0, 80), frame(0.3, 120), frame(3.0, 110)]
        let picked = KeyframeSelector.select(from: frames)
        XCTAssertEqual(picked.map(\.timestamp), [0.3, 3.0])
    }

    func testCapThinsAcrossTheWholeSweep() {
        let frames = (0..<20).map { frame(Double($0), 100) }
        let picked = KeyframeSelector.select(
            from: frames, config: KeyframeConfig(maxFrames: 5, minGapSeconds: 0.1))
        XCTAssertEqual(picked.count, 5)
        XCTAssertEqual(picked.first?.timestamp, 0)
        XCTAssertEqual(picked.last?.timestamp, 19)
    }

    func testFramesBecomePhotosOfTheRightKind() {
        let photos = KeyframeSelector.photos(from: [frame(1.5, 100)], kind: .spices)
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(photos.first?.kind, .spices)
        XCTAssertEqual(photos.first?.videoTimestamp, 1.5)
    }
}
