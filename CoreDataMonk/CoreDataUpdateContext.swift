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

public class CoreDataUpdateContext {
    let context: NSManagedObjectContext
    let origin: CoreDataContext
    let autoMerge: Bool
    
    init(context: NSManagedObjectContext, origin: CoreDataContext, autoMerge: Bool) {
        self.context = context
        self.origin = origin
        self.autoMerge = autoMerge
    }

    public final var managedObjectContext: NSManagedObjectContext {
        return self.context
    }

    public final func handleError(error: ErrorType) {
        self.origin.stack.handleError(error)
    }
    
    public func perform(block: (CoreDataUpdate) throws -> Void) {
        if let queue = self.origin.updateQueue {
            dispatch_async(queue) {
                let group = dispatch_group_create()
                dispatch_group_enter(group)
                self.context.performBlock() {
                    let update = CoreDataUpdate(context: self, group: group)
                    do {
                        try block(update)
                    } catch {
                        self.handleError(error)
                    }
                    dispatch_group_leave(group)
                }
                dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
            }
        } else {
            self.context.performBlock() {
                let update = CoreDataUpdate(context: self, group: nil)
                do {
                    try block(update)
                } catch {
                    self.handleError(error)
                }
            }
        }
    }

    public func performAndWait(block: (CoreDataUpdate) throws -> Void) {
        if let queue = self.origin.updateQueue {
            dispatch_sync(queue) {
                let group = dispatch_group_create()
                dispatch_group_enter(group)
                self.context.performBlock() {
                    let update = CoreDataUpdate(context: self, group: group)
                    do {
                        try block(update)
                    } catch {
                        self.handleError(error)
                    }
                    dispatch_group_leave(group)
                }
                dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
            }
        } else {
            self.context.performBlockAndWait() {
                let update = CoreDataUpdate(context: self, group: nil)
                do {
                    try block(update)
                } catch {
                    self.handleError(error)
                }
            }
        }
    }
    
    public func wait() {
        if let queue = self.origin.updateQueue {
            dispatch_sync(queue) {
                // do nothing
            }
        } else {
            self.context.performBlockAndWait() {
                // do nothing
            }
        }
    }

    public func commit() {
        perform() {
            update in
            
            try update.commit()
        }
    }
    
    public func rollback() {
        perform() {
            update in
            
            update.rollback()
        }
    }
}

//---------------------------------------------------------------------------

public class CoreDataUpdate : CoreDataFetch {
    public let context: CoreDataUpdateContext
    let group: dispatch_group_t?
    
    init(context: CoreDataUpdateContext, group: dispatch_group_t?) {
        self.context = context
        self.group = group

        if let group = self.group {
            dispatch_group_enter(group)
        }
    }
    
    deinit {
        if let group = self.group {
            dispatch_group_leave(group)
        }
    }

    public final var managedObjectContext: NSManagedObjectContext {
        return self.context.context
    }
    
    public final func metadataForEntityClass(type: NSManagedObject.Type) throws -> (entity: NSEntityDescription, store: NSPersistentStore) {
        return try self.context.origin.metadataForEntityClass(type)
    }

    public func create<T: NSManagedObject>(type: T.Type) throws -> T {
        let meta = try self.metadataForEntityClass(type)
        let obj = T(entity: meta.entity, insertIntoManagedObjectContext: self.managedObjectContext)
        self.managedObjectContext.assignObject(obj, toPersistentStore: meta.store)
        return obj
    }

    private func applyProperties(obj: NSManagedObject, predicate: NSPredicate) throws {
        if let comp = predicate as? NSComparisonPredicate {
            guard comp.predicateOperatorType == .EqualToPredicateOperatorType else {
                throw CoreDataError("fetchOrCreate: only == and && are supported")
            }
            
            guard comp.leftExpression.expressionType == .KeyPathExpressionType else {
                throw CoreDataError("fetchOrCreate: left hand side of == must be key path")
            }
            
            switch comp.rightExpression.expressionType {
            case .KeyPathExpressionType:
                let value = obj.valueForKeyPath(comp.rightExpression.keyPath)
                obj.setValue(value, forKeyPath: comp.leftExpression.keyPath)
                
            case .ConstantValueExpressionType:
                var value: AnyObject? = comp.rightExpression.constantValue
                value = value is NSNull ? nil : value
                obj.setValue(value, forKeyPath: comp.leftExpression.keyPath)
                
            default:
                throw CoreDataError("fetchOrCreate: right hand side of == must be key path or constant value")
            }
            return
        }
        
        if let comp = predicate as? NSCompoundPredicate {
            guard comp.compoundPredicateType == .AndPredicateType else {
                throw CoreDataError("fetchOrCreate: only == and && are supported")
            }
            
            try applyProperties(obj, predicate: comp.subpredicates[0] as! NSPredicate)
            try applyProperties(obj, predicate: comp.subpredicates[1] as! NSPredicate)
            return
        }
        
        throw CoreDataError("Only == and && are supported in fetchOrCreate")
    }

    public func fetchOrCreate<T: NSManagedObject>(type: T.Type, _ query: CoreDataQuery) throws -> T {
        do {
            return try fetch(type, query)
        } catch {
            let error = error as NSError
            if error.domain != "CoreDataMonk.NotFound" {
                throw error
            }
            
            let obj = try create(type)
            try applyProperties(obj, predicate: query.predicate)
            return obj
        }
    }

    public func delete<T: NSManagedObject>(obj: T) throws {
        self.managedObjectContext.deleteObject(obj)
    }

    public func delete<T: NSManagedObject>(objs: [T]) throws {
        for obj in objs {
            self.managedObjectContext.deleteObject(obj)
        }
    }

    public func delete<T: NSManagedObject>(type: T.Type, id: NSManagedObjectID) throws {
        let obj = try self.managedObjectContext.existingObjectWithID(id) as! T
        self.managedObjectContext.deleteObject(obj)
    }

    public func delete<T: NSManagedObject>(type: T.Type, ids: [NSManagedObjectID]) throws {
        for id in ids {
            let obj = try self.managedObjectContext.existingObjectWithID(id) as! T
            self.managedObjectContext.deleteObject(obj)
        }
    }

    public final func deleteAll<T: NSManagedObject>(type: T.Type, _ query: CoreDataQuery? = nil) throws -> Int {
        let meta = try self.metadataForEntityClass(type)
        let request = NSFetchRequest()
        request.entity = meta.entity
        request.affectedStores = [ meta.store ]
        request.predicate = query?.predicate
        request.resultType = .ManagedObjectResultType
        request.returnsObjectsAsFaults = true
        request.includesPropertyValues = false

        let objects = try self.managedObjectContext.executeFetchRequest(request) as! [T]
        try self.delete(objects)
        return objects.count
    }
    
    @available(iOS 9.0, *)
    public func batchUpdate<T: NSManagedObject>(type: T.Type, _ query: CoreDataQuery? = nil, properties: [String: AnyObject]) throws -> Int {
        let meta = try self.metadataForEntityClass(type)
        let request = NSBatchUpdateRequest(entity: meta.entity)
        request.resultType = .UpdatedObjectsCountResultType
        request.affectedStores = [ meta.store ]
        request.predicate = query?.predicate
        request.propertiesToUpdate = properties

        let result = try self.managedObjectContext.executeRequest(request) as! NSBatchUpdateResult
        return result.result as! Int
    }

    @available(iOS 9.0, *)
    public func batchDelete<T: NSManagedObject>(type: T.Type, ids: [NSManagedObjectID]) throws {
        let request = NSBatchDeleteRequest(objectIDs: ids)
        try self.managedObjectContext.executeRequest(request)
        self.refreshAll()
    }

    @available(iOS 9.0, *)
    public func batchDelete<T: NSManagedObject>(type: T.Type, _ query: CoreDataQuery? = nil) throws -> Int {
        let meta = try self.metadataForEntityClass(type)
        let request = NSFetchRequest()
        request.entity = meta.entity
        request.affectedStores = [ meta.store ]
        request.predicate = query?.predicate
        
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        deleteRequest.resultType = .ResultTypeCount
        deleteRequest.affectedStores = [ meta.store ]
        
        let r = try self.managedObjectContext.executeRequest(deleteRequest) as! NSBatchDeleteResult
        let count = r.result as! Int
        self.refreshAll()
        return count
    }

    public func perform(block: (CoreDataUpdate) throws -> Void) {
        self.managedObjectContext.performBlock() {
            do {
                try block(self)
            } catch {
                self.context.handleError(error)
            }
        }
    }

    private func saveContext(context: NSManagedObjectContext) throws {
        if !context.hasChanges {
            return
        }
        
        if !context.insertedObjects.isEmpty {
            try context.obtainPermanentIDsForObjects(Array(context.insertedObjects))
        }
    
        try context.save()
        
        if let parent = context.parentContext {
            parent.performBlock() {
                do {
                    try self.saveContext(parent)
                } catch {
                    self.context.handleError(error)
                }
            }
        } else {
            if !self.context.autoMerge {
                NSNotificationCenter.defaultCenter().postNotificationName(CoreDataContext.CommitNotification, object: self.context.origin)
            }
        }
    }
    
    public func commit() throws {
        try saveContext(self.managedObjectContext)
    }
    
    public func rollback() {
        self.managedObjectContext.reset()
    }
}
