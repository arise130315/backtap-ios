import Foundation

/// 查询 DeepSeek 账户余额。
/// 官方接口:`GET <baseURL>/user/balance`,Bearer 同 Chat Completions 用的 API Key。
/// 响应里 `balance_infos` 是数组(支持多币种),取第一项即可。
enum DeepSeekBalanceService {
    struct Balance: Decodable {
        let isAvailable: Bool
        let balanceInfos: [BalanceInfo]

        struct BalanceInfo: Decodable {
            let currency: String         // "CNY" / "USD"
            let totalBalance: String     // 字符串形式的数字,例如 "9.42"
            let grantedBalance: String   // 赠送
            let toppedUpBalance: String  // 充值

            enum CodingKeys: String, CodingKey {
                case currency
                case totalBalance    = "total_balance"
                case grantedBalance  = "granted_balance"
                case toppedUpBalance = "topped_up_balance"
            }
        }

        enum CodingKeys: String, CodingKey {
            case isAvailable  = "is_available"
            case balanceInfos = "balance_infos"
        }
    }

    struct ServiceError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func fetch(baseURL: String, apiKey: String) async throws -> Balance {
        guard !apiKey.isEmpty else { throw ServiceError(message: "API Key 未配置") }
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed + "/user/balance") else {
            throw ServiceError(message: "Base URL 不合法")
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json",  forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw ServiceError(message: "HTTP \(code) \(body)")
        }
        do {
            return try JSONDecoder().decode(Balance.self, from: data)
        } catch {
            throw ServiceError(message: "余额数据解析失败")
        }
    }
}
