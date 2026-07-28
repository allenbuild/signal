import Foundation

enum TrackingMath {
    static let epsilon = 1e-12

    static func add(_ lhs: Point2D, _ rhs: Point2D) -> Point2D {
        Point2D(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func subtract(_ lhs: Point2D, _ rhs: Point2D) -> Point2D {
        Point2D(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func multiply(_ point: Point2D, by scalar: Double) -> Point2D {
        Point2D(x: point.x * scalar, y: point.y * scalar)
    }

    static func divide(_ point: Point2D, by scalar: Double) -> Point2D {
        guard scalar.isFinite, abs(scalar) > epsilon else {
            return Point2D(x: 0, y: 0)
        }
        return Point2D(x: point.x / scalar, y: point.y / scalar)
    }

    static func magnitude(_ point: Point2D) -> Double {
        hypot(point.x, point.y)
    }

    static func distance(_ lhs: Point2D, _ rhs: Point2D) -> Double {
        magnitude(subtract(lhs, rhs))
    }

    static func clampMagnitude(_ point: Point2D, maximum: Double) -> Point2D {
        let length = magnitude(point)
        guard length.isFinite, maximum.isFinite, maximum >= 0, length > maximum, length > epsilon else {
            return point
        }
        return multiply(point, by: maximum / length)
    }

    static func blend(_ old: Point2D, _ new: Point2D, newWeight: Double) -> Point2D {
        let weight = min(max(newWeight, 0), 1)
        return Point2D(
            x: old.x * (1 - weight) + new.x * weight,
            y: old.y * (1 - weight) + new.y * weight
        )
    }

    static func isFinite(_ point: Point2D) -> Bool {
        point.x.isFinite && point.y.isFinite
    }
}
