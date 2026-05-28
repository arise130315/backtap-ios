import Foundation

/// 拉取 OpenAI 兼容协议服务商的可用模型列表(`GET <baseURL>/models`)。
/// DeepSeek / OpenAI / OpenRouter / Together 都支持;Qwen DashScope 兼容模式不支持,会 4xx。
enum ModelListService {
    struct ServiceError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func fetch(baseURL: String, apiKey: String) async throws -> [String] {
        guard !apiKey.isEmpty else { throw ServiceError(message: "API Key 未配置") }
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed + "/models") else {
            throw ServiceError(message: "Base URL 不合法")
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json",  forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ServiceError(message: "HTTP \(code)。此服务商可能不支持 /models 端点。")
        }
        struct Response: Decodable {
            let data: [Model]
            struct Model: Decodable { let id: String }
        }
        do {
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            return decoded.data.map { $0.id }.sorted()
        } catch {
            throw ServiceError(message: "模型列表解析失败")
        }
    }
}
