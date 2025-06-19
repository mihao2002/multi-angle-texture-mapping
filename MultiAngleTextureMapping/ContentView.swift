import SwiftUI
import ARKit
import SceneKit

struct ContentView: View {
    @State private var captureRequested = false

    var body: some View {
        ZStack {
            ARViewContainer(captureRequested: $captureRequested)
                .edgesIgnoringSafeArea(.all)
            VStack {
                Spacer()
                Button("Capture") {
                    captureRequested = true
                }
                .padding()
                .background(Color.white.opacity(0.8))
                .cornerRadius(12)
                .padding()
            }
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    @Binding var captureRequested: Bool

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView()
        let config = ARWorldTrackingConfiguration()

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }

        config.environmentTexturing = .automatic
        sceneView.session.run(config)
        sceneView.delegate = context.coordinator
        sceneView.scene = SCNScene()
        context.coordinator.sceneView = sceneView
        context.coordinator.captureRequestedBinding = $captureRequested
        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        if captureRequested {
            context.coordinator.captureImage()
            captureRequested = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, ARSCNViewDelegate {
        var sceneView: ARSCNView?
        var captureRequestedBinding: Binding<Bool>?
        var imageSamples: [(UIImage, simd_float4x4)] = []

        func captureImage() {
            guard let sceneView = sceneView,
                  let currentFrame = sceneView.session.currentFrame,
                  imageSamples.count < 5 else { return }

            let pixelBuffer = currentFrame.capturedImage
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                let image = UIImage(cgImage: cgImage)
                let transform = currentFrame.camera.transform
                imageSamples.append((image, transform))
                print("Captured image sample \(imageSamples.count)")
            }
        }

        func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            guard let meshAnchor = anchor as? ARMeshAnchor else { return }

            let geometry = meshAnchor.geometry

            var vertexArray: [SCNVector3] = []
            var colorArray: [SCNVector3] = []

            for i in 0..<geometry.vertices.count {
                let vertex = geometry.vertices.vertex(at: i)
                let worldPos4 = meshAnchor.transform * simd_float4(vertex, 1)
                let worldPos = simd_float3(worldPos4.x, worldPos4.y, worldPos4.z)
                let blendedColor = blendColor(for: worldPos)
                colorArray.append(blendedColor)
                vertexArray.append(SCNVector3(vertex.x, vertex.y, vertex.z))
            }

            var indices: [Int32] = []
            for i in 0..<geometry.faces.count {
                let face = geometry.faces.triangleIndices(at: i)
                indices.append(Int32(face.0))
                indices.append(Int32(face.1))
                indices.append(Int32(face.2))
            }

            let vertexSource = SCNGeometrySource(vertices: vertexArray)
            let colorData = colorArray.flatMap { [$0.x, $0.y, $0.z, 1.0] }
            let colorSource = SCNGeometrySource(data: Data(bytes: colorData, count: colorData.count * MemoryLayout<Float>.size),
                                                semantic: .color,
                                                vectorCount: colorArray.count,
                                                usesFloatComponents: true,
                                                componentsPerVector: 4,
                                                bytesPerComponent: MemoryLayout<Float>.size,
                                                dataOffset: 0,
                                                dataStride: MemoryLayout<Float>.size * 4)

            let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
            let element = SCNGeometryElement(data: indexData,
                                             primitiveType: .triangles,
                                             primitiveCount: indices.count / 3,
                                             bytesPerIndex: MemoryLayout<Int32>.size)

            let meshGeometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
            meshGeometry.firstMaterial?.isDoubleSided = true
            meshGeometry.firstMaterial?.lightingModel = .blinn

            node.geometry = meshGeometry
        }

        func blendColor(for worldPos: simd_float3) -> SCNVector3 {
            var totalColor = simd_float3(0, 0, 0)
            var count: Float = 0

            for (image, cameraTransform) in imageSamples {
                let projected = project(worldPosition: worldPos, cameraTransform: cameraTransform)
                let sample = sampleColor(at: projected, from: image)
                totalColor += sample
                count += 1
            }

            if count == 0 { return SCNVector3(0.6, 0.6, 1.0) }
            let avg = totalColor / count
            return SCNVector3(avg.x, avg.y, avg.z)
        }

        func project(worldPosition: simd_float3, cameraTransform: simd_float4x4) -> CGPoint {
            let scenePoint = SCNVector3(worldPosition.x, worldPosition.y, worldPosition.z)
            guard let projected = sceneView?.projectPoint(scenePoint) else {
                return .zero
            }
            return CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
        }

        func sampleColor(at point: CGPoint, from image: UIImage) -> simd_float3 {
            guard let cgImage = image.cgImage else { return simd_float3(0.6, 0.6, 1.0) }

            let width = image.size.width
            let height = image.size.height

            let x = Int(point.x / UIScreen.main.bounds.width * width)
            let y = Int((1.0 - point.y / UIScreen.main.bounds.height) * height)

            guard x >= 0, x < Int(width), y >= 0, y < Int(height),
                  let data = cgImage.dataProvider?.data,
                  let ptr = CFDataGetBytePtr(data) else {
                return simd_float3(0.6, 0.6, 1.0)
            }

            let bytesPerPixel = 4
            let offset = (y * cgImage.bytesPerRow) + (x * bytesPerPixel)
            let r = Float(ptr[offset]) / 255.0
            let g = Float(ptr[offset + 1]) / 255.0
            let b = Float(ptr[offset + 2]) / 255.0

            return simd_float3(r, g, b)
        }
    }
}

// MARK: - Mesh Access Extensions

extension ARGeometrySource {
    func vertex(at index: Int) -> simd_float3 {
        let stride = self.stride
        let offset = self.offset
        let pointer = self.buffer.contents().advanced(by: offset + index * stride)
        let floatPtr = pointer.bindMemory(to: Float.self, capacity: 3)
        return simd_float3(floatPtr[0], floatPtr[1], floatPtr[2])
    }
}

extension ARGeometryElement {
    func triangleIndices(at triangleIndex: Int) -> (UInt32, UInt32, UInt32) {
        let pointer = self.buffer.contents().advanced(by: triangleIndex * self.bytesPerIndex * 3)
        let indices = pointer.bindMemory(to: UInt32.self, capacity: 3)
        return (indices[0], indices[1], indices[2])
    }
}
