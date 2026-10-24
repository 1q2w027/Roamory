import Foundation

/// Anything that can answer an evaluate request; `EvaluateClient` in the app, a fake in tests.
public protocol Evaluating: Sendable {
    func evaluate(context: EvaluateContext, frames: [Data]) async throws -> Evaluation
}

public enum EvaluateError: Error, Equatable, Sendable {
    /// Non-2xx with the contracts error shape; `code` is "unknown" when the body isn't that shape.
    case server(status: Int, code: String, retryable: Bool)
    case timeout
    case network
    /// A 2xx body that did not decode, twice.
    case invalidResponse
}

/// Client for `POST /v1/evaluate` (contracts/README.md). Callers fall back locally on any thrown error.
public struct EvaluateClient: Evaluating {
    let baseURL: URL
    let token: String
    let timeoutS: Double
    let session: URLSession

    public init(baseURL: URL, token: String, timeoutS: Double, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.timeoutS = timeoutS
        self.session = session
    }

    private struct ErrorBody: Decodable {
        var code: String
        var retryable: Bool
    }

    public func evaluate(context: EvaluateContext, frames: [Data]) async throws -> Evaluation {
        let request = try makeRequest(context: context, frames: frames)
        // One retry on an undecodable 2xx body (TRD 8.2); every other failure throws at once.
        for attempt in 1...2 {
            let (data, response) = try await send(request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
                throw EvaluateError.server(status: status, code: body?.code ?? "unknown", retryable: body?.retryable ?? (status >= 500))
            }
            if let evaluation = try? JSONDecoder().decode(Evaluation.self, from: data) { return evaluation }
            if attempt == 2 { break }
        }
        throw EvaluateError.invalidResponse
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw EvaluateError.timeout
        } catch {
            throw EvaluateError.network
        }
    }

    func makeRequest(context: EvaluateContext, frames: [Data]) throws -> URLRequest {
        let boundary = "roamory-\(UUID().uuidString)"
        var body = Data()
        func part(name: String, filename: String?, type: String, data: Data) {
            body.append(Data("--\(boundary)\r\n".utf8))
            let file = filename.map { "; filename=\"\($0)\"" } ?? ""
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\(file)\r\n".utf8))
            body.append(Data("Content-Type: \(type)\r\n\r\n".utf8))
            body.append(data)
            body.append(Data("\r\n".utf8))
        }
        part(name: "context", filename: nil, type: "application/json", data: try JSONEncoder().encode(context))
        for (k, frame) in frames.enumerated() {
            part(name: "frame_\(k).jpg", filename: "frame_\(k).jpg", type: "image/jpeg", data: frame)
        }
        body.append(Data("--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: baseURL.appending(path: "v1/evaluate"), timeoutInterval: timeoutS)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }
}
