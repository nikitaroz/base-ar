import Foundation
import os

/// One HTTP transport for TypeSafe Jev, shared by the Live Survey coach (`.live`) and the Review advisory (`.review`).
///
/// - One ephemeral `URLSession` for the whole app, so the TLS + HTTP/2 connection stays warm between calls.
///   HTTP/2 is negotiated by ALPN and keep-alive is URLSession's default; nothing is cached or written to disk.
/// - Every call has a total time budget, enforced by racing the request against a sleep:
///   `timeoutIntervalForRequest` is only an idle timer.
/// - `.live`: 2.0 s budget on a non-expensive path, 2.5 s on an expensive (cellular or hotspot) or unknown one; no
///   Low Data Mode; one retry only when a reused connection was reset (`networkConnectionLost`) and time remains.
/// - `.review`: 5 s idle timeout, 15 s total; one retry on 408 / 429 / 529 / 5xx or a reset connection, honouring
///   `retry-after-ms` / `Retry-After` up to 3 s.
/// - Never throws: every outcome is a `JevCallResult`. Cancelling the calling task cancels the request.
/// - The key is looked up exactly as the Review client always did (environment, then the Info.plist build setting
///   `$(TYPESAFE_API_KEY)`). No key means no call. Never embed a key; never log it.
final class JevTransport: Sendable {
    enum Profile: String, Sendable {
        case live
        case review
    }

    static let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
    static let modelsEndpoint = URL(string: "https://api.typesafe.ai/v1/models")!
    /// Pinned: every threshold is tuned against this version. `jev-latest` resolved to jev-1.13.0 on 26 Sep 2026.
    /// Re-tune before moving to a new version.
    static let pinnedModel = "jev-1.13.0"

    // MARK: Budgets (tune on device; 0.19–0.32 s round trips were measured from a Mac on 26 Sep 2026, not LTE)

    static let liveBudget: Duration = .milliseconds(2000)
    static let liveBudgetExpensive: Duration = .milliseconds(2500)
    /// A reset connection is retried only when at least this much of the live budget is left.
    static let liveRetryMinimumRemaining: Duration = .milliseconds(1000)
    static let reviewIdleTimeout: TimeInterval = 5
    static let reviewBudget: Duration = .seconds(15)
    static let reviewRetryAfterCap: Duration = .seconds(3)
    /// Review backoff when the reply carries no Retry-After: 0.5 s ± 25 %.
    static let reviewBackoff: Duration = .milliseconds(500)
    static let warmUpBudget: Duration = .seconds(3)

    static let shared = JevTransport()

    static let log = Logger(subsystem: "BaseAR", category: "Jev")

    private let apiKey: String?
    private let session: URLSession
    /// Whether the last call went over an expensive path. Nil until a call finishes.
    private let lastPathExpensive = OSAllocatedUnfairLock<Bool?>(initialState: nil)

    /// One session for every transport instance, so Live and Review share the warm connection.
    private static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        // Upper bounds only. Each call's own budget ends it sooner.
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        return URLSession(configuration: configuration)
    }()

    init(apiKey: String? = JevTransport.configuredKey(), session: URLSession? = nil) {
        self.apiKey = Self.normalizedKey(apiKey)
        self.session = session ?? Self.sharedSession
    }

    var isAvailable: Bool { apiKey != nil }

    /// Environment first (Xcode scheme), then the Info.plist build setting, which `Config/Local.xcconfig` sets.
    static func configuredKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !env.isEmpty {
            return env
        }
        return Bundle.main.object(forInfoDictionaryKey: "TYPESAFE_API_KEY") as? String
    }

    /// An empty value, or an unexpanded "$(TYPESAFE_API_KEY)" (the build setting was never defined), is no key.
    static func normalizedKey(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
    }

    /// The live budget for the next call: the longer one until a finished call shows a non-expensive path.
    var liveBudgetNow: Duration {
        lastPathExpensive.withLock { $0 } == false ? Self.liveBudget : Self.liveBudgetExpensive
    }

    /// Encodes a request body with sorted keys, so the same state always gives the same bytes (cache key, logs).
    static func encodeBody<Body: Encodable>(_ body: Body, snakeCaseKeys: Bool) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if snakeCaseKeys { encoder.keyEncodingStrategy = .convertToSnakeCase }
        return try encoder.encode(body)
    }

    // MARK: - Calls

    /// POSTs an encoded `{model, state, questions}` body to `/v1/systemone`.
    func post(_ body: Data, profile: Profile) async -> JevCallResult {
        guard let apiKey else { return .failure(.noKey) }
        let clock = ContinuousClock()
        let start = clock.now
        let budget = profile == .live ? liveBudgetNow : Self.reviewBudget
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.networkServiceType = .responsiveData
        switch profile {
        case .live:
            // Low Data Mode turns the live lane off; nothing is queued.
            request.allowsConstrainedNetworkAccess = false
            request.timeoutInterval = Self.seconds(budget)
        case .review:
            request.timeoutInterval = Self.reviewIdleTimeout
        }

        var attempts = 0
        while true {
            attempts += 1
            let remaining = budget - (clock.now - start)
            guard remaining > .zero else { return .failure(.timedOut) }
            let outcome = await attempt(request, budget: remaining)
            if Task.isCancelled { return .failure(.cancelled) }
            switch outcome {
            case .response(let raw, let metrics):
                if let metrics { lastPathExpensive.withLock { $0 = metrics.expensive } }
                let roundTrip = clock.now - start
                if (200...299).contains(raw.status) {
                    do {
                        let decoded = try JSONDecoder().decode(JevResponse.self, from: raw.data)
                        let reply = JevReply(
                            model: decoded.model,
                            answers: decoded.answers,
                            usage: decoded.usage,
                            requestID: raw.requestID,
                            status: raw.status,
                            roundTrip: roundTrip,
                            attempts: attempts,
                            network: metrics,
                            requestBytes: body.count
                        )
                        Self.debugLog(profile: profile, reply: reply)
                        return .success(reply)
                    } catch {
                        Self.debugLog(profile: profile, failure: .undecodable(requestID: raw.requestID), attempts: attempts)
                        return .failure(.undecodable(requestID: raw.requestID))
                    }
                }
                let failure = JevCallFailure.http(
                    status: raw.status,
                    retryAfter: raw.retryAfter,
                    requestID: raw.requestID,
                    detail: raw.status == 422 ? Self.validationDetail(raw.data) : nil
                )
                if profile == .review, attempts == 1, Self.reviewRetries(status: raw.status) {
                    let wait = raw.retryAfter ?? Self.jittered(Self.reviewBackoff)
                    if wait <= Self.reviewRetryAfterCap, budget - (clock.now - start) > wait + .seconds(1) {
                        Self.debugLog(profile: profile, failure: failure, attempts: attempts, retrying: true)
                        try? await Task.sleep(for: wait)
                        if Task.isCancelled { return .failure(.cancelled) }
                        continue
                    }
                }
                Self.debugLog(profile: profile, failure: failure, attempts: attempts)
                return .failure(failure)
            case .failed(let failure):
                // A reused HTTP/2 connection that the server or the radio dropped while idle: one fresh try.
                if failure == .connectionLost, attempts == 1 {
                    let left = budget - (clock.now - start)
                    let enough = profile == .live ? left >= Self.liveRetryMinimumRemaining : left > .seconds(1)
                    if enough {
                        Self.debugLog(profile: profile, failure: failure, attempts: attempts, retrying: true)
                        continue
                    }
                }
                Self.debugLog(profile: profile, failure: failure, attempts: attempts)
                return .failure(failure)
            }
        }
    }

    /// Opens the TLS + HTTP/2 connection before the first live call with `GET /v1/models`, which uses no tokens.
    /// Call it once when the Live Survey opens and the lane is on. The result only goes to the DEBUG log.
    func warmUp() async {
        guard let apiKey else { return }
        var request = URLRequest(url: Self.modelsEndpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.allowsConstrainedNetworkAccess = false
        request.networkServiceType = .responsiveData
        let clock = ContinuousClock()
        let start = clock.now
        let outcome = await attempt(request, budget: Self.warmUpBudget)
        #if DEBUG
        let ms = Self.milliseconds(clock.now - start)
        switch outcome {
        case .response(let raw, let metrics):
            if let metrics { lastPathExpensive.withLock { $0 = metrics.expensive } }
            Self.log.debug("warm-up status=\(raw.status) ms=\(ms) \(metrics?.summary ?? "net=-", privacy: .public)")
        case .failed(let failure):
            Self.log.debug("warm-up failed \(String(describing: failure), privacy: .public) ms=\(ms)")
        }
        #else
        if case .response(_, let metrics?) = outcome { lastPathExpensive.withLock { $0 = metrics.expensive } }
        #endif
    }

    // MARK: - One attempt

    private enum AttemptOutcome: Sendable {
        case response(RawResponse, JevNetworkMetrics?)
        case failed(JevCallFailure)
    }

    private struct RawResponse: Sendable {
        let status: Int
        let data: Data
        let requestID: String?
        let retryAfter: Duration?
    }

    private struct BudgetExceeded: Error {}

    private func attempt(_ request: URLRequest, budget: Duration) async -> AttemptOutcome {
        let collector = JevMetricsCollector()
        let session = self.session
        do {
            let raw = try await withThrowingTaskGroup(of: RawResponse.self) { group in
                group.addTask {
                    let (data, response) = try await session.data(for: request, delegate: collector)
                    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                    return RawResponse(
                        status: http.statusCode,
                        data: data,
                        requestID: http.value(forHTTPHeaderField: "x-typesafe-request-id"),
                        retryAfter: Self.retryAfter(http)
                    )
                }
                group.addTask {
                    try await Task.sleep(for: budget)
                    throw BudgetExceeded()
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else { throw CancellationError() }
                return first
            }
            return .response(raw, collector.metrics)
        } catch is BudgetExceeded {
            return .failed(.timedOut)
        } catch is CancellationError {
            return .failed(.cancelled)
        } catch let error as URLError {
            return .failed(Self.failure(for: error))
        } catch {
            return .failed(.connection(code: URLError.Code.unknown.rawValue))
        }
    }

    private static func failure(for error: URLError) -> JevCallFailure {
        if error.networkUnavailableReason == .constrained { return .constrained }
        switch error.code {
        case .cancelled: return .cancelled
        case .timedOut: return .timedOut
        case .networkConnectionLost: return .connectionLost
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .cannotFindHost, .dnsLookupFailed:
            return .offline
        default: return .connection(code: error.code.rawValue)
        }
    }

    private static func reviewRetries(status: Int) -> Bool {
        status == 408 || status == 429 || status == 529 || (500...599).contains(status)
    }

    /// `retry-after-ms` (milliseconds) wins over `Retry-After` (seconds or an HTTP date). Capped at 60 s.
    private static func retryAfter(_ response: HTTPURLResponse) -> Duration? {
        let cap = Duration.seconds(60)
        if let ms = response.value(forHTTPHeaderField: "retry-after-ms").flatMap(Double.init), ms >= 0 {
            return min(.milliseconds(Int64(ms)), cap)
        }
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespaces) else {
            return nil
        }
        if let seconds = Double(value), seconds >= 0 {
            return min(.milliseconds(Int64(seconds * 1000)), cap)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: value) {
            let seconds = max(0, date.timeIntervalSinceNow)
            return min(.milliseconds(Int64(seconds * 1000)), cap)
        }
        return nil
    }

    /// `{"detail":[{"loc":[...],"msg":"..."}]}` → "questions.next_try.criteria: msg". Our own request text only.
    private static func validationDetail(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let details = object["detail"] as? [[String: Any]] else {
            return (object["detail"] as? String).map { String($0.prefix(300)) }
        }
        let parts = details.prefix(4).map { item -> String in
            let loc = (item["loc"] as? [Any])?.map { "\($0)" }.joined(separator: ".") ?? "?"
            let msg = item["msg"] as? String ?? "?"
            return "\(loc): \(msg)"
        }
        return String(parts.joined(separator: "; ").prefix(300))
    }

    static func jittered(_ base: Duration, spread: Double = 0.25) -> Duration {
        base * Double.random(in: (1 - spread)...(1 + spread))
    }

    static func seconds(_ duration: Duration) -> TimeInterval {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1000) + Int(duration.components.attoseconds / 1_000_000_000_000_000)
    }

    // MARK: - DEBUG log (never the key, never the Authorization header)

    private static func debugLog(profile: Profile, reply: JevReply) {
        #if DEBUG
        log.debug("\(profile.rawValue, privacy: .public) \(reply.logLine, privacy: .public)")
        #endif
    }

    private static func debugLog(profile: Profile, failure: JevCallFailure, attempts: Int, retrying: Bool = false) {
        #if DEBUG
        log.debug("\(profile.rawValue, privacy: .public) failed \(String(describing: failure), privacy: .public) attempt=\(attempts)\(retrying ? " retrying" : "", privacy: .public)")
        #endif
    }
}

// MARK: - Results

enum JevCallResult: Sendable {
    case success(JevReply)
    case failure(JevCallFailure)
}

enum JevCallFailure: Error, Sendable, Equatable, CustomStringConvertible {
    case noKey
    case cancelled
    case timedOut
    case offline
    /// Low Data Mode: the live lane never uses a constrained network.
    case constrained
    case connectionLost
    case connection(code: Int)
    case http(status: Int, retryAfter: Duration?, requestID: String?, detail: String?)
    case undecodable(requestID: String?)

    var description: String {
        switch self {
        case .noKey: "no-key"
        case .cancelled: "cancelled"
        case .timedOut: "timed-out"
        case .offline: "offline"
        case .constrained: "low-data-mode"
        case .connectionLost: "connection-lost"
        case .connection(let code): "url-error-\(code)"
        case .http(let status, let retryAfter, let requestID, let detail):
            "http-\(status)" + (retryAfter.map { " retry-after-ms=\(JevTransport.milliseconds($0))" } ?? "")
                + (requestID.map { " request-id=\($0)" } ?? "") + (detail.map { " detail=\($0)" } ?? "")
        case .undecodable(let requestID): "undecodable" + (requestID.map { " request-id=\($0)" } ?? "")
        }
    }

    var httpStatus: Int? {
        if case .http(let status, _, _, _) = self { return status }
        return nil
    }
}

struct JevReply: Sendable {
    /// The versioned model that answered, e.g. "jev-1.13.0".
    let model: String?
    let answers: [String: JevAnswer]
    let usage: JevUsage?
    /// `x-typesafe-request-id`, for TypeSafe support.
    let requestID: String?
    let status: Int
    let roundTrip: Duration
    let attempts: Int
    let network: JevNetworkMetrics?
    let requestBytes: Int

    var logLine: String {
        "status=\(status) ms=\(JevTransport.milliseconds(roundTrip)) attempts=\(attempts) bytes=\(requestBytes) "
            + "model=\(model ?? "-") in=\(usage?.inputTokens.map(String.init) ?? "-") out=\(usage?.outputTokens.map(String.init) ?? "-") "
            + (network?.summary ?? "net=-") + " request-id=\(requestID ?? "-")"
    }
}

/// From `URLSessionTaskMetrics`: whether the warm connection was reused, and over what.
struct JevNetworkMetrics: Sendable, Equatable {
    let protocolName: String?
    let reusedConnection: Bool
    let expensive: Bool
    let constrained: Bool
    let cellular: Bool

    var summary: String {
        "proto=\(protocolName ?? "-") reused=\(reusedConnection) expensive=\(expensive) cellular=\(cellular)"
    }
}

private final class JevMetricsCollector: NSObject, URLSessionTaskDelegate, Sendable {
    private let box = OSAllocatedUnfairLock<JevNetworkMetrics?>(initialState: nil)

    var metrics: JevNetworkMetrics? { box.withLock { $0 } }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let transaction = metrics.transactionMetrics.last else { return }
        let value = JevNetworkMetrics(
            protocolName: transaction.networkProtocolName,
            reusedConnection: transaction.isReusedConnection,
            expensive: transaction.isExpensive,
            constrained: transaction.isConstrained,
            cellular: transaction.isCellular
        )
        box.withLock { $0 = value }
    }
}

// MARK: - Response body

/// `{model, answers, usage}` from `/v1/systemone`.
struct JevResponse: Decodable, Sendable {
    let model: String?
    let answers: [String: JevAnswer]
    let usage: JevUsage?
}

struct JevUsage: Decodable, Sendable, Equatable {
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

/// One answer. The live API (jev-1.13.0, checked 26 Sep 2026) returns `noul` as the probability of "yes"
/// (e.g. 0.12), `score` as a fractional scale value with a `legend`, and `choice` with `confidence` and
/// `probabilities`. Older docs showed `noul` as a string and `score` as an integer, so both decode.
struct JevAnswer: Decodable, Sendable, Equatable {
    let type: String?
    let noul: Double?
    let choice: String?
    let score: Double?
    let confidence: Double?
    let probabilities: [String: Double]?
    let legend: [String: String]?

    init(
        type: String? = nil,
        noul: Double? = nil,
        choice: String? = nil,
        score: Double? = nil,
        confidence: Double? = nil,
        probabilities: [String: Double]? = nil,
        legend: [String: String]? = nil
    ) {
        self.type = type
        self.noul = noul
        self.choice = choice
        self.score = score
        self.confidence = confidence
        self.probabilities = probabilities
        self.legend = legend
    }

    enum CodingKeys: String, CodingKey { case type, noul, choice, score, confidence, probabilities, legend }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try? container.decode(String.self, forKey: .type)
        if let probability = try? container.decode(Double.self, forKey: .noul) {
            noul = probability
        } else if let word = try? container.decode(String.self, forKey: .noul) {
            noul = word.lowercased() == "yes" ? 1 : (word.lowercased() == "no" ? 0 : nil)
        } else {
            noul = nil
        }
        choice = try? container.decode(String.self, forKey: .choice)
        score = try? container.decode(Double.self, forKey: .score)
        confidence = try? container.decode(Double.self, forKey: .confidence)
        probabilities = try? container.decode([String: Double].self, forKey: .probabilities)
        legend = try? container.decode([String: String].self, forKey: .legend)
    }
}
