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

import UIKit
import CoreData

//---------------------------------------------------------------------------

public struct CoreDataQuery {
    let predicate: NSPredicate
    
    private init(_ predicate: NSPredicate) {
        self.predicate = predicate
    }
    
    public static func Where(format: String, _ args: AnyObject...) -> CoreDataQuery {
        return CoreDataQuery(NSPredicate(format: format, argumentArray: args))
    }

    public static func Where(predicate: NSPredicate) -> CoreDataQuery {
        return CoreDataQuery(predicate)
    }
}

public func && (lhs: CoreDataQuery, rhs: CoreDataQuery) -> CoreDataQuery {
    return .Where(NSCompoundPredicate(type: .AndPredicateType, subpredicates: [ lhs.predicate, rhs.predicate ]))
}

public func || (lhs: CoreDataQuery, rhs: CoreDataQuery) -> CoreDataQuery {
    return .Where(NSCompoundPredicate(type: .OrPredicateType, subpredicates: [ lhs.predicate, rhs.predicate ]))
}

public prefix func ! (lhs: CoreDataQuery) -> CoreDataQuery {
    return .Where(NSCompoundPredicate(type: .NotPredicateType, subpredicates: [ lhs.predicate ]))
}

//---------------------------------------------------------------------------

public enum CoreDataQueryKey {
    case Key(String)
    case KeyModifier(String, NSComparisonPredicateModifier)
    case KeyPath([String])
    
    var path: String {
        switch self {
        case let .Key(path):
            return path
            
        case let .KeyModifier(path, _):
            return path

        case let .KeyPath(list):
            var path = list.first!
            for item in list[1 ..< list.count] {
                path += "."
                path += item
            }
            return path
        }
    }

    var modifier: NSComparisonPredicateModifier {
        switch self {
        case let .KeyModifier(_, mod):
            return mod

        default:
            return .DirectPredicateModifier
        }
    }
    
    var list: [String] {
        switch self {
        case let .Key(path):
            return [ path ]
            
        case let .KeyModifier(path, _):
            return [ path ]

        case let .KeyPath(list):
            return list
        }
    }
    
    public var any: CoreDataQueryKey {
        return .KeyModifier(self.path, .AllPredicateModifier)
    }
    
    public var all: CoreDataQueryKey {
        return .KeyModifier(self.path, .AnyPredicateModifier)
    }
    
    private func compare(op: NSPredicateOperatorType, _ key: CoreDataQueryKey) -> CoreDataQuery {
        return .Where(NSComparisonPredicate(
                leftExpression: NSExpression(forKeyPath: self.path),
                rightExpression: NSExpression(forKeyPath: key.path),
                modifier: self.modifier,
                type: op,
                options: []))
    }

    private func compare(op: NSPredicateOperatorType, _ value: AnyObject) -> CoreDataQuery {
        return .Where(NSComparisonPredicate(
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
    return CoreDataQueryKey.Key(name)
}

public postfix func % (name: String) -> CoreDataQueryKey {
    return CoreDataQueryKey.Key(name)
}

public func | (lhs: CoreDataQueryKey, rhs: CoreDataQueryKey) -> CoreDataQueryKey {
    return .KeyPath(lhs.list + rhs.list)
}

public func == (lhs: CoreDataQueryKey, rhs: Any?) -> CoreDataQuery {
    return lhs.compare(.EqualToPredicateOperatorType, (rhs ??  NSNull()) as! AnyObject)
}

public func == (lhs: CoreDataQueryKey, rhs: CoreDataQueryKey) -> CoreDataQuery {
    return lhs.compare(.EqualToPredicateOperatorType, rhs)
}

public func != (lhs: CoreDataQueryKey, rhs: Any?) -> CoreDataQuery {
    return lhs.compare(.NotEqualToPredicateOperatorType, (rhs ??  NSNull()) as! AnyObject)
}

public func != (lhs: CoreDataQueryKey, rhs: CoreDataQueryKey) -> CoreDataQuery {
    return lhs.compare(.NotEqualToPredicateOperatorType, rhs)
}

public func > (lhs: CoreDataQueryKey, rhs: Any) -> CoreDataQuery {
    return lhs.compare(.GreaterThanPredicateOperatorType, rhs as! AnyObject)
}

public func > (lhs: CoreDataQueryKey, rhs: CoreDataQueryKey) -> CoreDataQuery {
    return lhs.compare(.GreaterThanPredicateOperatorType, rhs)
}

public func < (lhs: CoreDataQueryKey, rhs: Any) -> CoreDataQuery {
    return lhs.compare(.LessThanPredicateOperatorType, rhs as! AnyObject)
}

public func < (lhs: CoreDataQueryKey, rhs: CoreDataQueryKey) -> CoreDataQuery {
    return lhs.compare(.LessThanPredicateOperatorType, rhs)
}

public func >= (lhs: CoreDataQueryKey, rhs: Any) -> CoreDataQuery {
    return lhs.compare(.GreaterThanOrEqualToPredicateOperatorType, rhs as! AnyObject)
}

public func >= (lhs: CoreDataQueryKey, rhs: CoreDataQueryKey) -> CoreDataQuery {
    return lhs.compare(.GreaterThanOrEqualToPredicateOperatorType, rhs)
}

public func <= (lhs: CoreDataQueryKey, rhs: Any) -> CoreDataQuery {
    return lhs.compare(.LessThanOrEqualToPredicateOperatorType, rhs as! AnyObject)
}

public func <= (lhs: CoreDataQueryKey, rhs: CoreDataQueryKey) -> CoreDataQuery {
    return lhs.compare(.LessThanOrEqualToPredicateOperatorType, rhs)
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
    
    public static func Select(keys: String...) -> CoreDataSelect {
        return CoreDataSelect(keys)
    }
    
    public static func Expression(expression: NSExpressionDescription) -> CoreDataSelect {
        return CoreDataSelect(expression)
    }
    
    public static func Sum(property: String, alias: String? = nil) -> CoreDataSelect {
        return CoreDataSelect(function: "sum:", property: property, alias: alias, type: .DecimalAttributeType)
    }
    
    public static func Average(property: String, alias: String? = nil) -> CoreDataSelect {
        return CoreDataSelect(function: "average:", property: property, alias: alias, type: .DecimalAttributeType)
    }

    public static func StdDev(property: String, alias: String? = nil) -> CoreDataSelect {
        return CoreDataSelect(function: "stddev:", property: property, alias: alias, type: .DecimalAttributeType)
    }

    public static func Count(property: String, alias: String? = nil) -> CoreDataSelect {
        return CoreDataSelect(function: "count:", property: property, alias: alias, type: .Integer64AttributeType)
    }

    public static func Max(property: String, alias: String? = nil) -> CoreDataSelect {
        return CoreDataSelect(function: "max:", property: property, alias: alias, type: .UndefinedAttributeType)
    }

    public static func Min(property: String, alias: String? = nil) -> CoreDataSelect {
        return CoreDataSelect(function: "min:", property: property, alias: alias, type: .UndefinedAttributeType)
    }

    public static func Median(property: String, alias: String? = nil) -> CoreDataSelect {
        return CoreDataSelect(function: "median:", property: property, alias: alias, type: .UndefinedAttributeType)
    }
    
    private func keyPathResultType(key: String, entity: NSEntityDescription) throws -> NSAttributeType {
        if let r = key.rangeOfString(".") {
            let name = key.substringToIndex(r.startIndex)
            let next = key.substringFromIndex(r.startIndex.successor())
            
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
    
    func resolve(entity: NSEntityDescription) throws -> [AnyObject] {
        var properties = [AnyObject]()
        for unknownDescription in self.descriptions {
            if unknownDescription is String {
                properties.append(unknownDescription)
                continue
            }
            
            guard let description = unknownDescription as? NSExpressionDescription else {
                throw CoreDataError("Can not resolve property \(unknownDescription)")
            }
            
            guard description.expressionResultType == .UndefinedAttributeType else {
                properties.append(description)
                continue
            }
            
            let expression = description.expression!
            switch expression.expressionType {
            case .KeyPathExpressionType:
                properties.append(expression.keyPath)
                
            case .FunctionExpressionType:
                guard let argument = expression.arguments?.first where argument.expressionType == .KeyPathExpressionType else {
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
    
    private init(_ descriptor: NSSortDescriptor) {
        self.descriptors = [ descriptor ]
    }

    private init(_ descriptors: [NSSortDescriptor]) {
        self.descriptors = descriptors
    }
    
    public static func Ascending(key: String) -> CoreDataOrderBy {
        return CoreDataOrderBy(NSSortDescriptor(key: key, ascending: true))
    }
    
    public static func Descending(key: String) -> CoreDataOrderBy {
        return CoreDataOrderBy(NSSortDescriptor(key: key, ascending: false))
    }

    public static func OrderBy(descriptor: NSSortDescriptor) -> CoreDataOrderBy {
        return CoreDataOrderBy(descriptor)
    }
}

public func | (lhs: CoreDataOrderBy, rhs: CoreDataOrderBy) -> CoreDataOrderBy {
    return CoreDataOrderBy(lhs.descriptors + rhs.descriptors)
}

//---------------------------------------------------------------------------

public enum CoreDataQueryOptions {
    case NoSubEntities
    case NoPendingChanges
    case NoPropertyValues
    case Limit(Int)
    case Offset(Int)
    case Batch(Int)
    case Prefetch([String])
    case PropertiesOnly([String])
    case Distinct
    case Tweak(NSFetchRequest -> Void)
    case Multiple([CoreDataQueryOptions])

    private var options: [CoreDataQueryOptions] {
        switch self {
        case let .Multiple(list):
            return list
            
        default:
            return [ self ]
        }
    }

    func apply(request: NSFetchRequest) throws {
        switch self {
        case .NoSubEntities:
            request.includesSubentities = false
            
        case .NoPendingChanges:
            request.includesPendingChanges = false
            
        case .NoPropertyValues:
            request.includesPropertyValues = false

        case let .Limit(limit):
            request.fetchLimit = limit
            
        case let .Offset(offset):
            request.fetchOffset = offset
            
        case let .Batch(size):
            request.fetchBatchSize = size
            
        case let .Prefetch(keys):
            request.relationshipKeyPathsForPrefetching = keys
         
        case let .PropertiesOnly(keys):
            if request.resultType == .ManagedObjectResultType {
                request.propertiesToFetch = keys
            }
            
        case .Distinct:
            request.returnsDistinctResults = true
            
        case let .Tweak(tweak):
            tweak(request)
            
        case let .Multiple(list):
            for option in list {
                try option.apply(request)
            }
        }
    }
}

public func | (lhs: CoreDataQueryOptions, rhs: CoreDataQueryOptions) -> CoreDataQueryOptions {
    return .Multiple(lhs.options + rhs.options)
}
