import Foundation

/// OpenJEV advisory client for optional eligibility guidance.
/// This is strictly advisory and does NOT override measured rule-based checks.
struct OpenJEVClient: Sendable {
    var apiKey: String?
    var baseURL: String
    
    static let defaultBaseURL = "https://api.openjev.sh/v1/systemone"
    
    init(apiKey: String? = nil, baseURL: String = defaultBaseURL) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }
    
    /// Query OpenJEV with survey state and rule results
    func queryAdvisory(session: SurveySession) async throws -> OpenJEVAdvisoryResponse {
        guard let apiKey, !apiKey.isEmpty else {
            throw OpenJEVError.noAPIKey
        }
        
        let request = OpenJEVRequest(
            model: "openjev",
            state: AdvisoryState(session: session),
            questions: [
                AdvisoryQuestion(
                    key: "visit_ready",
                    type: "noul",
                    prompt: "Is the survey ready for a Base engineer visit?"
                ),
                AdvisoryQuestion(
                    key: "next_action",
                    type: "choice",
                    prompt: "What should the next action be?",
                    choices: ["proceed", "need_more_photos", "conflict"]
                ),
                AdvisoryQuestion(
                    key: "blocking_gap",
                    type: "choice",
                    prompt: "Which missing evidence matters most?",
                    choices: ["footprint", "transfer_switch", "ocr", "photos", "form", "none"]
                )
            ]
        )
        
        guard let url = URL(string: baseURL) else {
            throw OpenJEVError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 15
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(request)
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenJEVError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw OpenJEVError.unauthorized
            }
            throw OpenJEVError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OpenJEVAdvisoryResponse.self, from: data)
    }
}

enum OpenJEVError: LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case unauthorized
    case httpError(statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "OpenJEV API key not configured"
        case .invalidURL:
            return "Invalid OpenJEV API URL"
        case .invalidResponse:
            return "Invalid response from OpenJEV"
        case .unauthorized:
            return "OpenJEV API key is invalid or unauthorized"
        case .httpError(let statusCode):
            return "OpenJEV API error: HTTP \(statusCode)"
        }
    }
}

// MARK: - Request Models

struct OpenJEVRequest: Encodable {
    let model: String
    let state: AdvisoryState
    let questions: [AdvisoryQuestion]
}

struct AdvisoryState: Encodable {
    let propertyIdentifier: String
    let homeownership: String?
    let hasSolar: Bool?
    let hasStandbyGenerator: Bool?
    let hasExistingWholeHomeBattery: Bool?
    let plannedBatteryCount: Int?
    let mainBreakerAmperage: Int?
    let meterNumber: String?
    let batteryPlaced: Bool
    let meterMarked: Bool
    let gasMeterMarked: Bool
    let lidarMeshAvailable: Bool
    let ruleResults: [AdvisoryRuleResult]
    
    init(session: SurveySession) {
        self.propertyIdentifier = session.propertyIdentifier
        self.homeownership = session.homeownership?.rawValue
        self.hasSolar = session.electrical.hasSolar
        self.hasStandbyGenerator = session.electrical.hasStandbyGenerator
        self.hasExistingWholeHomeBattery = session.electrical.hasExistingWholeHomeBattery
        self.plannedBatteryCount = session.electrical.plannedBatteryCount
        self.mainBreakerAmperage = session.electrical.mainBreakerAmperage
        self.meterNumber = session.electrical.meterNumber
        self.batteryPlaced = session.placement.batteryPlaced
        self.meterMarked = session.placement.meterMarked
        self.gasMeterMarked = session.placement.gasMeterMarked
        self.lidarMeshAvailable = session.placement.lidarMeshAvailable
        self.ruleResults = session.ruleResults.map(AdvisoryRuleResult.init)
    }
}

struct AdvisoryRuleResult: Encodable {
    let id: String
    let title: String
    let status: String
    let usedMeasuredEvidence: Bool
    let isRequired: Bool
    
    init(ruleResult: RuleResult) {
        self.id = ruleResult.id
        self.title = ruleResult.title
        self.status = ruleResult.status.rawValue
        self.usedMeasuredEvidence = ruleResult.usedMeasuredEvidence
        self.isRequired = ruleResult.isRequired
    }
}

struct AdvisoryQuestion: Encodable {
    let key: String
    let type: String
    let prompt: String
    let choices: [String]?
    
    init(key: String, type: String, prompt: String, choices: [String]? = nil) {
        self.key = key
        self.type = type
        self.prompt = prompt
        self.choices = choices
    }
}

// MARK: - Response Models

struct OpenJEVAdvisoryResponse: Decodable {
    let answers: [AdvisoryAnswer]
}

struct AdvisoryAnswer: Decodable, Identifiable {
    let key: String
    let value: String?
    let confidence: Double?
    
    var id: String { key }
    
    var displayValue: String {
        value ?? "unknown"
    }
    
    var displayConfidence: String {
        guard let confidence else { return "" }
        return String(format: "%.0f%%", confidence * 100)
    }
}
