import Foundation
import ARKit

class Coordinator: NSObject, ARSCNViewDelegate, ObservableObject {
    @Published var furnitureCandidates: [FurnitureCandidate] = []
    var sceneView: ARSCNView?

    private var groupedCandidates: [FurnitureCandidate] = []

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let meshAnchor = anchor as? ARMeshAnchor else { return }
        addMeshAnchor(meshAnchor)
    }
    
    var wireframeNodes: [UUID: SCNNode] = [:]  // Dictionary to track them by candidate ID

    func addMeshAnchor(_ anchor: ARMeshAnchor) {
        // 1. Compute bounding box of the incoming mesh anchor
        let newBox = BoundingBox.from(anchor: anchor)

        // 2. Track which existing candidates intersect with this new one
        var overlappingCandidates: [FurnitureCandidate] = []
        var remainingCandidates: [FurnitureCandidate] = []

        for candidate in furnitureCandidates {
            if candidate.boundingBox.intersects(with: newBox) {
                overlappingCandidates.append(candidate)
            } else {
                remainingCandidates.append(candidate)
            }
        }

        // 3. Merge all intersecting bounding boxes (including the new one)
        let allBoxes = overlappingCandidates.map { $0.boundingBox } + [newBox]
        let mergedBox = mergeBoundingBoxes(boxes: allBoxes)
        
        // 4. Collect all anchors involved
        let allAnchors = overlappingCandidates.flatMap { $0.anchors } + [anchor]

        let mergedCandidate = FurnitureCandidate(anchors: allAnchors, boundingBox: mergedBox)

        // 4. Replace candidates: keep non-overlapping + the merged one
        DispatchQueue.main.async {
            self.furnitureCandidates = remainingCandidates + [mergedCandidate]
        }

        // Optional: For visual debugging
        addBoundingBoxWireframe(for: mergedCandidate.boundingBox, id: mergedCandidate.id)
        
        let idsToRemove = overlappingCandidates.map { $0.id }
        removeBoundingBoxWireframes(for: idsToRemove)
    }
    
    func mergeBoundingBoxes(boxes: [BoundingBox]) -> BoundingBox {
        guard let first = boxes.first else {
            return BoundingBox(min: .zero, max: .zero)
        }

        // Start with the min and max of the first box
        var minPoint = first.min
        var maxPoint = first.max

        // Expand min/max to include all other boxes
        for box in boxes.dropFirst() {
            minPoint = simd_min(minPoint, box.min)
            maxPoint = simd_max(maxPoint, box.max)
        }

        // Build a new bounding box from the final min/max
        return BoundingBox(min: minPoint, max: maxPoint)
    }



    func merge(_ a: BoundingBox, _ b: BoundingBox) -> BoundingBox {
        BoundingBox(min: simd_min(a.min, b.min), max: simd_max(a.max, b.max))
    }

    func publishCandidates() {
        DispatchQueue.main.async {
            self.furnitureCandidates = self.groupedCandidates
        }
    }
    
    func removeBoundingBoxWireframes(for candidateIDs: [UUID]) {
        for id in candidateIDs {
            if let node = wireframeNodes[id] {
                node.removeFromParentNode()
                wireframeNodes.removeValue(forKey: id)
            }
        }
    }

    
    func addBoundingBoxWireframe(for box: BoundingBox, id: UUID) {
        guard let sceneView = sceneView else { return }

        let size = box.extent
        let center = box.center

        guard size.x > 0, size.y > 0, size.z > 0 else {
            print("Invalid bounding box size: \(size)")
            return
        }

        // Create a box geometry without material (invisible fill)
        let boxGeometry = SCNBox(width: CGFloat(size.x),
                                 height: CGFloat(size.y),
                                 length: CGFloat(size.z),
                                 chamferRadius: 0)

        // Create a node with the box geometry
        let boxNode = SCNNode(geometry: boxGeometry)
        boxNode.position = SCNVector3(center.x, center.y, center.z)

        // Create a wireframe by showing only edges
        let wireframeNode = SCNNode()

        // Define 12 edges as lines
        let edges: [(SCNVector3, SCNVector3)] = [
            // Bottom square
            (SCNVector3(-size.x/2, -size.y/2, -size.z/2), SCNVector3(size.x/2, -size.y/2, -size.z/2)),
            (SCNVector3(size.x/2, -size.y/2, -size.z/2), SCNVector3(size.x/2, -size.y/2, size.z/2)),
            (SCNVector3(size.x/2, -size.y/2, size.z/2), SCNVector3(-size.x/2, -size.y/2, size.z/2)),
            (SCNVector3(-size.x/2, -size.y/2, size.z/2), SCNVector3(-size.x/2, -size.y/2, -size.z/2)),

            // Top square
            (SCNVector3(-size.x/2, size.y/2, -size.z/2), SCNVector3(size.x/2, size.y/2, -size.z/2)),
            (SCNVector3(size.x/2, size.y/2, -size.z/2), SCNVector3(size.x/2, size.y/2, size.z/2)),
            (SCNVector3(size.x/2, size.y/2, size.z/2), SCNVector3(-size.x/2, size.y/2, size.z/2)),
            (SCNVector3(-size.x/2, size.y/2, size.z/2), SCNVector3(-size.x/2, size.y/2, -size.z/2)),

            // Vertical edges
            (SCNVector3(-size.x/2, -size.y/2, -size.z/2), SCNVector3(-size.x/2, size.y/2, -size.z/2)),
            (SCNVector3(size.x/2, -size.y/2, -size.z/2), SCNVector3(size.x/2, size.y/2, -size.z/2)),
            (SCNVector3(size.x/2, -size.y/2, size.z/2), SCNVector3(size.x/2, size.y/2, size.z/2)),
            (SCNVector3(-size.x/2, -size.y/2, size.z/2), SCNVector3(-size.x/2, size.y/2, size.z/2)),
        ]

        for (start, end) in edges {
            let line = lineNode(from: start, to: end)
            wireframeNode.addChildNode(line)
        }

        wireframeNode.position = SCNVector3(center.x, center.y, center.z)

        sceneView.scene.rootNode.addChildNode(wireframeNode)
        print("Added wireframe bounding box at \(center) size \(size)")
        wireframeNodes[id] = wireframeNode
    }

    // Helper to create a line node between two points
    func lineNode(from: SCNVector3, to: SCNVector3) -> SCNNode {
        let vertices: [SCNVector3] = [from, to]
        let source = SCNGeometrySource(vertices: vertices)
        let indices: [UInt8] = [0, 1]
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.firstMaterial?.diffuse.contents = UIColor.white
        return SCNNode(geometry: geometry)
    }
}

struct FurnitureCandidate: Identifiable {
    let id = UUID()
    var anchors: [ARMeshAnchor]
    var boundingBox: BoundingBox
}
