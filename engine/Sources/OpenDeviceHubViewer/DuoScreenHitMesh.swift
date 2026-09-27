import SceneKit
import simd

/// Hit tests the screen skinned on the processor; SceneKit's own hit test uses the authored pose.
struct DuoScreenHitMesh {
    var triangleCount: Int { triangles.count }
    var vertexCount: Int { restPositions.count }
    private let restPositions: [SIMD3<Float>]
    private let textureCoordinates: [SIMD2<Float>]
    private let triangles: [(Int, Int, Int)]
    private let cornerList: [(position: Int, uv: Int)]
    private let boneIndices: [[Int]]
    private let boneWeights: [[Float]]
    private let inverseBind: [simd_float4x4]

    init?(node: SCNNode) {
        guard let geometry = node.geometry,
              let skinner = node.skinner,
              let bind = skinner.boneInverseBindTransforms else { return nil }

        let sources = geometry.sources
        guard let vertexSlot = sources.firstIndex(where: { $0.semantic == .vertex }) else { return nil }
        // A button has no texture coordinates; its uv index aliases the position index, unused.
        let uvSlot = sources.firstIndex(where: { $0.semantic == .texcoord }) ?? vertexSlot

        let vertices = Self.vectors(from: sources[vertexSlot], components: 3).map {
            SIMD3<Float>($0[0], $0[1], $0[2])
        }
        let uvs = uvSlot == vertexSlot
            ? vertices.map { _ in SIMD2<Float>(0, 0) }
            : Self.vectors(from: sources[uvSlot], components: 2).map { SIMD2<Float>($0[0], $0[1]) }
        guard !vertices.isEmpty, !uvs.isEmpty else { return nil }

        let influences = skinner.boneIndices.componentsPerVector
        var indices = Self.integers(from: skinner.boneIndices, components: influences)
        var weights = Self.vectors(from: skinner.boneWeights, components: influences)
        if indices.isEmpty, weights.isEmpty, bind.count == 1 {
            // A panel on one bone has no weights stored; every vertex follows that bone.
            indices = Array(repeating: [0], count: vertices.count)
            weights = Array(repeating: [1], count: vertices.count)
        }
        guard indices.count == vertices.count, weights.count == vertices.count else { return nil }

        // USD layout: a vertex count per polygon, then one index per corner for every source, with
        // positions and texture coordinates indexed independently.
        var corners: [(position: Int, uv: Int)] = []
        var faces: [(Int, Int, Int)] = []
        for element in geometry.elements {
            let read = Self.indexReader(element)
            let polygonCount = element.primitiveCount
            var counts: [Int] = []
            var cursor = 0
            if element.primitiveType == .polygon {
                counts = (0..<polygonCount).map { read($0) }
                cursor = polygonCount
            } else if element.primitiveType == .triangles {
                counts = Array(repeating: 3, count: polygonCount)
            } else {
                continue
            }

            for count in counts {
                guard count >= 3 else { cursor += count * sources.count; continue }
                let first = corners.count
                for corner in 0..<count {
                    let base = cursor + corner * sources.count
                    corners.append((read(base + vertexSlot), read(base + uvSlot)))
                }
                // A fan from the first corner, which is right for this model's convex quads.
                for offset in 1..<(count - 1) {
                    faces.append((first, first + offset, first + offset + 1))
                }
                cursor += count * sources.count
            }
        }
        guard !faces.isEmpty else { return nil }

        restPositions = vertices
        textureCoordinates = uvs
        cornerList = corners
        triangles = faces
        boneIndices = indices
        boneWeights = weights
        inverseBind = bind.map { simd_float4x4($0.scnMatrix4Value) }
    }

    /// The hit as texture coordinates, or nil when the ray misses.
    func hit(from start: SIMD3<Float>, to end: SIMD3<Float>, bones: [SCNNode]) -> SIMD2<Float>? {
        guard !bones.isEmpty else { return nil }
        return hit(from: start, to: end, posed: skinned(bones: bones))
    }

    func hit(from start: SIMD3<Float>, to end: SIMD3<Float>, posed: [SIMD3<Float>]) -> SIMD2<Float>? {
        let direction = end - start
        var best: (distance: Float, uv: SIMD2<Float>)?

        for (a, b, c) in triangles {
            guard a < cornerList.count, b < cornerList.count, c < cornerList.count else { continue }
            let first = cornerList[a], second = cornerList[b], third = cornerList[c]
            guard first.position < posed.count, second.position < posed.count,
                  third.position < posed.count,
                  let hit = Self.intersect(
                      start, direction,
                      posed[first.position], posed[second.position], posed[third.position]
                  ) else { continue }

            if best == nil || hit.distance < best!.distance {
                guard first.uv < textureCoordinates.count, second.uv < textureCoordinates.count,
                      third.uv < textureCoordinates.count else { continue }
                let uv = textureCoordinates[first.uv] * (1 - hit.u - hit.v)
                    + textureCoordinates[second.uv] * hit.u
                    + textureCoordinates[third.uv] * hit.v
                best = (hit.distance, uv)
            }
        }
        return best?.uv
    }

    func posedPositions(bones: [SCNNode]) -> [SIMD3<Float>] {
        skinned(bones: bones)
    }

    private func skinned(bones: [SCNNode]) -> [SIMD3<Float>] {
        let boneTransforms = bones.map { simd_float4x4($0.presentation.worldTransform) }
        return restPositions.indices.map { index in
            var result = SIMD4<Float>.zero
            var total: Float = 0
            let rest = SIMD4<Float>(restPositions[index], 1)
            for influence in boneIndices[index].indices {
                let bone = boneIndices[index][influence]
                let weight = boneWeights[index][influence]
                guard weight > 0, bone < boneTransforms.count, bone < inverseBind.count else { continue }
                result += (boneTransforms[bone] * inverseBind[bone] * rest) * weight
                total += weight
            }
            guard total > 0 else { return restPositions[index] }
            return simd_make_float3(result / total)
        }
    }

    /// Möller and Trumbore, which answers both whether the ray meets the triangle and where on it.
    private static func intersect(
        _ origin: SIMD3<Float>,
        _ direction: SIMD3<Float>,
        _ a: SIMD3<Float>,
        _ b: SIMD3<Float>,
        _ c: SIMD3<Float>
    ) -> (distance: Float, u: Float, v: Float)? {
        let edge1 = b - a
        let edge2 = c - a
        let h = simd_cross(direction, edge2)
        let determinant = simd_dot(edge1, h)
        guard abs(determinant) > 1e-8 else { return nil }
        let inverse = 1 / determinant
        let s = origin - a
        let u = inverse * simd_dot(s, h)
        guard u >= -1e-5, u <= 1 + 1e-5 else { return nil }
        let q = simd_cross(s, edge1)
        let v = inverse * simd_dot(direction, q)
        guard v >= -1e-5, u + v <= 1 + 1e-5 else { return nil }
        let distance = inverse * simd_dot(edge2, q)
        guard distance >= 0, distance <= 1 else { return nil }
        return (distance, u, v)
    }

    private static func vectors(from source: SCNGeometrySource, components: Int) -> [[Float]] {
        let stride = source.dataStride
        let offset = source.dataOffset
        let size = source.bytesPerComponent
        return source.data.withUnsafeBytes { raw -> [[Float]] in
            (0..<source.vectorCount).map { index in
                (0..<components).map { component in
                    let at = index * stride + offset + component * size
                    guard at + size <= raw.count else { return 0 }
                    if size == 4 { return raw.loadUnaligned(fromByteOffset: at, as: Float.self) }
                    return Float(raw.loadUnaligned(fromByteOffset: at, as: Float16.self))
                }
            }
        }
    }

    private static func integers(from source: SCNGeometrySource, components: Int) -> [[Int]] {
        let stride = source.dataStride
        let offset = source.dataOffset
        let size = source.bytesPerComponent
        return source.data.withUnsafeBytes { raw -> [[Int]] in
            (0..<source.vectorCount).map { index in
                (0..<components).map { component in
                    let at = index * stride + offset + component * size
                    guard at + size <= raw.count else { return 0 }
                    switch size {
                    case 1: return Int(raw.loadUnaligned(fromByteOffset: at, as: UInt8.self))
                    case 2: return Int(raw.loadUnaligned(fromByteOffset: at, as: UInt16.self))
                    default: return Int(raw.loadUnaligned(fromByteOffset: at, as: UInt32.self))
                    }
                }
            }
        }
    }

    private static func indexReader(_ element: SCNGeometryElement) -> (Int) -> Int {
        let size = element.bytesPerIndex
        let data = element.data
        return { position in
            data.withUnsafeBytes { raw -> Int in
                let at = position * size
                guard at + size <= raw.count else { return 0 }
                switch size {
                case 1: return Int(raw.loadUnaligned(fromByteOffset: at, as: UInt8.self))
                case 2: return Int(raw.loadUnaligned(fromByteOffset: at, as: UInt16.self))
                default: return Int(raw.loadUnaligned(fromByteOffset: at, as: UInt32.self))
                }
            }
        }
    }
}
