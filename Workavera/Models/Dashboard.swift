import Foundation

struct DashboardSummary: Equatable {
    let activeProjects: Int
    let openTasks: Int
    let nextSevenDays: Int
    let unreadReading: Int
    let loadedAt: Date
}
