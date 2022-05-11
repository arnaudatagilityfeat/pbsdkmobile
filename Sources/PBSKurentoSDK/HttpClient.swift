import UIKit
import PromiseKit
import PMKFoundation

public class HttpApi {
    var baseUrl: String?
    var token: String?
    var adminBaseUrl: String?
    var isSecured: Bool = true
    public init(baseUrl: String?, token: String?, adminBaseUrl: String?) {
        self.baseUrl = baseUrl
        self.token = token
        self.adminBaseUrl = adminBaseUrl
    }
    private func getUrl(from endpoint: ApiRequestEndpoint) -> URL? {
        if let base = baseUrl {
            var components = URLComponents()
            components.scheme = isSecured ? "https" : "http"
            components.host = base
            components.path = endpoint.path
            if endpoint.queryItems.count > 0 {
                components.queryItems = endpoint.queryItems
            }
            
            return components.url
        }
        return nil
    }
    
    public func requestOfferSDP(_ endpoint: ApiRequestEndpoint, offer: Offer,  httpMethod: String = HttpMethod.get.rawValue)-> Promise<Bool> {
        let (promise, resolver) = Promise<Bool>.pending()
        if let url = getUrl(from: endpoint) {
            var request = URLRequest(url: url)
            request.httpMethod = httpMethod
            do {
                let encoder = JSONEncoder()
                let offerData = try encoder.encode(offer)
//                request.httpBody = try? JSONSerialization.data(withJSONObject: offerData, options:.fragmentsAllowed)
                request.httpBody = offerData
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("*", forHTTPHeaderField: "Access-Control-Allow-Origin")
                request.setValue(self.token, forHTTPHeaderField: "Authorization")
                
                URLSession.shared.dataTask(with: request) { (data, response, error) in
                    if let error = error {
//                        completion(.failure(.network(error)))
                        
                        return resolver.reject(error)
                    }
                    
                    guard let response = response as? HTTPURLResponse,
                        200 ... 299 ~= response.statusCode else {
                        
                            
                        return resolver.reject(DataError.invalidResponse)
                    }
                    
                    guard data != nil else {
                        return resolver.reject(DataError.invalidData)
                    }
                    
                        return resolver.fulfill(true)
                
                }.resume()
            } catch (let error) {
                print(error)
            }
        }
        return promise
    }
    
    public func requestVoid(_ endpoint: ApiRequestEndpoint, body: [String : Any]? = nil,  httpMethod: String = HttpMethod.get.rawValue)-> Promise<Bool> {
        let (promise, resolver) = Promise<Bool>.pending()
        if let url = getUrl(from: endpoint) {
            var request = URLRequest(url: url)
            request.httpMethod = httpMethod
            do {
                if let body = body{
                    request.httpBody = try? JSONSerialization.data(withJSONObject: body, options:.fragmentsAllowed)
                }
                
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("*", forHTTPHeaderField: "Access-Control-Allow-Origin")
                request.setValue(self.token, forHTTPHeaderField: "Authorization")
                
                URLSession.shared.dataTask(with: request) { (data, response, error) in
                    if let error = error {
//                        completion(.failure(.network(error)))
                        
                        return resolver.reject(error)
                    }
                    
                    guard let response = response as? HTTPURLResponse,
                        200 ... 299 ~= response.statusCode else {
                        
                            
                        return resolver.reject(DataError.invalidResponse)
                    }
                    
                    guard data != nil else {
                        return resolver.reject(DataError.invalidData)
                    }
                    
                        return resolver.fulfill(true)
                
                }.resume()
            } catch (let error) {
                print(error)
            }
        }
        return promise
    }
    
//    public func requestVoid(_ endpoint: ApiRequestEndpoint, body: [String : Any]? = nil,
//                                       httpMethod: String = HttpMethod.get.rawValue,
//                                       completion: @escaping (Result<Bool, DataError>)->Void) {
//        if let url = getUrl(from: endpoint) {
//            var request = URLRequest(url: url)
//            request.httpMethod = httpMethod
//            do {
//                if let body = body{
//                    request.httpBody = try? JSONSerialization.data(withJSONObject: body, options:.fragmentsAllowed)
//                }
//
//                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//                request.setValue("*", forHTTPHeaderField: "Access-Control-Allow-Origin")
//                request.setValue(self.token, forHTTPHeaderField: "Authorization")
//                URLSession.shared.dataTask(with: request) { (data, response, error) in
//                    if let error = error {
//                        completion(.failure(.network(error)))
//                        return
//                    }
//
//                    guard let response = response as? HTTPURLResponse,
//                        200 ... 299 ~= response.statusCode else {
//                        completion(.failure(.invalidResponse))
//                        return
//                    }
//
//                    guard data != nil else {
//                        completion(.failure(.invalidData))
//                        return
//                    }
//
//
//                    completion(.success(true))
//                }.resume()
//            } catch (let error) {
//                print(error)
//            }
//        }
//    }
    
    
    public func request<T: Codable>(_ endpoint: ApiRequestEndpoint, type: T.Type, body: [String : Any]? = nil,
                                       httpMethod: String = HttpMethod.get.rawValue) -> Promise<T?> {
        let (promise, resolver) = Promise<T?>.pending()
        if let url = getUrl(from: endpoint) {
            var request = URLRequest(url: url)
            request.httpMethod = httpMethod
            
            print("### REQUEST ### URL \(url)")
            if let body = body{
//                if T.Type.self == User.Type.self {
//                    request.httpBody = try? JSONSerialization.data(withJSONObject: ["login"], options:.fragmentsAllowed)
//                }
//                else {
                    request.httpBody = try? JSONSerialization.data(withJSONObject: body, options:.fragmentsAllowed)
//                }
            }

            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("*", forHTTPHeaderField: "Access-Control-Allow-Origin")
            request.setValue(self.token, forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: request) { (data, response, error) in
                if let error = error {
                    return resolver.reject(DataError.network(error))

                }

                guard let response = response as? HTTPURLResponse,
                    200 ... 299 ~= response.statusCode else {
                        return resolver.reject(DataError.invalidResponse)
                }

                guard let data = data else {
                    return resolver.reject(DataError.invalidData)
                }
                
                    let convertedString : String = String(data: data, encoding: String.Encoding.utf8)!
                print("### REQUEST ### RESPONSE \(convertedString)")

                do {
                    // TODO : ["{\"typeMessage\":\"CLOSE_CONNECTION\",\"userId\":[\"61cc587a5d9c3a54e04a4577\"]}"]
                    // For kicking the format is different
                    if T.Type.self == Session.Type.self {
                        let convertedString : String = String(data: data, encoding: String.Encoding.utf8)!
                        return resolver.fulfill(Session(id: convertedString) as? T)
                    }else if T.Type.self == [Event].Type.self {
                        let convertedString : String = String(data: data, encoding: String.Encoding.utf8)!
                        let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                        let eventStringArray = try JSONDecoder().decode([String].self, from: data)
                        var response: [Event] = []
                        var index = 0;
                        for eventString in eventStringArray {
                            let event: Event =  try JSONDecoder().decode(Event.self, from: eventString.data(using: .utf8)!)
                            response.append(event)
                            index = index + 1
                        }   
                        return resolver.fulfill(response as? T)
                    }
                    else{
                        if let responseString = String(data: data, encoding: String.Encoding.utf8){
                            if responseString.count == 0{
                                return resolver.fulfill(nil)
                            }else{
                                let decodedData = try JSONDecoder().decode(T.self, from: data)
                                return resolver.fulfill(decodedData)
                            }
                        }
                    }

                }catch {
                    return resolver.reject(DataError.network(error))

                }
            }.resume()
        }

        return promise
    }
    
//    private func request<T: Decodable>(_ endpoint: ApiRequestEndpoint, body: [String : Any]? = nil,
//                                       httpMethod: String = HttpMethod.get.rawValue,
//                                       completion: @escaping Completion<T?>) {
//        if let url = getUrl(from: endpoint) {
//            var request = URLRequest(url: url)
//            request.httpMethod = httpMethod
//
//            if let body = body{
//                request.httpBody = try? JSONSerialization.data(withJSONObject: body, options:.fragmentsAllowed)
//            }
//
//            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//            request.setValue("*", forHTTPHeaderField: "Access-Control-Allow-Origin")
//            request.setValue(self.token, forHTTPHeaderField: "Authorization")
//            URLSession.shared.dataTask(with: request) { (data, response, error) in
//                if let error = error {
//                    completion(.failure(.network(error)))
//                    return
//                }
//
//                guard let response = response as? HTTPURLResponse,
//                    200 ... 299 ~= response.statusCode else {
//                    completion(.failure(.invalidResponse))
//                    return
//                }
//
//                guard let data = data else {
//                    completion(.failure(.invalidData))
//                    return
//                }
//
//                do {
//                    // TODO : ["{\"typeMessage\":\"CLOSE_CONNECTION\",\"userId\":[\"61cc587a5d9c3a54e04a4577\"]}"]
//                    // For kicking the format is different
//                    if T.Type.self == Session.Type.self {
//                        let convertedString : String = String(data: data, encoding: String.Encoding.utf8)!
//                        completion(.success(Session(id: convertedString) as? T))
//                    }else if T.Type.self == [Event].Type.self {
//                        let convertedString : String = String(data: data, encoding: String.Encoding.utf8)!
//                        print("event: \(convertedString)")
//                        let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
//                        let eventStringArray = try JSONDecoder().decode([String].self, from: data)
//                        var response: [Event] = []
//                        var index = 0;
//                        for eventString in eventStringArray {
//                            let event: Event =  try JSONDecoder().decode(Event.self, from: eventString.data(using: .utf8)!)
//                            response.append(event)
//                            index = index + 1
//                        }
//                        completion(.success(response as? T))
//                    }
//                    else{
//                        if let responseString = String(data: data, encoding: String.Encoding.utf8){
//                            if responseString.count == 0{
//                                completion(.success(nil))
//                            }else{
//                                let decodedData = try JSONDecoder().decode(T.self, from: data)
//                                completion(.success(decodedData))
//                            }
//                        }
//                    }
//
//                }catch {
//                    completion(.failure(.network(error)))
//
//                }
//            }.resume()
//        }
//    }
    
    public func post<T: Codable>(_ endpoint: ApiRequestEndpoint, type: T, body: [String : Any]) -> Promise<T?>{
        let response = request(endpoint, type: T.self, body: body, httpMethod: HttpMethod.post.rawValue)
        return response
    }
    
    public func get<T:Codable>(_ endpoint: ApiRequestEndpoint, type: T) -> Promise<T?>{
        let response = request(endpoint, type: T.self, httpMethod: HttpMethod.get.rawValue)
        return response
    }
    
    public func put<T:Codable>(_ endpoint: ApiRequestEndpoint, type: T, body: [String : Any]) -> Promise<T?>{
        let response = request(endpoint, type: T.self, body: body, httpMethod: HttpMethod.put.rawValue)
        return response
    }
    
    public func delete<T:Codable>(_ endpoint: ApiRequestEndpoint, type: T) -> Promise<T?>{
        let response = request(endpoint, type: T.self, httpMethod: HttpMethod.delete.rawValue)
        return response
    }
    
//    public func get<T:Decodable>(_ endpoint: ApiRequestEndpoint, completion: @escaping Completion<T?>) -> Promise<T?>{
//        let (promise, resolver) = Promise<T?>.pending()
//        let result = request<T?>(endpoint)
//        resolver.fulfill(result)
//        return promise
//    }
//    //POST
//    public func post<T: Decodable>(_ endpoint: ApiRequestEndpoint, body: [String : Any], completion: @escaping Completion<T?>){
//        request(endpoint, body: body,httpMethod: HttpMethod.post.rawValue){(result: Result<T?, DataError>) in
//            completion(result)
//        }
//    }
//    //PUT
//    public func put<T: Decodable>(_ endpoint: ApiRequestEndpoint, body: [String : Any], completion: @escaping Completion<T?>){
//        request(endpoint, body: body,httpMethod: HttpMethod.post.rawValue){(result: Result<T?, DataError>) in
//            completion(result)
//        }
//    }
//    //DELETE
//    public func delete<T: Decodable>(_ endpoint: ApiRequestEndpoint, completion: @escaping Completion<T?>){
//        request(endpoint, httpMethod: HttpMethod.delete.rawValue){(result: Result<T?, DataError>) in
//            completion(result)
//        }
//    }
}
