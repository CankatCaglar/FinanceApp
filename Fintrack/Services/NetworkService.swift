import Foundation
import Combine

enum NetworkError: Error {
    case invalidURL
    case invalidStatusCode(Int)
    case custom(String)
    case decodingError
    case noData
}

class NetworkService {
    static let shared = NetworkService()
    private init() {}
    
    private func createRequest(_ url: URL, apiKey: String, isFinnnhub: Bool = true) -> URLRequest {
        var request = URLRequest(url: url)
        if isFinnnhub {
            request.setValue(apiKey, forHTTPHeaderField: "X-Finnhub-Token")
        } else {
            request.setValue(apiKey, forHTTPHeaderField: "X-CMC_PRO_API_KEY")
        }
        return request
    }
    
    func fetch<T: Decodable>(_ url: String, apiKey: String, isFinnnhub: Bool = true) -> AnyPublisher<T, Error> {
        guard let url = URL(string: url) else {
            return Fail(error: NetworkError.invalidURL).eraseToAnyPublisher()
        }
        
        let request = createRequest(url, apiKey: apiKey, isFinnnhub: isFinnnhub)
        
        return URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("Network Error: Response is not HTTPURLResponse")
                    throw NetworkError.custom("Invalid HTTP Response")
                }
                
                print("Response for \(url.absoluteString):")
                print("Status code: \(httpResponse.statusCode)")
                print("Headers: \(httpResponse.allHeaderFields)")
                print("Data: \(String(data: data, encoding: .utf8) ?? "Unable to decode data")")
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    print("Network Error: Invalid status code \(httpResponse.statusCode)")
                    throw NetworkError.invalidStatusCode(httpResponse.statusCode)
                }
                
                return data
            }
            .decode(type: T.self, decoder: JSONDecoder())
            .mapError { error in
                if let decodingError = error as? DecodingError {
                    print("Decoding Error: \(decodingError)")
                    return NetworkError.decodingError
                }
                if let networkError = error as? NetworkError {
                    return networkError
                }
                return NetworkError.custom(error.localizedDescription)
            }
            .eraseToAnyPublisher()
    }
} 