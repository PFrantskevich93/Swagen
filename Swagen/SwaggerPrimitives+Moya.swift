//
//  SwaggerPrimitives+Moya.swift
//  Swagen
//
//  Created by Dmitriy Petrusevich on 9/29/19.
//  Copyright © 2019 Dmitriy Petrusevich. All rights reserved.
//

import Foundation

extension PropertyObject {
    var moyaFormDataString: String {
        let dataString: String
        switch type {
        case .file:
            dataString = "\(nameSwiftString).moyaFormData(name: \"\(nameSwiftString)\")"
        default:
            dataString = "MultipartFormData(provider: .data(String(describing: \(nameSwiftString)).data(using: .utf8)!), name: \"\(nameSwiftString)\")"
        }

        return required ? dataString : "\(nameSwiftString) == nil ? nil : \(dataString)"
    }
}

extension Operation {
    var caseName: String {
        return id.loweredFirstLetter.escaped
    }
    
    var pathComponent: Bool {
        return parameters.filter { $0.in == .path }.isEmpty == false
    }

    var caseDocumetation: String {
        let keys = responses.keys.sorted()
        var strings: [String] = []
        strings.append("\(indent)/// \(descriptionText ?? "")")
        strings.append("\(indent)/// - respones:")
        strings.append(contentsOf: keys.map { "\(indent)/// \(indent)- \($0): \(responses[$0]!.primitive.typeSwiftString)" })
        return strings.joined(separator: "\n")
    }

    var swiftEnum: String? {
        let enums = parameters.compactMap({ $0.swiftEnum })
        return enums.isEmpty ? nil : enums.joined(separator: "\n")
    }
    
    var sortedParameters: [OperationParameter] {
        return parameters.sorted {
            if $0.in == $1.in { return $0.nameSwiftString < $1.nameSwiftString}
            else { return $0.in.rawValue == $1.in.rawValue }
        }
    }
    
    var caseDeclaration: String {
        return parameters.isEmpty ? caseName : "\(caseName)(\(sortedParameters.map({ $0.nameTypeSwiftString }).joined(separator: ", ")))"
    }

    var funcDeclaration: String {
        return "\(caseName)(\(sortedParameters.map({ $0.nameTypeSwiftString }).joined(separator: ", ")))"
    }

    var caseUsage: String {
        return parameters.isEmpty ? caseName : "\(caseName)(\(sortedParameters.map({ "\($0.nameSwiftString): \($0.nameSwiftString)" }).joined(separator: ", ")))"
    }
    
    func caseWithParams(position: [ParameterPosition]) -> String {
        let needParams = parameters.contains(where: { position.contains($0.in) })
        return needParams == false ? caseName : "\(caseName)(\(sortedParameters.map({ position.contains($0.in) ? "let \($0.nameSwiftString)" : "_" }).joined(separator: ", ")))"
    }
    
    var needParams: Bool {
        return parameters.isEmpty == false
    }
        
    
    var encoding: String {
        let body = parameters.filter { $0.in == .body }
        let query = parameters.filter { $0.in == .query }
        let form = parameters.filter { $0.in == .formData }

        if form.isEmpty == false {
            return "JSONEncoding.default"
        } else if body.isEmpty && query.isEmpty {
            return "JSONEncoding.default"
        } else if body.count == 1, query.isEmpty {
            return "JSONEncoding.default"
        } else {
            return "URLEncoding.default"
        }
    }

    var moyaTaskHeaders: String {
        let header = parameters.filter { $0.in == .header }
        var headerStrings = header.map({ "(\"\($0.name)\", \($0.nameSwiftString))" })
        if let type = consumes.first {
            headerStrings.append("(\"Content-Type\", \"\(type)\")")
        }
        return headerStrings.isEmpty ? "nil" : "Dictionary<String, Any?>(dictionaryLiteral: \(headerStrings.joined(separator: ", "))).unoptString()"
    }

    var firstSuccessResponseType: String {
        if let key = responses.keys.sorted().first, let primitive = responses[key]?.primitive {
            return primitive.typeSwiftString
        } else {
            return "Void"
        }
    }
}
