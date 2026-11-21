import Foundation
import Combine
import Security

struct Sample: Decodable, Identifiable {
    let sampled_at, cpu_percent, ram_percent, disk_percent: Double
    let uptime_seconds: Int
    let hostname, os: String
    var id: Double { sampled_at }
    var time: Date { Date(timeIntervalSince1970: sampled_at) }
}

struct Problem: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum Vault {
    static func query(_ endpoint: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "NEXUS pairing", kSecAttrAccount as String: endpoint]
    }

    static func read(_ endpoint: String) throws -> String {
        var lookup = query(endpoint)
        lookup[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { throw Problem("Enter the pairing token for this PC and port.") }
        guard status == errSecSuccess, let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw Problem("Unlock your iPhone and try reading the saved token again.")
        }
        return token
    }

    static func save(_ token: String, for endpoint: String) throws {
        var item = query(endpoint)
        let value = [kSecValueData as String: Data(token.utf8)]
        let status = SecItemUpdate(item as CFDictionary, value as CFDictionary)
        if status == errSecSuccess { return }
        if status == errSecItemNotFound {
            item.merge(value) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            if SecItemAdd(item as CFDictionary, nil) == errSecSuccess { return }
        }
        throw Problem("Keychain could not save the token. Unlock the phone and reconnect.")
    }
}

private final class LocalOnly: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class Monitor: ObservableObject {
    @Published var samples: [Sample] = []
    @Published var status = "Disconnected"
    @Published var detail = "Open Settings to pair your Windows PC."
    @Published var active = false
    private var task: Task<Void, Never>?
    private let session = URLSession(configuration: .ephemeral, delegate: LocalOnly(), delegateQueue: nil)

    func disconnect() {
        task?.cancel()
        task = nil
        active = false
        samples.removeAll()
        status = "Disconnected"
        detail = "Open Settings to connect."
    }

    func connect(host: String, port: String, typedToken: String, interval: Int) {
        disconnect()
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { UInt8($0) }
        guard numbers.count == 4, numbers.map({ String($0) }).joined(separator: ".") == host,
              host == "127.0.0.1" || numbers[0] == 10 || (numbers[0] == 172 && (16...31).contains(numbers[1])) ||
              (numbers[0] == 192 && numbers[1] == 168),
              let p = UInt16(port), p > 0 else {
            detail = "Use the PC’s private IPv4 address and a port from 1 to 65535."
            return
        }
        let endpoint = "\(host):\(p)"
        guard let url = URL(string: "http://\(endpoint)/api/v1/stats") else { return }
        do {
            let token = try typedToken.isEmpty ? Vault.read(endpoint) : typedToken
            var request = URLRequest(url: url, timeoutInterval: 5)
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            active = true
            status = "Connecting"
            detail = "Contacting \(endpoint)…"
            task = Task {
                var needsSave = !typedToken.isEmpty
                while !Task.isCancelled {
                    do {
                        let (data, response) = try await session.data(for: request)
                        try Task.checkCancellation()
                        let code = (response as? HTTPURLResponse)?.statusCode
                        if code == 401 {
                            disconnect()
                            detail = "Token rejected. Paste the current token from the PC."
                            return
                        }
                        guard code == 200 else { throw Problem("Server returned HTTP \(code ?? 0). Retrying.") }
                        let sample = try JSONDecoder().decode(Sample.self, from: data)
                        if needsSave {
                            do { try Vault.save(token, for: endpoint) }
                            catch { disconnect(); detail = error.localizedDescription; return }
                            needsSave = false
                        }
                        if samples.last?.id != sample.id { samples.append(sample) }
                        samples = Array(samples.suffix(30))
                        status = "Online"
                        detail = "\(sample.hostname) · \(endpoint)"
                    } catch {
                        if Task.isCancelled { return }
                        samples.removeAll()
                        status = "Unavailable"
                        detail = "\(error.localizedDescription) Check the server, Wi-Fi and Local Network permission."
                    }
                    try? await Task.sleep(nanoseconds: UInt64(max(2, interval)) * 1_000_000_000)
                }
            }
        } catch { detail = error.localizedDescription }
    }
}
