import SwiftUI
import ARKit
import SceneKit

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var coordinator: Coordinator

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView()
        sceneView.delegate = coordinator
        sceneView.session.run({
            let config = ARWorldTrackingConfiguration()
            config.sceneReconstruction = .mesh
            config.environmentTexturing = .automatic
            return config
        }())
        sceneView.scene = SCNScene()
        coordinator.sceneView = sceneView
        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        coordinator
    }
}
