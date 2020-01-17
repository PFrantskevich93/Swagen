//
//  SwaggerMoyaGenerator.swift
//  Swagen
//
//  Created by Dmitriy Petrusevich on 9/27/19.
//  Copyright © 2019 Dmitriy Petrusevich. All rights reserved.
//

import Foundation

class SwaggerMoyaGenerator {
    struct Options: OptionSet {
        let rawValue: Int

        static let internalLevel = Options(rawValue: 1 << 0)
        static let responseTypes = Options(rawValue: 1 << 1)
        static let customAuthorization = Options(rawValue: 1 << 2)
        static let moyaProvider = Options(rawValue: 1 << 3)
    }

    let processor: SwaggerProcessor
    let options: Options
    let outputFolder: URL
    let modelsFolder: URL
    let apisFolder: URL

    init(outputFolder: URL, processor: SwaggerProcessor, options: Options) {
        genAccessLevel = options.contains(.internalLevel) ? "internal" : "public"

        self.options = options
        self.outputFolder = outputFolder
        self.modelsFolder = outputFolder.appendingPathComponent("Models")
        self.apisFolder = outputFolder.appendingPathComponent("APIs")
        self.processor = processor
    }

    func run() {
        generateModels()
        generateAPI()
    }

    private func generateModels() {
        do {
            try? FileManager.default.removeItem(at: modelsFolder)
            try FileManager.default.createDirectory(at: modelsFolder, withIntermediateDirectories: true, attributes: nil)

            for (_, scheme) in processor.schemes {
                let fileURL = modelsFolder.appendingPathComponent("\(scheme.title.escaped).swift")
                let text = "\(genFilePrefix)\n\n\(scheme.swiftString)\n"
                try text.data(using: .utf8)?.write(to: fileURL)
            }
        } catch {
            print(error)
        }
    }

    private func generateAPI() {
        do {
            try? FileManager.default.removeItem(at: apisFolder)
            try FileManager.default.createDirectory(at: apisFolder, withIntermediateDirectories: true, attributes: nil)

            let utilsURL = outputFolder.appendingPathComponent("Utils.swift")
            try? FileManager.default.removeItem(at: utilsURL)
            
            let apiControllerURL = outputFolder.appendingPathComponent("ApiController.swift")
            try? FileManager.default.removeItem(at: apiControllerURL)

            if options.contains(.moyaProvider) {
                let fileURL = outputFolder.appendingPathComponent("Server.swift")
                try? FileManager.default.removeItem(at: fileURL)
                try serverFile.data(using: .utf8)?.write(to: fileURL)
            }

            var utilsStings = utilsFile
            if options.contains(.responseTypes) {
                utilsStings.append(contentsOf: targetTypeResponseCode)
            }
            
            let apiStrings = apiControllerFile

            try utilsStings.data(using: .utf8)?.write(to: utilsURL)
            try apiStrings.data(using: .utf8)?.write(to: apiControllerURL)
        
            for (tag, ops) in processor.operationsByTag {
                let name = tag.capitalized.replacingOccurrences(of: "-", with: "") + "API"
                let fileURL = apisFolder.appendingPathComponent("\(name).swift")

                let sorted = ops.sorted(by: { $0.id < $1.id })
                let defenition = apiDefenition(name: name, operations: sorted)

                let text = "\(genFilePrefix)\nimport Alamofire\n\n\(defenition)"
                try text.data(using: .utf8)?.write(to: fileURL)
            }
        } catch {
            print(error)
        }
    }

    private func apiDefenition(name: String, operations: [Operation]) -> String {
        var strings: [String] = []
        
//        let caseReturn = "\n\(indent)\(indent)\(indent)return"
        let caseReturn = " return"
        
        // Defenition
        strings.append("\(genAccessLevel) enum \(name) {")
        strings.append(operations.map({ "\($0.caseDocumetation)\n\(indent)case \($0.caseDeclaration)" }).joined(separator: "\n\n"))
        strings.append("}")
        strings.append("")
        
        // Paths
        strings.append("extension \(name): ApiController {")
        strings.append("\(indent)\(genAccessLevel) var path: String {")
        strings.append("\(indent)\(indent)switch self {")
        strings.append(contentsOf: operations.map({
            var string = "\(indent)\(indent)case .\($0.caseWithParams(position: [.path]))"
            string += ": return "
            string += "\""
            var path = $0.path
            let params = $0.sortedParameters.filter { $0.in == .path }
            for param in params {
                path =  path.replacingOccurrences(of: "{\(param.nameSwiftString)}", with: "\\(\(param.nameSwiftString))")
            }
            string += path
            string += "\""
            
           return string
            
        }))
        strings.append("\(indent)\(indent)}")
        strings.append("\(indent)}")
        strings.append("")
        
        // RequestsneedParams
        strings.append("\(indent)\(genAccessLevel) var headers: HTTPHeaders? {")
        strings.append("\(indent)\(indent)switch self {")
        strings.append(contentsOf: operations.map({ "\(indent)\(indent)case .\($0.caseWithParams(position: [.header])):\(caseReturn) nil" }))
        strings.append("\(indent)\(indent)}")
        strings.append("\(indent)}")
        strings.append("")
        
        strings.append("\(indent)\(genAccessLevel) var method: HTTPMethod {")
        strings.append("\(indent)\(indent)switch self {")
        strings.append(contentsOf: operations.map({ "\(indent)\(indent)case .\($0.caseName): return .\($0.method.lowercased())" }))
        strings.append("\(indent)\(indent)}")
        strings.append("\(indent)}")
        strings.append("")
        
        strings.append("\(indent)\(genAccessLevel) var parameters: [String: Any]? {")
        strings.append("\(indent)\(indent)switch self {")
        strings.append(contentsOf: operations.map({
            var str = "\(indent)\(indent)case .\($0.caseWithParams(position: [.body, .query, .formData])):"
            if $0.sortedParameters.contains(where: { (operation) -> Bool in return operation.in == .body }) {
                str += "\(caseReturn) req.dictionary"
            } else if $0.sortedParameters.contains(where: { (operation) -> Bool in return operation.in == .query }) {
                 str += "\n             var params = [String: Any]()"
                for operation in $0.sortedParameters.filter({ $0.in == .query }) {
                    str += "\n             params[\"\(operation.nameSwiftString)\"] = \(operation.nameSwiftString)"
                }
                str += "\n            \(caseReturn) params"
            } else {
                str += "\(caseReturn) nil"
            }
            return str
        }))
        strings.append("\(indent)\(indent)}")
        strings.append("\(indent)}")
        strings.append("")
        
        strings.append("\(indent)\(genAccessLevel) var encoding: ParameterEncoding {")
        strings.append("\(indent)\(indent)switch self {")
        strings.append(contentsOf: operations.map({ "\(indent)\(indent)case .\($0.caseName):\(caseReturn) \($0.encoding)" }))
        strings.append("\(indent)\(indent)}")
        strings.append("\(indent)}")
        strings.append("}")

        return strings.joined(separator: "\n")
    }
}
