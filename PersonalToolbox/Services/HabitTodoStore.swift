import Foundation

struct HabitItem: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var createdAt: Date
    /// yyyy-MM-dd keys completed
    var completedDays: [String]

    var streak: Int {
        var s = 0
        var day = Calendar.current.startOfDay(for: Date())
        let f = Self.dayFormatter
        for _ in 0..<365 {
            let key = f.string(from: day)
            if completedDays.contains(key) {
                s += 1
                day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
            } else {
                // allow today incomplete without breaking past streak if checking mid-day? require continuous from today or yesterday
                if s == 0, key == f.string(from: Date()) {
                    day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
                    continue
                }
                break
            }
        }
        return s
    }

    func isDone(on date: Date = Date()) -> Bool {
        completedDays.contains(Self.dayFormatter.string(from: date))
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

struct TodoItem: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var isDone: Bool
    var createdAt: Date
    var dueDate: Date?
}

private struct HabitTodoPayload: Codable {
    var habits: [HabitItem]
    var todos: [TodoItem]
}

@MainActor
final class HabitTodoStore: ObservableObject {
    static let shared = HabitTodoStore()
    private let fileName = "habits_todos.json"

    @Published private(set) var habits: [HabitItem] = []
    @Published private(set) var todos: [TodoItem] = []

    private init() {
        let data = LocalJSONStore.load(HabitTodoPayload.self, from: fileName, fallback: .init(habits: [], todos: []))
        habits = data.habits
        todos = data.todos
    }

    private func persist() {
        LocalJSONStore.save(HabitTodoPayload(habits: habits, todos: todos), to: fileName)
    }

    // MARK: Habits

    func addHabit(title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        habits.insert(HabitItem(id: UUID().uuidString, title: t, createdAt: Date(), completedDays: []), at: 0)
        persist()
    }

    func toggleHabitToday(_ id: String) {
        guard let i = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = HabitItem.dayFormatter.string(from: Date())
        if let idx = habits[i].completedDays.firstIndex(of: key) {
            habits[i].completedDays.remove(at: idx)
        } else {
            habits[i].completedDays.append(key)
        }
        persist()
    }

    func deleteHabit(_ id: String) {
        habits.removeAll { $0.id == id }
        persist()
    }

    // MARK: Todos

    func addTodo(title: String, due: Date? = nil) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        todos.insert(TodoItem(id: UUID().uuidString, title: t, isDone: false, createdAt: Date(), dueDate: due), at: 0)
        persist()
    }

    func toggleTodo(_ id: String) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].isDone.toggle()
        persist()
    }

    func deleteTodo(_ id: String) {
        todos.removeAll { $0.id == id }
        persist()
    }

    var openTodos: [TodoItem] { todos.filter { !$0.isDone } }
    var doneTodos: [TodoItem] { todos.filter(\.isDone) }
}
