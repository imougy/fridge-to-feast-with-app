import Foundation

/// Lays every dish's steps backward from the serve time so the whole
/// menu lands on the table together, and tells the cook when to start.
///
/// NOTE: in Ilam's production Cooking app this role is played by his
/// existing backward scheduling core. This scaffold implementation honors
/// the same contract (recipes + serve time → timeline) so the hackathon
/// app can be built and demoed against it now, and swapped for the
/// production core without touching the pipeline or the UI.
///
/// Rules of the scaffold scheduler:
/// - Each dish's steps run sequentially and the dish finishes at serveAt.
/// - One cook: two *active* steps may not overlap.
/// - One oven: two oven steps may not overlap (passive or not — the oven
///   is physically occupied).
/// - Conflicts are resolved by shifting the whole dish earlier, in
///   5-minute steps, up to `maxShiftMinutes`. Anything still conflicting
///   after that is reported in `warnings`, never silently dropped.
public enum BackwardScheduler {
    public static let shiftStepMinutes = 5
    public static let maxShiftMinutes = 90

    public static func schedule(recipes: [Recipe], serveAt: Date) -> CookingTimeline {
        // Lay each dish out ending at serveAt, tracking its shift.
        var dishes: [(recipe: Recipe, shift: Int)] = recipes.map { ($0, 0) }
        var warnings: [String] = []

        // Deterministic order: longest dish first (hardest to place).
        dishes.sort { $0.recipe.scheduledMinutes > $1.recipe.scheduledMinutes }

        func tasks(for dish: (recipe: Recipe, shift: Int)) -> [ScheduledTask] {
            var cursor = serveAt.addingTimeInterval(TimeInterval(-dish.shift * 60))
            var result: [ScheduledTask] = []
            for step in dish.recipe.steps.reversed() {
                cursor = cursor.addingTimeInterval(TimeInterval(-step.minutes * 60))
                result.append(ScheduledTask(
                    recipeTitle: dish.recipe.title, stepText: step.text,
                    start: cursor, minutes: step.minutes,
                    resource: step.resource, isPassive: step.isPassive))
            }
            return result.reversed()
        }

        func conflicts(_ a: ScheduledTask, _ b: ScheduledTask) -> Bool {
            guard a.start < b.end, b.start < a.end else { return false }
            if a.resource == .oven && b.resource == .oven { return true }
            if !a.isPassive && !b.isPassive { return true } // one cook
            return false
        }

        // Place dishes one at a time; shift the newcomer earlier until it
        // fits against everything already placed.
        var placed: [ScheduledTask] = []
        for index in dishes.indices {
            var shift = 0
            var mine = tasks(for: dishes[index])
            while mine.contains(where: { task in placed.contains { conflicts(task, $0) } }),
                  shift < maxShiftMinutes {
                shift += shiftStepMinutes
                dishes[index].shift = shift
                mine = tasks(for: dishes[index])
            }
            if mine.contains(where: { task in placed.contains { conflicts(task, $0) } }) {
                warnings.append(
                    "\(dishes[index].recipe.title) still overlaps another dish after shifting \(maxShiftMinutes) min earlier; a second cook or a menu change would fix it.")
            }
            placed += mine
        }

        let sorted = placed.sorted { $0.start < $1.start }
        return CookingTimeline(
            tasks: sorted,
            startCookingAt: sorted.first?.start ?? serveAt,
            serveAt: serveAt,
            warnings: warnings)
    }
}
