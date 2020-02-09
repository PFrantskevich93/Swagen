//
//  String+Generator.swift
//  Swagen
//
//  Created by Dmitriy Petrusevich on 9/27/19.
//  Copyright © 2019 Dmitriy Petrusevich. All rights reserved.
//

import Foundation

let reserverWords = ["Type", "Self", "self", "Codable", "default", "continue"]
let indent = "    "
var genAccessLevel = "public"

extension String {
    var escaped: String {
        var strings = self.split(separator: " ")
        if let string = strings.first, let number = Int(string){
            strings.removeFirst()
        }
        let newString = strings.joined()
        var result = newString.filter { $0.isLetter || $0.isNumber || $0 == "_" }
        result = reserverWords.contains(result) ? "`\(result)`" : result
        return result
    }

    var capitalizedFirstLetter: String {
        guard self.isEmpty == false else { return self }
        return self.prefix(1).uppercased() + self.dropFirst()
    }

    var loweredFirstLetter: String {
        guard self.isEmpty == false else { return self }
        return self.prefix(1).lowercased() + self.dropFirst()
    }
}

let genFilePrefix =
"""
// swiftformat:disable all
// swiftlint:disable all
// Generated file

import Foundation
"""

let apiControllerFile =
"""
import Alamofire
import Foundation

public protocol ApiController {
    var path: String { get }
    var parameters: [String: Any]? { get }
    var method: HTTPMethod { get }
    var encoding: ParameterEncoding { get }
    var headers: HTTPHeaders? { get }
}
"""

let utilsFile =
"""
\(genFilePrefix)

extension Dictionary where Value == Any? {
    func unopt() -> [Key: Any] {
        return reduce(into: [Key: Any]()) { (result, kv) in
            if let value = kv.value {
                result[kv.key] = value
            }
        }
    }

    func unoptString() -> [Key: String] {
        return reduce(into: [Key: String]()) { (result, kv) in
            if let value = kv.value {
                result[kv.key] = String(describing: value)
            }
        }
    }
}

extension JSONDecoder {
    func decodeSafe<T>(_ type: T.Type, from data: Data) throws -> T where T : Decodable {
        do {
            return try self.decode(type, from: data)
        } catch DecodingError.dataCorrupted(let context) {
            let value = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
            if let result = value as? T {
                return result
            } else {
                throw DecodingError.dataCorrupted(context)
            }
        }
    }
}

extension Encodable {
internal var dictionary: [String: Any]? {
    guard let data = try? JSONEncoder().encode(self) else {
        return nil
    }
    
    let dictionary = (try? JSONSerialization.jsonObject(with: data,
                                                        options: .allowFragments)).flatMap { $0 as? [String: Any] }
    return dictionary
    }
}

\(genAccessLevel) enum AnyObjectValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: AnyObjectValue])
    case array([AnyObjectValue])

    \(genAccessLevel) init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([String: AnyObjectValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([AnyObjectValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.typeMismatch(AnyObjectValue.self, DecodingError.Context(codingPath: container.codingPath, debugDescription: "Not a JSON object"))
        }
    }

    \(genAccessLevel) func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        }
    }
}

public struct FileValue {
    public let data: Foundation.Data
    public let fileName: String = UUID().uuidString
    public let mimeType: String
    
    public init(data: Foundation.Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}
"""


let targetTypeResponseCode =
"""

\(genAccessLevel) enum ResponseDecodeError: Error {
    case unknowCode
}

\(genAccessLevel) protocol TargetTypeResponse: TargetType {
    func decodeResponse(_ response: Moya.Response) throws -> Any
}
"""


let serverFile =
"""
\(genFilePrefix)
import Alamofire

public final class Server<Target: ApiController> {
    private let baseURL: URL
    private let sessionManager: AuthorizedSessionManager

    public init(baseURL: URL, accessToken: String?) {
        self.baseURL = baseURL
        self.sessionManager = AuthorizedSessionManager(accessToken: accessToken)
    }

    // MARK: - Async requests

    @discardableResult
    public func request<DataType: Decodable>(_ target: Target,
                                               callbackQueue: DispatchQueue? = .none,
                                               completion: @escaping (Swift.Result<DataType, Error>) -> Void) -> Request {
        let url = baseURL.appendingPathComponent(target.path)
        return sessionManager.request(url,
                                      method: target.method,
                                      parameters: target.parameters,
                                      encoding: target.encoding,
                                      headers: target.headers).validate(statusCode: 200...299).responseJSON { (response) in
            print(response)
            let result = Swift.Result<DataType, Error> {
                switch response.result {
                case .success:
                    do {
                        // swiftlint:disable force_unwrapping
                        if response.response?.statusCode == 204 {
                            return try JSONDecoder().decodeSafe(DataType.self, from: "{}".data(using: .utf16)!)
                        }
                        return try JSONDecoder().decodeSafe(DataType.self, from: response.data!)
                    } catch {
                        throw error
                    }
                case .failure(let error):
                    throw error
                }
            }
            completion(result)
        }
    }

    // MARK: - Sync request
    public func response<DataType: Decodable>(_ target: Target, callbackQueue: DispatchQueue? = .none) throws -> DataType {
        assert(Thread.isMainThread == false)

        var result: Swift.Result<DataType, Error>!
        let semaphore = DispatchSemaphore(value: 0)
        self.request(target, callbackQueue: callbackQueue) { (response: Swift.Result<DataType, Error>) in
            result = response
            semaphore.signal()
        }
        semaphore.wait()
        return try result.get()
    }
    
    // MARK: - Async upload

    public func uploadRequest<DataType: Decodable>(_ target: Target,
                                              file: FileValue,
                                              callbackQueue: DispatchQueue? = .none,
                                              completion: @escaping (Swift.Result<DataType, Error>) -> Void) {
        let url = baseURL.appendingPathComponent(target.path)
        sessionManager.upload(multipartFormData: { (multipartFormData) in
            multipartFormData.append(file.data, withName: "file", fileName: file.fileName, mimeType: file.mimeType)
        }, to: url, method: target.method, headers: target.headers) { uploadResult in
            switch uploadResult {
            case .success(let request, _, _):
                request.responseJSON { (response) in
                    let result = Swift.Result<DataType, Error> {
                        switch response.result {
                        case .success:
                            do {
                                // swiftlint:disable force_unwrapping
                                if response.response?.statusCode == 204 {
                                    return try JSONDecoder().decodeSafe(DataType.self, from: "{}".data(using: .utf16)!)
                                }
                                return try JSONDecoder().decodeSafe(DataType.self, from: response.data!)
                            } catch {
                                throw error
                            }
                        case .failure(let error):
                            throw error
                        }
                    }
                    completion(result)
                }
            case .failure(let error):
                let result = Swift.Result<DataType, Error> {
                    throw error
                }
                completion(result)
            }
        }
    }
    
    // MARK: - Sync upload
    public func upload<DataType: Decodable>(_ target: Target, file: FileValue, callbackQueue: DispatchQueue? = .none) throws -> DataType {
        assert(Thread.isMainThread == false)

        var result: Swift.Result<DataType, Error>!
        let semaphore = DispatchSemaphore(value: 0)
        self.uploadRequest(target, file: file) { (response: Swift.Result<DataType, Error>) in
            result = response
            semaphore.signal()
        }
        semaphore.wait()
        return try result.get()
    }
}

private enum TimeOutIntervals: Double {
    case `default` = 45.0
}

final class AuthorizedSessionManager: SessionManager {
    init(accessToken: String?) {
        let configuration: URLSessionConfiguration = .default
        configuration.httpAdditionalHeaders = SessionManager.defaultHTTPHeaders
        configuration.timeoutIntervalForRequest = TimeOutIntervals.default.rawValue

        super.init(configuration: configuration)
        self.adapter = AuthorizedHeadersAdapter(accessToken: accessToken)
    }
}

final class AuthorizedHeadersAdapter: RequestAdapter {
    private let accessToken: String?

    init(accessToken: String?) {
        self.accessToken = accessToken
    }

    func adapt(_ urlRequest: URLRequest) throws -> URLRequest {
        var urlRequest = urlRequest
        if let token = accessToken {
            urlRequest.setValue(token, forHTTPHeaderField: "Authorization")
        }
        return urlRequest
    }
}
"""
