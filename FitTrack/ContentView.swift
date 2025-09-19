import SwiftUI
import Foundation

// =========================================================
// FITTRACK — Single-file SwiftUI MVP (ContentView.swift)
// =========================================================
// Tabs: Log • History • Habits • Stats
// Local JSON persistence (no backend)
// =========================================================

// MARK: - Models

struct Workout: Identifiable, Codable, Hashable {
    let id: UUID
    var date: Date
    var type: String          // "Workout", "Run", etc.
    var notes: String?
    var durationMinutes: Int?

    init(id: UUID = UUID(), date: Date = .now, type: String,
         notes: String? = nil, durationMinutes: Int? = nil) {
        self.id = id
        self.date = date
        self.type = type
        self.notes = notes
        self.durationMinutes = durationMinutes
    }
}

struct Habit: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var dates: Set<String>    // ISO keys like "yyyy-MM-dd"
    init(id: UUID = UUID(), name: String, dates: Set<String> = []) {
        self.id = id
        self.name = name
        self.dates = dates
    }
}

extension Date {
    var dayKey: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: self)
    }
}

// MARK: - Store (Persistence)

@MainActor
final class AppStore: ObservableObject {
    @Published var workouts: [Workout] = []
    @Published var habits: [Habit] = [
        Habit(name: "Water"),
        Habit(name: "Meditation"),
        Habit(name: "Steps")
    ]

    private let workoutsURL: URL
    private let habitsURL: URL

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        workoutsURL = dir.appendingPathComponent("workouts.json")
        habitsURL   = dir.appendingPathComponent("habits.json")
        Task { await loadAll() }
    }

    func addWorkout(_ w: Workout) {
        withAnimation { workouts.insert(w, at: 0) }
        saveWorkouts()
    }

    func deleteWorkouts(at offsets: IndexSet) {
        workouts.remove(atOffsets: offsets)
        saveWorkouts()
    }

    func toggleHabit(_ id: Habit.ID, on date: Date) {
        guard let i = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = date.dayKey
        if habits[i].dates.contains(key) { habits[i].dates.remove(key) }
        else { habits[i].dates.insert(key) }
        saveHabits()
    }

    // MARK: Persistence helpers

    private func loadAll() async {
        await loadWorkouts()
        await loadHabits()
    }

    private func loadWorkouts() async {
        if let data = try? Data(contentsOf: workoutsURL),
           let decoded = try? JSONDecoder().decode([Workout].self, from: data) {
            workouts = decoded
        }
    }

    private func loadHabits() async {
        if let data = try? Data(contentsOf: habitsURL),
           let decoded = try? JSONDecoder().decode([Habit].self, from: data) {
            habits = decoded
        }
    }

    private func saveWorkouts() {
        do { try JSONEncoder().encode(workouts).write(to: workoutsURL) }
        catch { print("saveWorkouts error:", error) }
    }

    private func saveHabits() {
        do { try JSONEncoder().encode(habits).write(to: habitsURL) }
        catch { print("saveHabits error:", error) }
    }
}

// MARK: - Views

struct RootView: View {
    var body: some View {
        TabView {
            LogView()
                .tabItem { Label("Log", systemImage: "plus.circle") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
            HabitsView()
                .tabItem { Label("Habits", systemImage: "checkmark.circle") }
            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar") }
        }
    }
}

// ---- Log (add a workout)

struct LogView: View {
    @EnvironmentObject var store: AppStore
    @State private var type = "Workout"
    @State private var duration = 30
    @State private var notes = ""
    private let types = ["Workout", "Run", "Walk", "Yoga", "Cycling"]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $type) {
                    ForEach(types, id: \.self, content: Text.init)
                }
                Stepper("Duration: \(duration) min",
                        value: $duration, in: 5...240, step: 5)
                TextField("Notes (optional)", text: $notes)
                Button {
                    store.addWorkout(.init(type: type,
                                           notes: notes.isEmpty ? nil : notes,
                                           durationMinutes: duration))
                    type = "Workout"; duration = 30; notes = ""
                } label: {
                    Label("Save Workout", systemImage: "tray.and.arrow.down")
                }
            }
            .navigationTitle("Quick Log")
        }
    }
}

// ---- History (list + delete)

struct HistoryView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationStack {
            if store.workouts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "figure.strengthtraining.functional")
                        .font(.largeTitle)
                    Text("No workouts yet").font(.headline)
                    Text("Log your first workout in the Log tab.")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .navigationTitle("History")
            } else {
                List {
                    ForEach(store.workouts) { w in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(w.type).font(.headline)
                            Text(w.date.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                            if let d = w.durationMinutes { Text("\(d) min") }
                            if let n = w.notes, !n.isEmpty { Text(n).lineLimit(2) }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: store.deleteWorkouts)
                }
                .navigationTitle("History")
                .toolbar { EditButton() }
            }
        }
    }
}

// ---- Habits (daily check-ins)

struct HabitsView: View {
    @EnvironmentObject var store: AppStore
    private let today = Date()

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.habits) { h in
                    HStack {
                        Text(h.name)
                        Spacer()
                        let done = h.dates.contains(today.dayKey)
                        Button(done ? "Done" : "Mark") {
                            store.toggleHabit(h.id, on: today)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel(done ? "Completed" : "Mark complete")
                    }
                }
            }
            .navigationTitle("Habits")
        }
    }
}

// ---- Stats (simple weekly summary)

struct StatsView: View {
    @EnvironmentObject var store: AppStore

    var weeklyCount: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        return store.workouts.filter { $0.date >= weekAgo }.count
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Last 7 Days").font(.headline)
            Text("\(weeklyCount) workouts").font(.largeTitle.bold())
            Text("Goal: 4+ per week").foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Stats")
    }
}

// MARK: - Previews (optional; shows each screen in canvas)

#Preview { LogView().environmentObject(AppStore()) }
#Preview { HistoryView().environmentObject(AppStore()) }
#Preview { HabitsView().environmentObject(AppStore()) }
#Preview { StatsView().environmentObject(AppStore()) }

// MARK: - App Entry

@main
struct FitTrackApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}
