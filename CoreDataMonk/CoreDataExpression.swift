//
// https://github.com/SteveKChiu/CoreDataMonk
//
// Copyright 2015, Steve K. Chiu <steve.k.chiu@gmail.com>
//
// The MIT License (http://www.opensource.org/licenses/mit-license.php)
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the "Software"),
// to deal in the Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.
//

import CoreData

//---------------------------------------------------------------------------

public struct CoreDataQuery {
    let predicate: NSPredicate
    
    private init(_ predicate: NSPredicate) {
        self.predicate = predicate
    }
    
    public static func Where(_ format: String, _ args: Any...) -> CoreDataQuery {
        return CoreDataQuery(NSPredicate(format: format, argumentArray: args))
    }

    public static func Where(_ predicate: NSPredicate) -> CoreDataQuery {
        return CoreDataQuery(predicate)
    }
}

public func && (lhs: CoreDataQuery, rhs: CoreDataQuery) -> CoreDataQuery {
    return .Where(NSCompoundPredicate(type: .and, subpredicates: [ lhs.predicate, rhs.predicate ]))
}

public func || (lhs: CoreDataQuery, rhs: CoreDataQuery) -> CoreDataQuery {
    return .Where(NSCompoundPredicate(type: .or, subpredicates: [ lhs.predicate, rhs.predicate ]))
}

public prefix func ! (lhs: CoreDataQuery) -> CoreDataQuery {
    return .Where(NSCompoundPredicate(type: .not, subpredicates: [ lhs.predicate ]))
}

//---------------------------------------------------------------------------

public enum CoreDataQueryKey {
    case key(String)
    case keyModifier(String, NSComparisonPredicate.Modifier)
    case keyPath([String])
    
    var path: String {
        switch self {
        case let .key(path):
            return path
            
        case let .keyModifier(path, _):
            return path

        case let .keyPath(list):
            var path = list.first!
            for item in list[1 ..< list.count] {
                path += "."
                path += item
            }
            return path
        }
    }

    var modifier: NSComparisonPredicate.Modifier {
        switch self {
        case let .keyModifier(_, mod):
            return mod

        default:
            return .direct
        }
    }
    
    var list: [String] {
        switch self {
        case let .key(path):
            return [ path ]
            
        case let .keyModifier(path, _):
            return [ path ]

        case let .keyPath(list):
            return list
        }
    }
    
    public var any: CoreDataQueryKey {
        return .keyModifier(self.path, .any)
    }
    
    public var all: CoreDataQueryKey {
        return .keyModifier(self.path, .all)
    }
    
    fileprivate func compare(_ op: NSComparisonPredicate.Operator, _ key: CoreDataQueryKey) -> CoreDataQuery {
        return .Where(NSComparisonPredicate(
                leftExpression: NSExpression(forKeyPath: self.path),
                rightExpression: NSExpression(forKeyPath: key.path),
                modifier: self.modifier,
                type: op,
                options: []))
    }

    fileprivate func compare(_ op: NSComparisonPredicate.Operator, _ value: Any) -> CoreDataQuery {
        return .Where(NSComparisonPredicate(
                leftExpression: NSExpression(forKeyPath: self.path),
                rightExpression: NSExpression(forConstantValue: value),
                modifier: self.modifier,
                type: op,
                options: []))
    }
}

prefix operator %

postfix operator %

public prefix func % (key: CoreDataQueryKey) -> CoreDataQueryKey {
    return key
}

public prefix func % (name: String) -> CoreDataQueryKey {
    return CoreDataQueryKey.key(name)
}

public postfix func % (name: String) -> CoreDataQueryKey {
    return CoreDataQueryKey.key(name)
}

public func | (lhs: CoreDataQueryKey, rhs: CoreDataQueryKey) -> CoreDataQueryKey {
    return .keyPath(lhs.list + rhs.list)
}

public func == (lhs: CoreDataQueryKey, rhs: Any?) -> CoreDataQuery {
    return lhs.compare(.equalTo, rhs ?? NSNull())
}

public func == (lhs: CoreDataQueryKey, rhs: CoreDataQueryKey) -> CoreDataQuery {
    return lhs.compare(.equalTo, rhs)
}

public func != (lhs: CoreDataQueryKey, rhs: Any?) -> CoreDataQuery {
    return lhs.compare(.notEqualTo, rhs ?? NSNull())
}

public func != (lhs: CoreDataQueryKey, rhs: CoreDataQueryKey) -> CoreDataQuery {
    return lhs.compare(.notEqualTo, rhs)
}

public func > (lhs: CoreDataQueryKey, rhs: Any) -> CoreDataQuery {
    return lhs.compare(.greaterThan, rhs)
}

public func > (lhs: CoreDataQueryKey, rhs: CoreDataQueryKey) -> CoreDataQuery {
    return lhs.compare(.greaterThan, rhs)
}

public func < (lhs: CoreDataQueryKey, rhs: Any) -> CoreDataQuery {
    return lhs.compare(.lessThan, rhs)
}

public func < (lhs: CoreDataQueryKey, rhs: CoreDataQueryKey) -> CoreDataQuery {
    return lhs.compare(.lessThan, rhs)
}

public func >= (lhs: CoreDataQueryKey, rhs: Any) -> CoreDataQuery {
    return lhs.compare(.greaterThanOrEqualTo, rhs)
}

public func >= (lhs: CoreDataQueryKey, rhs: CoreDataQueryKey) -> CoreDataQuery {
    return lhs.compare(.greaterThanOrEqualTo, rhs)
}

public func <= (lhs: CoreDataQueryKey, rhs: Any) -> CoreDataQuery {
    return lhs.compare(.lessThanOrEqualTo, rhs)
}

public func <= (lhs: CoreDataQueryKey, rhs: CoreDataQueryKey) -> CoreDataQuery {
    return lhs.compare(.lessThanOrEqualTo, rhs)
}

//---------------------------------------------------------------------------

public struct CoreDataSelect {
    fileprivate let descriptions: [Any]
    
    fileprivate init(_ expression: Any) {
        self.descriptions = [ expression ]
    }

    fileprivate init(_ expressions: [Any]) {
        self.descriptions = expressions
    }

    private init(function: String, property: String, alias: String?, type: NSAttributeType) {
        let key = NSExpression(forKeyPath: property)
        let expression = NSExpression(forFunction: function, arguments: [ key ])
        let description = NSExpressionDescription()
        description.name = alias ?? property
        description.expression = expression
        description.expressionResultType = type
        self.descriptions = [ description ]
    }
    
    public static func Select(_ keys: String...) -> CoreDataSelect {
        return CoreDataSelect(keys)
    }
    
    public static func Expression(_ expression: NSExpressionDescription) -> CoreDataSelect {
        return CoreDataSelect(expression)
    }
    
    public static func Sum(_ property: String, alias: String? = nil) -> CoreDataSelect {
        return CoreDataSelect(function: "sum:", property: property, alias: alias, type: .decimalAttributeType)
    }
    
    public static func Average(_ property: String, alias: String? = nil) -> CoreDataSelect {
        return CoreDataSelect(function: "average:", property: property, alias: alias, type: .decimalAttributeType)
    }

    public static func StdDev(_ property: String, alias: String? = nil) -> CoreDataSelect {
        return CoreDataSelect(function: "stddev:", property: property, alias: alias, type: .decimalAttributeType)
    }

    public static func Count(_ property: String, alias: String? = nil) -> CoreDataSelect {
        return CoreDataSelect(function: "count:", property: property, alias: alias, type: .integer64AttributeType)
    }

    public static func Max(_ property: String, alias: String? = nil) -> CoreDataSelect {
        return CoreDataSelect(function: "max:", property: property, alias: alias, type: .undefinedAttributeType)
    }

    public static func Min(_ property: String, alias: String? = nil) -> CoreDataSelect {
        return CoreDataSelect(function: "min:", property: property, alias: alias, type: .undefinedAttributeType)
    }

    public static func Median(_ property: String, alias: String? = nil) -> CoreDataSelect {
        return CoreDataSelect(function: "median:", property: property, alias: alias, type: .undefinedAttributeType)
    }
    
    private func keyPathResultType(_ key: String, entity: NSEntityDescription) throws -> NSAttributeType {
        if let r = key.range(of: ".") {
            let name = key.substring(to: r.lowerBound)
            let next = key.substring(from: key.index(after: r.lowerBound))
            
            guard let relate = entity.relationshipsByName[name]?.destinationEntity else {
                throw CoreDataError("Can not find relationship [\(name)] of [\(entity.name)]")
            }
            return try keyPathResultType(next, entity: relate)
        }
    
        guard let attr = entity.attributesByName[key] else {
            throw CoreDataError("Can not find attribute [\(key)] of [\(entity.name)]")
        }
        return attr.attributeType
    }
    
    func resolve(_ entity: NSEntityDescription) throws -> [Any] {
        var properties = [Any]()
        for unknownDescription in self.descriptions {
            if unknownDescription is String {
                properties.append(unknownDescription)
                continue
            }
            
            guard let description = unknownDescription as? NSExpressionDescription else {
                throw CoreDataError("Can not resolve property \(unknownDescription)")
            }
            
            guard description.expressionResultType == .undefinedAttributeType else {
                properties.append(description)
                continue
            }
            
            let expression = description.expression!
            switch expression.expressionType {
            case .keyPath:
                properties.append(expression.keyPath)
                
            case .function:
                guard let argument = expression.arguments?.first, argument.expressionType == .keyPath else {
                    throw CoreDataError("Can not resolve function result type unless its argument is key path: \(expression)")
                }
                description.expressionResultType = try keyPathResultType(argument.keyPath, entity: entity)
                properties.append(description)
            
            default:
                throw CoreDataError("Can not resolve result type of expression: \(expression)")
            }
        }
        return properties
    }
}

public func | (lhs: CoreDataSelect, rhs: CoreDataSelect) -> CoreDataSelect {
    return CoreDataSelect(lhs.descriptions + rhs.descriptions)
}

//---------------------------------------------------------------------------

public struct CoreDataOrderBy {
    let descriptors: [NSSortDescriptor]
    
    fileprivate init(_ descriptor: NSSortDescriptor) {
        self.descriptors = [ descriptor ]
    }

    fileprivate init(_ descriptors: [NSSortDescriptor]) {
        self.descriptors = descriptors
    }
    
    public static func Ascending(_ key: String) -> CoreDataOrderBy {
        return CoreDataOrderBy(NSSortDescriptor(key: key, ascending: true))
    }
    
    public static func Ascending(_ key: String, selector: Selector) -> CoreDataOrderBy {
        return CoreDataOrderBy(NSSortDescriptor(key: key, ascending: true, selector: selector))
    }
    
    public static func Descending(_ key: String) -> CoreDataOrderBy {
        return CoreDataOrderBy(NSSortDescriptor(key: key, ascending: false))
    }

    public static func Descending(_ key: String, selector: Selector) -> CoreDataOrderBy {
        return CoreDataOrderBy(NSSortDescriptor(key: key, ascending: false, selector: selector))
    }

    public static func Sort(_ descriptor: NSSortDescriptor) -> CoreDataOrderBy {
        return CoreDataOrderBy(descriptor)
    }
}

public func | (lhs: CoreDataOrderBy, rhs: CoreDataOrderBy) -> CoreDataOrderBy {
    return CoreDataOrderBy(lhs.descriptors + rhs.descriptors)
}

//---------------------------------------------------------------------------

public enum CoreDataQueryOptions {
    case noSubEntities
    case noPendingChanges
    case noPropertyValues
    case limit(Int)
    case offset(Int)
    case batch(Int)
    case prefetch([String])
    case propertiesOnly([String])
    case distinct
    case tweak((NSFetchRequest<NSFetchRequestResult>) -> Void)
    case multiple([CoreDataQueryOptions])

    fileprivate var options: [CoreDataQueryOptions] {
        switch self {
        case let .multiple(list):
            return list
            
        default:
            return [ self ]
        }
    }

    func apply(_ request: NSFetchRequest<NSFetchRequestResult>) throws {
        switch self {
        case .noSubEntities:
            request.includesSubentities = false
            
        case .noPendingChanges:
            request.includesPendingChanges = false
            
        case .noPropertyValues:
            request.includesPropertyValues = false

        case let .limit(limit):
            request.fetchLimit = limit
            
        case let .offset(offset):
            request.fetchOffset = offset
            
        case let .batch(size):
            request.fetchBatchSize = size
            
        case let .prefetch(keys):
            request.relationshipKeyPathsForPrefetching = keys
         
        case let .propertiesOnly(keys):
            if request.resultType == NSFetchRequestResultType() {
                request.propertiesToFetch = keys
            }
            
        case .distinct:
            request.returnsDistinctResults = true
            
        case let .tweak(tweak):
            tweak(request)
            
        case let .multiple(list):
            for option in list {
                try option.apply(request)
            }
        }
    }
}

public func | (lhs: CoreDataQueryOptions, rhs: CoreDataQueryOptions) -> CoreDataQueryOptions {
    return .multiple(lhs.options + rhs.options)
}
