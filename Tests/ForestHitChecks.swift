import SwiftUI
import FocusCore

private func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw FocusError(message) }
}

@main struct ForestHitChecks {
    static func main() throws {
        // In a five-record forest the first pit is at (430,149), with a
        // small tree in front at (430,263). Its old 170x190 rectangle
        // incorrectly covered the pit although no tree pixels were there.
        for unit in [1.0, 0.64] {
            let treeRect = CGRect(x: 345 * unit, y: 85 * unit, width: 170 * unit, height: 190 * unit)
            let treeHit = ForestPlantHitShape(kind: .sapling).path(in: treeRect)
            for (dx, dy) in [(0.0,0.0),(-6,0),(6,0),(0,-2),(0,2)] {
                try check(!treeHit.contains(CGPoint(x:(430+dx)*unit,y:(149+dy)*unit)), "A visible early pit must not be covered by the small tree's transparent padding")
            }
            let pitHit = ForestPlantHitShape(kind: .pit).path(in: CGRect(x:390*unit,y:129*unit,width:80*unit,height:40*unit))
            try check(pitHit.contains(CGPoint(x:430*unit,y:149*unit)), "The pit itself must accept a click at its center")
            try check(treeHit.contains(CGPoint(x:430*unit,y:220*unit)), "The small tree's visible crown must remain clickable")
        }
        for kind in [ForestPlantKind.sapling, .tree, .mediumTree, .largeTree] {
            let hit = ForestPlantHitShape(kind:kind).path(in:CGRect(x:0,y:0,width:170,height:190))
            try check(hit.contains(CGPoint(x:85,y:178-85*kind.scale)), "Every tree size must accept a click in its crown")
            try check(hit.contains(CGPoint(x:85,y:178-20*kind.scale)), "Every tree size must accept a click on its trunk")
            try check(!hit.contains(CGPoint(x:5,y:5)), "Invisible canvas padding must pass clicks through")
        }
        print("PASS: visible pit receives clicks through foreground sapling padding; all tree crowns and trunks remain clickable")
    }
}
