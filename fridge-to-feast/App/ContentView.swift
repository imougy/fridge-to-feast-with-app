import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import FridgeToFeastCore

struct ContentView: View {
    @StateObject private var model = FridgeViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch model.stage {
                case .capture:
                    CaptureView(model: model)
                case .working(let message):
                    VStack(spacing: 16) {
                        ProgressView()
                        Text(message).foregroundStyle(.secondary)
                    }
                case .confirm:
                    ConfirmView(model: model)
                case .recipes:
                    RecipesView(model: model)
                case .menu:
                    if let plan = model.menuPlan {
                        MenuView(model: model, plan: plan)
                    }
                case .cooking(let recipe):
                    CookView(model: model, recipe: recipe)
                }
            }
            .navigationTitle("Fridge-to-Feast")
            .alert("Something went wrong", isPresented: .constant(model.errorMessage != nil)) {
                Button("OK") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
            .toolbar {
                if model.canGoBack {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") { model.goBack() }
                    }
                }
            }
        }
    }
}

// MARK: - Capture

private struct CaptureView: View {
    @ObservedObject var model: FridgeViewModel
    @State private var showingVideoPicker = false
    @State private var showingPhotoPicker = false
    @State private var pendingKind: PhotoKind = .fridge
    /// The kind locked in when an Add button is tapped. The picker loads
    /// the video file in the background, and reading pendingKind only
    /// when that finishes lets a quick switch retag the frames, so the
    /// kind is captured up front instead.
    @State private var uploadKind: PhotoKind = .fridge
    @State private var previewPhoto: CapturedPhoto?
    @State private var photoToDelete: CapturedPhoto?

    var body: some View {
        Form {
            Section("Your kitchen, captured") {
                Button { uploadKind = pendingKind; showingVideoPicker = true } label: {
                    Label("Add a sweep video (5–10 seconds)", systemImage: "video")
                }
                Button { uploadKind = pendingKind; showingPhotoPicker = true } label: {
                    Label("Add a still photo", systemImage: "photo.on.rectangle.angled")
                }
                Picker("These show my", selection: $pendingKind) {
                    Text("Fridge").tag(PhotoKind.fridge)
                    Text("Spices").tag(PhotoKind.spices)
                    Text("Pantry").tag(PhotoKind.pantry)
                }
                if model.isExtracting {
                    HStack { ProgressView(); Text("Pulling the sharpest frames…") }
                        .foregroundStyle(.secondary)
                }
                let shown = model.photos.filter { $0.kind == pendingKind }
                if shown.isEmpty {
                    Text("No \(pendingKind.rawValue) shots yet. Add a sweep video or a photo above.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(shown) { photo in
                    HStack {
                        Button { previewPhoto = photo } label: {
                            HStack {
                                if let image = UIImage(data: photo.imageData) {
                                    Image(uiImage: image)
                                        .resizable().scaledToFill()
                                        .frame(width: 44, height: 44).clipped().cornerRadius(8)
                                }
                                Label(photo.kind.rawValue.capitalized, systemImage: icon(for: photo.kind))
                                if let ts = photo.videoTimestamp {
                                    Text("frame at \(String(format: "%.1f", ts))s")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text("photo")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button(role: .destructive) { photoToDelete = photo } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                Text("A slow sweep beats stills: it sees every shelf and what hides behind the milk. The app keeps only the sharp frames.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Preferences") {
                Toggle("Vegetarian", isOn: $model.preferences.vegetarian)
                Stepper("Ready in ≤ \(model.preferences.maxMinutes) min",
                        value: $model.preferences.maxMinutes, in: 10...120, step: 5)
                Stepper("OK to buy up to \(model.preferences.maxBuyItems) items",
                        value: $model.preferences.maxBuyItems, in: 0...5)
            }
            Section("Hosting?") {
                Toggle("I'm cooking for guests", isOn: $model.hosting)
                if model.hosting {
                    Stepper("\(model.guests) guests", value: $model.guests, in: 2...12)
                    Stepper("Budget: $\(Int(model.budgetUSD)) for buys",
                            value: $model.budgetUSD, in: 10...150, step: 5)
                    DatePicker("Food on the table at", selection: $model.serveAt,
                               displayedComponents: .hourAndMinute)
                }
            }
            Section {
                Button("See what I can cook") { model.analyze() }
                    .disabled(model.photos.isEmpty)
            }
        }
        .sheet(isPresented: $showingVideoPicker) {
            LibraryPicker(media: .video, isPresented: $showingVideoPicker) { assets in
                for asset in assets {
                    if case .video(let url) = asset {
                        model.addSweepVideo(kind: uploadKind, url: url)
                    }
                }
            }
        }
        .sheet(isPresented: $showingPhotoPicker) {
            LibraryPicker(media: .photo, isPresented: $showingPhotoPicker) { assets in
                for asset in assets {
                    if case .photo(let data) = asset {
                        model.addPhoto(kind: uploadKind, data: data)
                    }
                }
            }
        }
        .fullScreenCover(item: $previewPhoto) { photo in
            NavigationStack {
                VStack(spacing: 12) {
                    if let image = UIImage(data: photo.imageData) {
                        Image(uiImage: image).resizable().scaledToFit()
                    }
                    if let ts = photo.videoTimestamp {
                        Text("Frame at \(String(format: "%.1f", ts))s").foregroundStyle(.secondary)
                    } else {
                        Text("Still photo").foregroundStyle(.secondary)
                    }
                }
                .toolbar { Button("Done") { previewPhoto = nil } }
            }
        }
        .confirmationDialog("Delete this frame?", isPresented: .constant(photoToDelete != nil)) {
            Button("Delete", role: .destructive) {
                if let photo = photoToDelete { model.removePhoto(photo) }
                photoToDelete = nil
            }
            Button("Cancel", role: .cancel) { photoToDelete = nil }
        }
    }

    private func icon(for kind: PhotoKind) -> String {
        switch kind {
        case .fridge: return "refrigerator"
        case .spices: return "leaf"
        case .pantry: return "cabinet"
        }
    }
}

// MARK: - Confirm inventory

private struct ConfirmView: View {
    @ObservedObject var model: FridgeViewModel
    @State private var newItemName = ""
    @State private var newItemIsSpice = false

    var body: some View {
        List {
            Section("What it saw") {
                if model.isMockMode {
                    Label("Demo data: no API is connected yet, so these boxes are placeholders, not detections from your photos. Fix the lists below to match your kitchen.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                ForEach(model.photos.filter { photo in model.items.contains { $0.photoID == photo.id } }) { photo in
                    let photoItems = model.items.filter { $0.photoID == photo.id }
                    VStack(alignment: .leading, spacing: 6) {
                        SegmentationOverlayView(photo: photo, items: photoItems)
                            .frame(maxWidth: 320)
                        Text("\(caption(for: photo)) · \(photoItems.count) items")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(photoItems) { item in
                            HStack {
                                Text(item.rawLabel)
                                Text(String(format: "%.0f%%", item.confidence * 100))
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button(role: .destructive) { model.removeSegmentedItem(item) } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                }
            }
            Section("Ingredients — tap trash to remove") {
                ForEach(model.inventory.filter { $0.category == .ingredient }) { ingredient in
                    row(ingredient)
                }
            }
            Section("Spices") {
                ForEach(model.inventory.filter { $0.category == .spice }) { ingredient in
                    row(ingredient)
                }
            }
            Section("Add something it missed") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("e.g. butter", text: $newItemName)
                    HStack {
                        Picker("Kind", selection: $newItemIsSpice) {
                            Text("Ingredient").tag(false)
                            Text("Spice").tag(true)
                        }
                        .pickerStyle(.segmented)
                        Button("Add") {
                            model.addIngredient(name: newItemName,
                                                category: newItemIsSpice ? .spice : .ingredient)
                            newItemName = ""
                        }
                        .disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            if !model.userAdded.isEmpty {
                Section("You added") {
                    ForEach(model.userAdded) { ingredient in
                        HStack {
                            Text(ingredient.name)
                            Text(ingredient.category == .spice ? "spice" : "ingredient")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(role: .destructive) { model.removeUserAdded(ingredient) } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
            }
            Section {
                if model.hosting {
                    Button("Plan the menu for \(model.guests)") { model.makeMenu() }
                        .disabled(model.confirmedInventory.isEmpty)
                } else {
                    Button("Make my recipes") { model.makeRecipes() }
                        .disabled(model.confirmedInventory.isEmpty)
                }
            }
        }
    }

    private func caption(for photo: CapturedPhoto) -> String {
        if let ts = photo.videoTimestamp {
            return "\(photo.kind.rawValue.capitalized) · frame at \(String(format: "%.1f", ts))s"
        }
        return "\(photo.kind.rawValue.capitalized) · photo"
    }

    private func row(_ ingredient: Ingredient) -> some View {
        HStack {
            Text(ingredient.name)
            if let note = ingredient.quantityNote {
                Text(note).foregroundStyle(.secondary).font(.caption)
            }
            Spacer()
            Button(role: .destructive) { model.removeIngredient(ingredient) } label: {
                Image(systemName: "trash")
            }
        }
    }
}

// MARK: - Shared dish card

private struct DishCard: View {
    @ObservedObject var model: FridgeViewModel
    let recipe: Recipe

    var body: some View {
        Button { model.startCooking(recipe) } label: {
            VStack(alignment: .leading, spacing: 6) {
                DishImageView(data: model.dishImages[recipe.id], title: recipe.title)
                Text(recipe.title).font(.headline).foregroundStyle(.primary)
                Text(recipe.summary).font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Label("\(recipe.minutes) min", systemImage: "clock")
                    Label("serves \(recipe.servings)", systemImage: "person.2")
                    Label(recipe.difficulty.rawValue.capitalized, systemImage: "gauge")
                }
                .font(.caption).foregroundStyle(.secondary)
                if !recipe.shoppingList.isEmpty {
                    Label("Buy: \(recipe.shoppingList.map(\.name).joined(separator: ", ")) (~$\(String(format: "%.2f", recipe.buyCostUSD)))",
                          systemImage: "cart")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// Shows the Muse Image render when bytes exist; in mock mode (and while
/// loading) a labeled placeholder keeps the card honest instead of faking art.
private struct DishImageView: View {
    let data: Data?
    let title: String

    var body: some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable().scaledToFill()
                .frame(height: 140).clipped().cornerRadius(10)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 140)
                Label(title, systemImage: "fork.knife")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Solo recipes

private struct RecipesView: View {
    @ObservedObject var model: FridgeViewModel

    var body: some View {
        List {
            if !model.cookNowRecipes.isEmpty {
                Section("Cook now") {
                    ForEach(model.cookNowRecipes) { recipe in DishCard(model: model, recipe: recipe) }
                }
            }
            if !model.quickBuyRecipes.isEmpty {
                Section("Worth a quick buy") {
                    ForEach(model.quickBuyRecipes) { recipe in DishCard(model: model, recipe: recipe) }
                }
            }
            Section {
                Button("Start over") { model.reset() }
            }
        }
    }
}

// MARK: - Party menu + timeline

private struct MenuView: View {
    @ObservedObject var model: FridgeViewModel
    let plan: MenuPlan

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }

    var body: some View {
        List {
            Section("The menu — \(plan.party.guests) guests, on the table at \(timeFormatter.string(from: plan.party.serveAt))") {
                ForEach(plan.recipes) { recipe in DishCard(model: model, recipe: recipe) }
            }
            if !plan.allBuys.isEmpty {
                Section("The shopping run — est. $\(String(format: "%.2f", plan.totalBuyCostUSD)) of $\(Int(plan.party.budgetUSD)) budget") {
                    ForEach(plan.allBuys, id: \.name) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Text("~$\(String(format: "%.2f", item.estimatedCostUSD))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Prices are typical US grocery estimates, not store quotes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Your timeline — start at \(timeFormatter.string(from: plan.timeline.startCookingAt))") {
                ForEach(plan.timeline.tasks) { task in
                    HStack(alignment: .top, spacing: 10) {
                        Text(timeFormatter.string(from: task.start))
                            .font(.callout.monospacedDigit()).frame(width: 76, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.stepText).font(.callout)
                            Text("\(task.recipeTitle) · \(task.minutes) min\(task.isPassive ? " · hands free" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(plan.timeline.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Section {
                Button("Start over") { model.reset() }
            }
        }
    }
}

// MARK: - Cook mode

private struct CookView: View {
    @ObservedObject var model: FridgeViewModel
    let recipe: Recipe
    @State private var doneSteps: Set<Int> = []
    @State private var boughtItems: Set<String> = []

    var body: some View {
        List {
            if !recipe.shoppingList.isEmpty {
                Section("First, the quick buy") {
                    ForEach(recipe.shoppingList, id: \.name) { item in
                        Button {
                            boughtItems.formSymmetricDifference([item.name])
                        } label: {
                            HStack {
                                Label(item.name, systemImage: boughtItems.contains(item.name)
                                      ? "checkmark.circle.fill" : "circle")
                                Spacer()
                                Text("~$\(String(format: "%.2f", item.estimatedCostUSD))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section("Steps") {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    Button {
                        doneSteps.formSymmetricDifference([index])
                    } label: {
                        HStack(alignment: .top) {
                            Image(systemName: doneSteps.contains(index)
                                  ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.text)
                                    .strikethrough(doneSteps.contains(index))
                                    .foregroundStyle(.primary)
                                Text("\(step.minutes) min · \(step.resource.rawValue)\(step.isPassive ? " · hands free" : "")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section("Uses from your photos") {
                Text(recipe.usedIngredients.joined(separator: ", "))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                Button("Done — back to start") { model.reset() }
            }
        }
        .navigationTitle(recipe.title)
    }
}
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A photo-library sheet that stays open while the user checkmarks items
/// and starts empty every time it opens.
///
/// SwiftUI's PhotosPicker keeps its selection binding across presentations,
/// so a picked video stays checkmarked on the next open. This wrapper owns
/// no selection state: each presentation is a fresh picker, tapping an item
/// only toggles its checkmark, and Add hands back everything selected.
struct LibraryPicker: UIViewControllerRepresentable {
    enum Media {
        case video
        case photo
    }

    enum LibraryAsset {
        /// A private temp copy the caller owns (the picker's URL is only
        /// valid inside its completion handler, so it is copied first).
        case video(URL)
        case photo(Data)
    }

    let media: Media
    let isPresented: Binding<Bool>
    let onPick: ([LibraryAsset]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 0
        config.filter = media == .video ? .videos : .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: isPresented, onPick: onPick)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let isPresented: Binding<Bool>
        let onPick: ([LibraryAsset]) -> Void

        init(isPresented: Binding<Bool>, onPick: @escaping ([LibraryAsset]) -> Void) {
            self.isPresented = isPresented
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            isPresented.wrappedValue = false
            guard !results.isEmpty else { return }
            let group = DispatchGroup()
            var assets: [LibraryAsset] = []
            let lock = NSLock()
            for result in results {
                let provider = result.itemProvider
                if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    group.enter()
                    provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                        defer { group.leave() }
                        guard let url else { return }
                        let copy = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
                            .appendingPathExtension(url.pathExtension)
                        if (try? FileManager.default.copyItem(at: url, to: copy)) != nil {
                            lock.lock()
                            assets.append(.video(copy))
                            lock.unlock()
                        }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    group.enter()
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                        defer { group.leave() }
                        guard let data else { return }
                        lock.lock()
                        assets.append(.photo(data))
                        lock.unlock()
                    }
                }
            }
            group.notify(queue: .main) { self.onPick(assets) }
        }
    }
}
