import Foundation

enum QuickStartType: Int {
    case undefined
    case newUser
    case existingUser
}

class QuickStartFactory {
    static func collections(for blog: Blog) -> [QuickStartToursCollection] {
        switch blog.quickStartType {
        case .undefined:
            guard let completedTours = blog.completedQuickStartTours, completedTours.count > 0 else {
                return []
            }
            fallthrough
        case .newUser:
            return [QuickStartCustomizeToursCollection(blog: blog), QuickStartGrowToursCollection(blog: blog)]
        case .existingUser:
            return [QuickStartGetToKnowAppCollection(blog: blog)]
        }
    }

    static func allTours(for blog: Blog) -> [QuickStartTour] {
        collections(for: blog).flatMap({$0.tours} )
    }
}
