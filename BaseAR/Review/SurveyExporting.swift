import Foundation
import simd

/// Rules/review export boundary. Writes the local survey packet. No network.
protocol SurveyExporting: Sendable {
    func write(_ session: SurveySession, to directory: URL) throws -> URL
}

/// One LiDAR mesh anchor, in AR world meters, ready to merge into a PLY.
struct MeshPointCloudChunk: Sendable {
    var positions: [SIMD3<Float>]
    var colors: [SIMD3<UInt8>]
    var triangles: [UInt32]
}

/// ASCII PLY of the reconstructed mesh. Vertices are the point cloud; triangles keep the surface.
enum PointCloudPLY {
    static func data(from chunks: [MeshPointCloudChunk], comments: [String] = []) -> Data? {
        var vertexCount = 0
        var faceCount = 0
        for chunk in chunks {
            guard chunk.colors.count == chunk.positions.count, chunk.triangles.count.isMultiple(of: 3) else { continue }
            vertexCount += chunk.positions.count
            faceCount += chunk.triangles.count / 3
        }
        guard vertexCount > 0 else { return nil }

        let locale = Locale(identifier: "en_US_POSIX")
        let extraComments = comments.map { "comment \($0)\n" }.joined()
        var text = """
        ply
        format ascii 1.0
        comment Base Site Survey LiDAR mesh
        comment units meters
        comment frame ARKit world
        comment colors: camera RGB, light gray where the camera never saw the surface
        \(extraComments)element vertex \(vertexCount)
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        element face \(faceCount)
        property list uchar int vertex_indices
        end_header

        """
        text.reserveCapacity(text.count + vertexCount * 36 + faceCount * 24)
        // PLY requires every vertex before any face, so write all chunks' vertices, then all faces.
        let chunks = chunks.filter { $0.colors.count == $0.positions.count && $0.triangles.count.isMultiple(of: 3) }
        for chunk in chunks {
            for index in chunk.positions.indices {
                let point = chunk.positions[index]
                let color = chunk.colors[index]
                text += String(
                    format: "%.5f %.5f %.5f %d %d %d\n",
                    locale: locale,
                    point.x, point.y, point.z,
                    Int(color.x), Int(color.y), Int(color.z)
                )
            }
        }
        var offset = 0
        for chunk in chunks {
            var face = 0
            while face < chunk.triangles.count {
                let a = Int(chunk.triangles[face]) + offset
                let b = Int(chunk.triangles[face + 1]) + offset
                let c = Int(chunk.triangles[face + 2]) + offset
                text += "3 \(a) \(b) \(c)\n"
                face += 3
            }
            offset += chunk.positions.count
        }
        return Data(text.utf8)
    }
}

struct JSONSurveyExporter: SurveyExporting {
    func write(_ session: SurveySession, to directory: URL) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        let url = directory.appendingPathComponent("survey.json")
        try data.write(to: url, options: .atomic)
        return url
    }
}
