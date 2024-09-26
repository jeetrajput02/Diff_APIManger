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
    
    public class func makeAsyncRequest<T:Codable>(url: String, method: HTTPMethod, parameter: [String:Any]?, headers: [String: String] = [:], timeoutInterval: TimeInterval = 30, type: T.Type) async -> Result<T,Error> {
        
        guard NetworkManager.shared.isInternetAvailable() else {
            return .failure(NetworkError.noInternet)
        }
        
        switch createURLRequest(url: url, method: method, headers: headers, timeoutInterval: timeoutInterval) {
        case .success(let urlRequest):
            do {
                return try await withCheckedThrowingContinuation { continuation in
                    
                    AF.request(urlRequest)
                        .responseData(queue: .global(qos: .background)) { response in
                            
                            switch response.result {
                                
                            case .success(let responseData):
                                do {
                                    
                                    print(responseData.prettyPrintedJSONString ?? "")
                                    guard let httpResponse = response.response else {
                                        continuation.resume(returning: .failure(NetworkError.unknown))
                                        return
                                    }
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
        case .failure(let error):
            return .failure(error)
        }
        
    }
    
    // progressHandler: @escaping (Double) -> Void
    public class func makeAsyncUploadRequest<T: Codable>(url: String, method: HTTPMethod, parameter: [String: Any]?, mediaObj: [String: mediaObject]?, headers: [String: String] = [:], timeoutInterval: TimeInterval = 30, type: T.Type, progressHandler: @escaping (Double) -> Void) async -> Result<T, Error> {
        
        guard NetworkManager.shared.isInternetAvailable() else {
            return .failure(NetworkError.noInternet)
        }
     
        switch createURLRequest(url: url, method: method, headers: headers, timeoutInterval: timeoutInterval) {
            
        case .success(let urlRequest):

             do {
                 return try await withCheckedThrowingContinuation { continuation in
                     
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
                                 multipartFormData.append(media.data, withName: key, fileName: media.filename, mimeType: media.mimeType)
                             }
                         }
                         
                     }, with: urlRequest)
                     .uploadProgress { progress in
                         progressHandler(progress.fractionCompleted)
                     }
                     .responseData(queue: .global(qos: .background)) { response in
                         
                         switch response.result {
                             
                         case .success(let responseData):
                             do {
                                 print(responseData.prettyPrintedJSONString ?? "")
                                 guard let httpResponse = response.response else {
                                     continuation.resume(returning: .failure(NetworkError.unknown))
                                     return
                                 }
                                 if httpResponse.statusCode == 200 {
                                     let decodedData = try JSONDecoder().decode(T.self, from: responseData)
                                     continuation.resume(returning: .success(decodedData))
                                 } else if httpResponse.statusCode == 401 {
                                     continuation.resume(returning: .failure(NetworkError.authentication))
                                 } else {
                                     continuation.resume(returning: .failure(NetworkError.responseError))
                                 }
                             } catch {
                                 continuation.resume(returning: .failure(NetworkError.unknown))
                             }
                             
                         case .failure(let error):
                             handleAFError(error, response: response, continuation: continuation)
                         }
                     }
                 }
             } catch {
                 return .failure(NetworkError.unknown)
             }
             
        case .failure(let error):
            return .failure(error)
        }
        
        
        
    }

    public class func makeAsyncUploadRequest<T: Codable>(url: String, method: HTTPMethod, parameter: [String: Any]?, mediaObjects: [String: [mediaObject]]? = nil, headers: [String: String] = [:], timeoutInterval: TimeInterval = 30, type: T.Type, progressHandler: @escaping (Double) -> Void) async -> Result<T, Error> {
        
        guard NetworkManager.shared.isInternetAvailable() else {
            return .failure(NetworkError.noInternet)
        }
        
        switch createURLRequest(url: url, method: method, headers: headers, timeoutInterval: timeoutInterval) {
            
        case .success(let urlRequest):
            do {
                return try await withCheckedThrowingContinuation { continuation in
                    
                    AF.upload(multipartFormData: { multipartFormData in
                        
                        // Append parameters
                        if let params = parameter {
                            for (key, value) in params {
                                if let val = value as? String, let data = val.data(using: .utf8) {
                                    multipartFormData.append(data, withName: key)
                                }
                            }
                        }
                        
                        // Append multiple media objects
                        if let mediaObjects = mediaObjects {
                            for (key, mediaArray) in mediaObjects {
                                for media in mediaArray {
                                    multipartFormData.append(media.data, withName: key, fileName: media.filename, mimeType: media.mimeType)
                                }
                            }
                        }
                        
                    }, with: urlRequest)
                    .uploadProgress { progress in
                        progressHandler(progress.fractionCompleted)
                    }
                    .responseData(queue: .global(qos: .background)) { response in
                        
                        switch response.result {
                            
                        case .success(let responseData):
                            do {
                                print(responseData.prettyPrintedJSONString ?? "")
                                guard let httpResponse = response.response else {
                                    continuation.resume(returning: .failure(NetworkError.unknown))
                                    return
                                }
                                if httpResponse.statusCode == 200 {
                                    let decodedData = try JSONDecoder().decode(T.self, from: responseData)
                                    continuation.resume(returning: .success(decodedData))
                                } else if httpResponse.statusCode == 401 {
                                    continuation.resume(returning: .failure(NetworkError.authentication))
                                } else {
                                    continuation.resume(returning: .failure(NetworkError.responseError))
                                }
                            } catch {
                                continuation.resume(returning: .failure(NetworkError.unknown))
                            }
                            
                        case .failure(let error):
                            handleAFError(error, response: response, continuation: continuation)
                        }
                    }
                }
            } catch {
                return .failure(NetworkError.unknown)
            }
        case .failure(let error):
            return .failure(error)
        }
        
    }

    
}

//MARK: - Without genric
extension APIManager {
    
    public class func makeAsyncRequest(url: String, method: HTTPMethod, parameter: [String:Any]?,headers: [String: String] = [:],timeoutInterval: TimeInterval = 30) async -> Result<Any,Error> {
        
        guard NetworkManager.shared.isInternetAvailable() else {
            return .failure(NetworkError.noInternet)
        }
        
        switch createURLRequest(url: url, method: method, headers: headers, timeoutInterval: timeoutInterval) {
        case .success(let urlRequest):
            do {
                return try await withCheckedThrowingContinuation { continuation in
                  
                    AF.request(urlRequest)
                        .responseData(queue: .global(qos: .background)) { response in
                            
                            switch response.result {
                                
                            case .success(let responseData):
                                do {
                                    print(responseData.prettyPrintedJSONString ?? "")
                                    guard let httpResponse = response.response else {
                                        continuation.resume(returning: .failure(NetworkError.unknown))
                                        return
                                    }
                                    if httpResponse.statusCode == 200 {
                                        let response = try JSONSerialization.jsonObject(with: responseData)
                                        continuation.resume(returning: .success(response))
                                        
                                    } else if httpResponse.statusCode == 401 {
                                        continuation.resume(returning: .failure(NetworkError.authentication))
                                    } else {
                                        continuation.resume(returning: .failure(NetworkError.responseError))
                                    }
                                    
                                } catch {
                                    print("Parsing error: \(error.localizedDescription)")
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
        case .failure(let error):
            return .failure(error)
        }
        
        
    }
    
    public class func makeAsyncUploadRequest(url: String, method: HTTPMethod, parameter: [String: Any]?, mediaObj: [String: mediaObject]?, headers: [String: String] = [:], timeoutInterval: TimeInterval = 30, progressHandler: @escaping (Double) -> Void) async -> Result<Any, Error> {
        
        guard NetworkManager.shared.isInternetAvailable() else {
            return .failure(NetworkError.noInternet)
        }
        
        switch createURLRequest(url: url, method: method, headers: headers, timeoutInterval: timeoutInterval) {
            
        case .success(let urlRequest):
            do {
                return try await withCheckedThrowingContinuation { continuation in
                    
                    // Perform the upload
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
                                multipartFormData.append(media.data, withName: key, fileName: media.filename, mimeType: media.mimeType)
                            }
                        }
                        
                    }, with: urlRequest)
                    .uploadProgress { progress in
                        progressHandler(progress.fractionCompleted)
                    }
                    .responseData(queue: .global(qos: .background)) { response in
                        
                        switch response.result {
                            
                        case .success(let responseData):
                            do {
                                print(responseData.prettyPrintedJSONString ?? "")
                                guard let httpResponse = response.response else {
                                    continuation.resume(returning: .failure(NetworkError.unknown))
                                    return
                                }
                                if httpResponse.statusCode == 200 {
                                    let response = try JSONSerialization.jsonObject(with: responseData)
                                    continuation.resume(returning: .success(response))
                                } else if httpResponse.statusCode == 401 {
                                    continuation.resume(returning: .failure(NetworkError.authentication))
                                } else {
                                    continuation.resume(returning: .failure(NetworkError.responseError))
                                }
                            } catch {
                                continuation.resume(returning: .failure(NetworkError.unknown))
                            }
                            
                        case .failure(let error):
                            handleAFError(error, response: response, continuation: continuation)
                        }
                    }
                }
            } catch {
                return .failure(NetworkError.unknown)
            }
        case .failure(let error):
            return .failure(error)
            
        }
        
        
    }

    public class func makeAsyncUploadRequest(url: String, method: HTTPMethod, parameter: [String: Any]?, mediaObjects: [String: [mediaObject]]? = nil, headers: [String: String] = [:], timeoutInterval: TimeInterval = 30, progressHandler: @escaping (Double) -> Void) async -> Result<Any, Error> {
        
        guard NetworkManager.shared.isInternetAvailable() else {
            return .failure(NetworkError.noInternet)
        }
        
        switch createURLRequest(url: url, method: method, headers: headers, timeoutInterval: timeoutInterval) {
            
        case .success(let urlRequest):
            do {
                return try await withCheckedThrowingContinuation { continuation in
                    
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
                        if let mediaObjects = mediaObjects {
                            for (key, mediaArray) in mediaObjects {
                                for media in mediaArray {
                                    multipartFormData.append(media.data, withName: key, fileName: media.filename, mimeType: media.mimeType)
                                }
                            }
                        }
                        
                    }, with: urlRequest)
                    .uploadProgress { progress in
                        progressHandler(progress.fractionCompleted)
                    }
                    .responseData(queue: .global(qos: .background)) { response in
                        
                        switch response.result {
                            
                        case .success(let responseData):
                            do {
                                print(responseData.prettyPrintedJSONString ?? "")
                                guard let httpResponse = response.response else {
                                    continuation.resume(returning: .failure(NetworkError.unknown))
                                    return
                                }
                                if httpResponse.statusCode == 200 {
                                    let response = try JSONSerialization.jsonObject(with: responseData)
                                    continuation.resume(returning: .success(response))
                                } else if httpResponse.statusCode == 401 {
                                    continuation.resume(returning: .failure(NetworkError.authentication))
                                } else {
                                    continuation.resume(returning: .failure(NetworkError.responseError))
                                }
                            } catch {
                                continuation.resume(returning: .failure(NetworkError.unknown))
                            }
                            
                        case .failure(let error):
                            handleAFError(error, response: response, continuation: continuation)
                        }
                    }
                }
            } catch {
                return .failure(NetworkError.unknown)
            }
        case .failure(let error):
            return .failure(error)
            
        }
        
    }

    
}


//MARK: - Error handling
extension APIManager {
    private class func handleAFError(_ error: AFError, response: AFDataResponse<Data>, continuation: CheckedContinuation<Result<Any, Error>, Error>) {
        print("Request failed: \(error.localizedDescription)")
        if error.isSessionTaskError || error.isExplicitlyCancelledError {
            print("Request timed out.")
            continuation.resume(returning: .failure(NetworkError.timeout))
        } else {
            if let responseData = response.data, let errorString = String(data: responseData, encoding: .utf8) {
                print("Error response: \(errorString)")
            }
            continuation.resume(returning: .failure(NetworkError.unknown))
        }
    }
    
    private class func handleAFError<T>(_ error: AFError, response: AFDataResponse<Data>, continuation: CheckedContinuation<Result<T, Error>, Error>) {
        print("Request failed: \(error.localizedDescription)")
        
        if error.isSessionTaskError || error.isExplicitlyCancelledError {
            print("Request timed out.")
            continuation.resume(returning: .failure(NetworkError.timeout))
        } else {
            if let responseData = response.data, let errorString = String(data: responseData, encoding: .utf8) {
                print("Error response: \(errorString)")
            }
            continuation.resume(returning: .failure(NetworkError.unknown))
        }
    }

}


//MARK: - Create urlRequest
extension APIManager {
    
    private class func createURLRequest(url: String, method: HTTPMethod, headers: [String: String], timeoutInterval: TimeInterval) -> Result<URLRequest, Error> {
        guard let validURL = URL(string: url) else {
            return .failure(NetworkError.invalidURL)
        }
        
        var urlRequest: URLRequest
        do {
            let httpHeader = HTTPHeaders(headers)
            urlRequest = try URLRequest(url: validURL, method: method, headers: httpHeader)
            urlRequest.timeoutInterval = timeoutInterval
            return .success(urlRequest)
        } catch {
            return .failure(NetworkError.unknown)
        }
    }
    
}
