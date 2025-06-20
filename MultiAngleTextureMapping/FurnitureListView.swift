import SwiftUI

struct FurnitureListView: View {
    var furnitureCandidates: [FurnitureCandidate]

    var body: some View {
        List(furnitureCandidates) { candidate in
            VStack(alignment: .leading) {
                Text("Anchors: \(candidate.anchors.count)")
                Text(String(format: "Bounds: [%.2f, %.2f, %.2f]",
                            candidate.boundingBox.extent.x,
                            candidate.boundingBox.extent.y,
                            candidate.boundingBox.extent.z))
            }
        }
    }
}
