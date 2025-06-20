import ARKit

struct BoundingBox {
    var min: simd_float3
    var max: simd_float3

    var center: simd_float3 {
        (min + max) * 0.5
    }

    var extent: simd_float3 {
        max - min
    }

    func intersects(with other: BoundingBox, threshold: Float = 0.3) -> Bool {
        return abs(center.x - other.center.x) < (extent.x + other.extent.x) * 0.5 + threshold &&
               abs(center.y - other.center.y) < (extent.y + other.extent.y) * 0.5 + threshold &&
               abs(center.z - other.center.z) < (extent.z + other.extent.z) * 0.5 + threshold
    }

    static func from(anchor: ARMeshAnchor) -> BoundingBox {
        let geometry = anchor.geometry
        let transform = anchor.transform

        var min = simd_float3(Float.greatestFiniteMagnitude)
        var max = simd_float3(-Float.greatestFiniteMagnitude)

        let vertices = geometry.vertices
        for i in 0..<vertices.count {
            let vertex = vertices.vertex(at: i)
            let world = simd_make_float3(transform * simd_float4(vertex, 1))
            min = simd_min(min, world)
            max = simd_max(max, world)
        }

        return BoundingBox(min: min, max: max)
    }
}

extension ARGeometrySource {
    func vertex(at index: Int) -> simd_float3 {
        let stride = self.formatStride ?? 12
        let offset = self.formatOffset ?? 0
        let start = self.buffer.contents().advanced(by: self.offset + index * stride + offset)

        var result = simd_float3()
        memcpy(&result, start, MemoryLayout<simd_float3>.size)
        return result
    }

    var formatStride: Int? {
        switch self.format {
        case .float3: return 12
        default: return nil
        }
    }

    var formatOffset: Int? {
        return 0
    }
}



