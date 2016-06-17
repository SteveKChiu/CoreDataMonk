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
    let predicate: Predicate
    
    private init(_ predicate: Predicate) {
        self.predicate = predicate
    }
    
    public static func `where`(_ format: String, _ args: AnyObject...) -> CoreDataQuery {
        return CoreDataQuery(Predicate(format: format, argumentArray: args))
    }

    public static func `where`(_ predicate: Predicate) -> CoreDataQuery {
        return CoreDataQuery(predicate)
    }
}

public func && (lhs: CoreDataQuery, rhs: CoreDataQuery) -> CoreDataQuery {
    return .where(CompoundPredicate(type: .and, subpredicates: [ lhs.predicate, rhs.predicate ]))
}

public func || (lhs: CoreDataQuery, rhs: CoreDataQuery) -> CoreDataQuery {
    return .where(CompoundPredicate(type: .or, subpredicates: [ lhs.predicate, rhs.predicate ]))
}

public prefix func ! (lhs: CoreDataQuery) -> CoreDataQuery {
    return .where(CompoundPredicate(type: .not, subpredicates: [ lhs.predicate ]))
}

//---------------------------------------------------------------------------

public enum CoreDataQueryKey {
    case key(String)
    case keyModifier(String, ComparisonPredicate.Modifier)
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

    var modifier: ComparisonPredicate.Modifier {
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
    
    private func compare(_ op: ComparisonPredicate.Operator, _ key: CoreDataQueryKey) -> CoreDataQuery {
        return .where(ComparisonPredicate(
                leftExpression: NSExpression(forKeyPath: self.path),
                rightExpression: NSExpression(forKeyPath: key.path),
                modifier: self.modifier,
                type: op,
                options: []))
    }

    private func compare(_ op: ComparisonPredicate.Operator, _ value: AnyObject) -> CoreDataQuery {
        return .where(ComparisonPredicate(
                leftExpression: NSExpression(forKeyPath: self.path),
                rightExpression: NSExpression(forConstantValue: value),
                modifier: self.modifier,
                type: op,
                options: []))
    }
}

prefix operator % {}

postfix operator % {}

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
    let rhs = rhs == nil ? NSNull() : asConstant(rhs!)
    return lhs.compare(.equalTo, rhs)
}

public func == (lhs: CoreDataQueryKey, rhs: CoreDataQueryKey) -> CoreDataQuery {
    return lhs.compare(.equalTo, rhs)
}

public func != (lhs: CoreDataQueryKey, rhs: Any?) -> CoreDataQuery {
    let rhs = rhs == nil ? NSNull() : asConstant(rhs!)
    return lhs.compare(.notEqualTo, rhs)
}

public func != (lhs: CoreDataQueryKey, rhs: CoreDataQueryKey) -> CoreDataQuery {
    return lhs.compare(.notEqualTo, rhs)
}

public func > (lhs: CoreDataQueryKey, rhs: Any) -> CoreDataQuery {
    let rhs = asConstant(rhs)
    return lhs.compare(.greaterThan, rhs)
}

public func > (lhs: CoreDataQueryKey, rhs: CoreDataQueryKey) -> CoreDataQuery {
    return lhs.compare(.greaterThan, rhs)
}

public func < (lhs: CoreDataQueryKey, rhs: Any) -> CoreDataQuery {
    let rhs = asConstant(rhs)
    return lhs.compare(.lessThan, rhs)
}

public func < (lhs: CoreDataQueryKey, rhs: CoreDataQueryKey) -> CoreDataQuery {
    return lhs.compare(.lessThan, rhs)
}

public func >= (lhs: CoreDataQueryKey, rhs: Any) -> CoreDataQuery {
    let rhs = asConstant(rhs)
    return lhs.compare(.greaterThanOrEqualTo, rhs)
}

public func >= (lhs: CoreDataQueryKey, rhs: CoreDataQueryKey) -> CoreDataQuery {
    return lhs.compare(.greaterThanOrEqualTo, rhs)
}

public func <= (lhs: CoreDataQueryKey, rhs: Any) -> CoreDataQuery {
    let rhs = asConstant(rhs)
    return lhs.compare(.lessThanOrEqualTo, rhs)
}

public func <= (lhs: CoreDataQueryKey, rhs: CoreDataQueryKey) -> CoreDataQuery {
    return lhs.compare(.lessThanOrEqualTo, rhs)
}

private func asConstant(_ value: Any) -> AnyObject {
    // String, Bool, Int, Float, Double can be casted to AnyObject implicitly
    if let value = value as? AnyObject {
        return value
    }
    
    // Need to convert these Intxx/UIntxx types explicitly
    if let value = value as? Int64 {
        return NSNumber(value: value)
    }
    if let value = value as? UInt64 {
        return NSNumber(value: value)
    }
    if let value = value as? Int32 {
        return NSNumber(value: value)
    }
    if let value = value as? UInt32 {
        return NSNumber(value: value)
    }
    if let value = value as? Int16 {
        return NSNumber(value: value)
    }
    if let value = value as? UInt16 {
        return NSNumber(value: value)
    }
    if let value = value as? Int8 {
        return NSNumber(value: value)
    }
    if let value = value as? UInt8 {
        return NSNumber(value: value)
    }
    
    fatalError("\(value) can not be converted to CoreData constant value")
}

//---------------------------------------------------------------------------

public struct CoreDataSelect {
    private let descriptions: [AnyObject]
    
    private init(_ expression: AnyObject) {
        self.descriptions = [ expression ]
    }

    private init(_ expressions: [AnyObject]) {
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
            let next = key.substring(from: r.upperBound)
            
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
    
    func resolve(_ entity: NSEntityDescription) throws -> [AnyObject] {
        var properties = [AnyObject]()
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
                guard let argument = expression.arguments?.first where argument.expressionType == .keyPath else {
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
    let descriptors: [SortDescriptor]
    
    private init(_ descriptor: SortDescriptor) {
        self.descriptors = [ descriptor ]
    }

    private init(_ descriptors: [SortDescriptor]) {
        self.descriptors = descriptors
    }
    
    public static func Ascending(_ key: String) -> CoreDataOrderBy {
        return CoreDataOrderBy(SortDescriptor(key: key, ascending: true))
    }

    public static func Ascending(_ key: String, selector: Selector) -> CoreDataOrderBy {
        return CoreDataOrderBy(SortDescriptor(key: key, ascending: true, selector: selector))
    }
    
    public static func Descending(_ key: String) -> CoreDataOrderBy {
        return CoreDataOrderBy(SortDescriptor(key: key, ascending: false))
    }

    public static func Descending(_ key: String, selector: Selector) -> CoreDataOrderBy {
        return CoreDataOrderBy(SortDescriptor(key: key, ascending: false, selector: selector))
    }

    public static func Sort(_ descriptor: SortDescriptor) -> CoreDataOrderBy {
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
    case multiple([CoreDataQueryOptions])

    private var options: [CoreDataQueryOptions] {
        switch self {
        case let .multiple(list):
            return list
            
        default:
            return [ self ]
        }
    }

    func apply<T: NSFetchRequestResult>(_ request: NSFetchRequest<T>) throws {
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
