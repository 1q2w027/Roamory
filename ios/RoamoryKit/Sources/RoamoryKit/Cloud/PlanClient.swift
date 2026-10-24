import Foundation

/// Asks the cloud planner for an edit spec. `PlanClient` is the real one; tests use fakes.
public protocol PlanService: Sendable {
    /// - Parameter thumbnails: JPEGs per moment id, sent as `{moment_id}_{k}.jpg` parts.
    func plan(_ request: PlanRequest, thumbnails: [String: [Data]]) async throws -> EditSpec
}

/// Body of every non-2xx backend response (contracts/error.schema.json).
public struct APIError: Codable, Sendable, Equatable {
    public var code: String
    public var message: String
    public var retryable: Bool
}

public enum PlanClientError: Error, Equatable, Sendable {
    case server(status: Int, error: APIError?)
    case timedOut
    case invalidResponse
}

/// `POST /v1/plan` (contracts README): multipart with a `request` JSON part and the thumbnails.
public struct PlanClient: PlanService {
    public var baseURL: URL
    public var appToken: String
    public var timeoutS: Double
    public var session: URLSession

    public init(baseURL: URL, appToken: String, timeoutS: Double, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.appToken = appToken
        self.timeoutS = timeoutS
        self.session = session
    }

    /// Reads `RoamoryAPIBaseURL` and `RoamoryAppToken` from Info.plist (set from build settings, never committed).
    /// Nil when either is missing, and the app plans on the phone.
    public static func fromBundle(_ bundle: Bundle = .main, config: EditConfig) -> PlanClient? {
        guard let base = bundle.object(forInfoDictionaryKey: "RoamoryAPIBaseURL") as? String, let url = URL(string: base),
              let token = bundle.object(forInfoDictionaryKey: "RoamoryAppToken") as? String, !token.isEmpty
        else { return nil }
        return PlanClient(baseURL: url, appToken: token, timeoutS: config.planTimeoutS)
    }

    public func plan(_ request: PlanRequest, thumbnails: [String: [Data]]) async throws -> EditSpec {
        let boundary = "roamory-\(UUID().uuidString)"
        var http = URLRequest(url: baseURL.appending(path: "v1/plan"), timeoutInterval: timeoutS)
        http.httpMethod = "POST"
        http.setValue("Bearer \(appToken)", forHTTPHeaderField: "Authorization")
        http.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let body = try Self.multipartBody(request, thumbnails: thumbnails, boundary: boundary)

        // timeoutInterval only limits idle time; this caps the whole request.
        let (session, sent) = (self.session, http)
        let (data, response) = try await withTimeout(timeoutS) { try await session.upload(for: sent, from: body) }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw PlanClientError.invalidResponse }
        guard status == 200 else {
            throw PlanClientError.server(status: status, error: try? JSONDecoder().decode(APIError.self, from: data))
        }
        return try JSONDecoder().decode(EditSpec.self, from: data)
    }

    static func multipartBody(_ request: PlanRequest, thumbnails: [String: [Data]], boundary: String) throws -> Data {
        var body = MultipartBody(boundary: boundary)
        body.part(name: "request", type: "application/json", data: try JSONEncoder().encode(request))
        for clip in request.clips {
            let images = thumbnails[clip.momentId] ?? []
            for (k, jpeg) in images.prefix(clip.thumbnailCount).enumerated() {
                let name = "\(clip.momentId)_\(k).jpg"
                body.part(name: name, filename: name, type: "image/jpeg", data: jpeg)
            }
        }
        return body.finished()
    }
}

/// A `multipart/form-data` body, shared by the plan and render clients.
struct MultipartBody {
    let boundary: String
    private var data = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func part(name: String, filename: String? = nil, type: String, data part: Data) {
        data.append(Data("--\(boundary)\r\n".utf8))
        let file = filename.map { "; filename=\"\($0)\"" } ?? ""
        data.append(Data("Content-Disposition: form-data; name=\"\(name)\"\(file)\r\n".utf8))
        data.append(Data("Content-Type: \(type)\r\n\r\n".utf8))
        data.append(part)
        data.append(Data("\r\n".utf8))
    }

    func finished() -> Data {
        data + Data("--\(boundary)--\r\n".utf8)
    }
}

/// Runs `operation`, throwing `timeoutError` if it takes longer than `seconds`.
func withTimeout<T: Sendable>(
    _ seconds: Double, error timeoutError: any Error = PlanClientError.timedOut, _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw timeoutError
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}
