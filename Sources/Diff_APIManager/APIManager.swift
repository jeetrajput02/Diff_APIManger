//
//  APIManager.swift
//  
//
//   Created by Jeet on 25/09/24.
//

import Foundation
import Alamofire
import Combine

public enum NetworkError: Error {
    case invalidURL
    case responseError
    case unknown
    case authentication
    case timeout
    case noInternet
}


extension NetworkError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return NSLocalizedString("Invalid URL", comment: "Invalid URL")
        case .responseError:
            return NSLocalizedString("Unexpected status code", comment: "Invalid response")
        case .unknown:
            return NSLocalizedString("Unknown error", comment: "Unknown error")
        case .authentication:
            return NSLocalizedString("Authentication is expired", comment: "Authentication error")
        case .timeout:
            return NSLocalizedString("Request timeout", comment: "Request timeout")
        case .noInternet:
            return NSLocalizedString("No Internet connecting", comment: "No Internet connecting")
        }
    }
}

public enum mediaType {
    case image
    case video
    case pdf
    case other
}

public struct mediaObject {
    public var type: mediaType // debug purpose
    public var data: Data
    public var filename: String
    public var mimeType: String

    // Add a public initializer
    public init(type: mediaType, data: Data, filename: String, mimeType: String) {
        self.type = type
        self.data = data
        self.filename = filename
        self.mimeType = mimeType
    }
}
 
public class APIManager {
    

    public class func makeAsyncRequest<T:Codable>(url: String, method: HTTPMethod, parameter: [String:Any]?,timeoutInterval: TimeInterval = 30, type: T.Type) async -> Result<T,Error> {
        
        if NetworkManager.shared.isInternetAvailable() {
            
            let headers:[String:String] = [:]
            let httpHeader = HTTPHeaders(headers)
            guard let validURL = URL(string: url) else {
                return .failure(NetworkError.invalidURL)
            }
            
            var urlRequest: URLRequest
            do {
                urlRequest = try URLRequest(url: validURL, method: method, headers: httpHeader)
                urlRequest.timeoutInterval = timeoutInterval
            } catch {
                return .failure(NetworkError.unknown)
            }
            
            do {
                return try await withCheckedThrowingContinuation { continuation in
                  
                    AF.request(urlRequest)
                        .responseData(queue: .global(qos: .background)) { response in
                            
                            switch response.result {
                                
                            case .success(let responseData):
                                do {
                                    
                                    guard let httpResponse = response.response else {
                                        continuation.resume(returning: .failure(NetworkError.unknown))
                                        return
                                    }
                                    print(responseData.prettyPrintedJSONString ?? "")
                                    if httpResponse.statusCode == 200 {
                                        let data = try JSONDecoder().decode(T.self, from: responseData)
                                        continuation.resume(returning: .success(data))
                                    } else if httpResponse.statusCode == 401 {
                                        continuation.resume(returning: .failure(NetworkError.authentication))
                                    } else {
                                        continuation.resume(returning: .failure(NetworkError.responseError))
                                    }
                                    
                                } catch {
                                    print(error.localizedDescription)
                                    continuation.resume(returning: .failure(NetworkError.unknown))
                                }
                                
                            case .failure(let error):
                                print(error.localizedDescription)
                                if let afError = error.asAFError {
                                    if afError.isSessionTaskError || afError.isExplicitlyCancelledError {
                                       
                                        print("Request timed out.")
                                        continuation.resume(returning: .failure(NetworkError.timeout))
                                    } else {
                                        // Handle other AFErrors
                                        if let responseData = response.data {
                                            print("Failure response: \(responseData.prettyPrintedJSONString ?? String(decoding: responseData, as: UTF8.self))")
                                        }
                                        continuation.resume(returning: .failure(NetworkError.invalidURL))
                                    }
                                } else {
                                    // Handle non-AFError cases
                                    if let responseData = response.data {
                                        print("Failure response: \(responseData.prettyPrintedJSONString ?? String(decoding: responseData, as: UTF8.self))")
                                    }
                                    continuation.resume(returning: .failure(error))
                                }
                            }
                            
                        }
                }
                
            } catch {
                print(error.localizedDescription)
                return .failure(NetworkError.unknown)
                
            }
            
        } else {
            return .failure(NetworkError.noInternet)
        }
        
    }
    
    public class func makeAsyncUploadRequest<T: Codable>(url: String, method: HTTPMethod, parameter: [String: Any]?, mediaObj: [String: mediaObject]?,timeoutInterval: TimeInterval = 30, type: T.Type) async -> Result<T, Error> {
        
        if NetworkManager.shared.isInternetAvailable() {
            
            let headers: [String: String] = [:]
            let httpHeader = HTTPHeaders(headers)
            
            guard let validURL = URL(string: url) else {
                return .failure(NetworkError.invalidURL)
            }
            

            var urlRequest: URLRequest
            do {
                urlRequest = try URLRequest(url: validURL, method: method, headers: httpHeader)
                urlRequest.timeoutInterval = timeoutInterval
            } catch {
                return .failure(NetworkError.unknown)
            }
            
            do {
                return try await withCheckedThrowingContinuation { continuation in
                    
                    // Perform the request using Alamofire's upload
                    AF.upload(multipartFormData: { multipartFormData in
                        
                        // Append parameters
                        if let params = parameter {
                            for (key, value) in params {
                                if let val = value as? String, let data = val.data(using: .utf8) {
                                    multipartFormData.append(data, withName: key)
                                }
                            }
                        }
                        
                        // Append media objects
                        if let mediaObjects = mediaObj {
                            for (key, media) in mediaObjects {
                                multipartFormData.append(media.data,
                                                         withName: key,
                                                         fileName: media.filename,
                                                         mimeType: media.mimeType)
                            }
                        }
                        
                    }, with: urlRequest)  // Use the URLRequest with the timeout
                    .uploadProgress { progress in
                        print("Upload Progress: \(progress.fractionCompleted)")
                    }
                    .responseData(queue: .global(qos: .background)) { response in
                        
                        switch response.result {
                            
                        case .success(let responseData):
                            do {
                                // Decode the response data
                                guard let httpResponse = response.response else {
                                    continuation.resume(returning: .failure(NetworkError.unknown))
                                    return
                                }
                                print(responseData.prettyPrintedJSONString ?? "")
                                if httpResponse.statusCode == 200 {
                                    let data = try JSONDecoder().decode(T.self, from: responseData)
                                    continuation.resume(returning: .success(data))
                                } else if httpResponse.statusCode == 401 {
                                    continuation.resume(returning: .failure(NetworkError.authentication))
                                } else {
                                    continuation.resume(returning: .failure(NetworkError.responseError))
                                }
                                
                            } catch {
                                print("Decoding error: \(error.localizedDescription)")
                                continuation.resume(returning: .failure(NetworkError.unknown))
                            }
                            
                        case .failure(let error):
                            print("Request failed: \(error.localizedDescription)")
                            if let afError = error.asAFError {
                                if afError.isSessionTaskError || afError.isExplicitlyCancelledError {
                                    // Handle timeout error
                                    print("Request timed out.")
                                    continuation.resume(returning: .failure(NetworkError.timeout))
                                } else {
                                    if let responseData = response.data {
                                        print("Failure response: \(responseData.prettyPrintedJSONString ?? String(decoding: responseData, as: UTF8.self))")
                                    }
                                    continuation.resume(returning: .failure(NetworkError.unknown))
                                }
                            } else {
                                if let responseData = response.data {
                                    print("Failure response: \(responseData.prettyPrintedJSONString ?? String(decoding: responseData, as: UTF8.self))")
                                }
                                continuation.resume(returning: .failure(NetworkError.unknown))
                            }
                        }
                    }
                }
            } catch {
                print("Upload failed: \(error.localizedDescription)")
                return .failure(NetworkError.unknown)
            }
        } else {
            return .failure(NetworkError.noInternet)
        }
        
    }
    
    public class func makeAsyncUploadMultipleFileRequest<T: Codable>(url: String, method: HTTPMethod, parameter: [String: Any]?, mediaObjects: [String: [mediaObject]]? = nil, timeoutInterval: TimeInterval = 30, type: T.Type) async -> Result<T, Error> {
        
        if NetworkManager.shared.isInternetAvailable() {
            
            let headers: [String: String] = [:]
            let httpHeader = HTTPHeaders(headers)
            
            guard let validURL = URL(string: url) else {
                return .failure(NetworkError.invalidURL)
            }
            
            var urlRequest: URLRequest
            do {
                urlRequest = try URLRequest(url: validURL, method: method, headers: httpHeader)
                urlRequest.timeoutInterval = timeoutInterval
            } catch {
                return .failure(NetworkError.unknown)
            }
            
            do {
                return try await withCheckedThrowingContinuation { continuation in
                    
                    AF.upload(multipartFormData: { multipartFormData in
                        
                        if let params = parameter {
                            for (key, value) in params {
                                if let val = value as? String, let data = val.data(using: .utf8) {
                                    multipartFormData.append(data, withName: key)
                                }
                            }
                        }
                        
                        if let mediaObjects = mediaObjects {
                            for (key, mediaArray) in mediaObjects {
                                for media in mediaArray {
                                    multipartFormData.append(media.data,
                                                             withName: key,
                                                             fileName: media.filename,
                                                             mimeType: media.mimeType)
                                }
                            }
                        }
                        
                    }, with: urlRequest)
                    .uploadProgress { progress in
                        print("Upload Progress: \(progress.fractionCompleted)")
                    }
                    .responseData(queue: .global(qos: .background)) { response in
                        
                        switch response.result {
                            
                        case .success(let responseData):
                            do {
                                guard let httpResponse = response.response else {
                                    continuation.resume(returning: .failure(NetworkError.unknown))
                                    return
                                }
                                print(responseData.prettyPrintedJSONString ?? "")
                                if httpResponse.statusCode == 200 {
                                    let data = try JSONDecoder().decode(T.self, from: responseData)
                                    continuation.resume(returning: .success(data))
                                } else if httpResponse.statusCode == 401 {
                                    continuation.resume(returning: .failure(NetworkError.authentication))
                                } else {
                                    continuation.resume(returning: .failure(NetworkError.responseError))
                                }
                                
                            } catch {
                                print("Decoding error: \(error.localizedDescription)")
                                continuation.resume(returning: .failure(NetworkError.unknown))
                            }
                            
                        case .failure(let error):
                            print("Request failed: \(error.localizedDescription)")
                            if let afError = error.asAFError {
                                if afError.isSessionTaskError || afError.isExplicitlyCancelledError {
                                    print("Request timed out.")
                                    continuation.resume(returning: .failure(NetworkError.timeout))
                                } else {
                                    if let responseData = response.data {
                                        print("Failure response: \(responseData.prettyPrintedJSONString ?? String(decoding: responseData, as: UTF8.self))")
                                    }
                                    continuation.resume(returning: .failure(NetworkError.unknown))
                                }
                            } else {
                                if let responseData = response.data {
                                    print("Failure response: \(responseData.prettyPrintedJSONString ?? String(decoding: responseData, as: UTF8.self))")
                                }
                                continuation.resume(returning: .failure(NetworkError.unknown))
                            }
                        }
                    }
                }
            } catch {
                print("Upload failed: \(error.localizedDescription)")
                return .failure(NetworkError.unknown)
            }
        } else {
            return .failure(NetworkError.noInternet)
        }
    }
    
}

