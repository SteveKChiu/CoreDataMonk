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

open class CoreDataUpdateContext {
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

    public final func handleError(_ error: Error) {
        self.origin.stack.handleError(error)
    }
    
    open func perform(_ block: @escaping (CoreDataUpdate) throws -> Void) {
        if let queue = self.origin.updateQueue {
            queue.async {
                let group = DispatchGroup()
                group.enter()
                self.context.perform() {
                    let update = CoreDataUpdate(context: self, group: group)
                    do {
                        try block(update)
                    } catch {
                        self.handleError(error)
                    }
                    group.leave()
                }
                _ = group.wait(timeout: DispatchTime.distantFuture)
            }
        } else {
            self.context.perform() {
                let update = CoreDataUpdate(context: self, group: nil)
                do {
                    try block(update)
                } catch {
                    self.handleError(error)
                }
            }
        }
    }

    open func performAndWait(_ block: @escaping (CoreDataUpdate) throws -> Void) {
        if let queue = self.origin.updateQueue {
            queue.sync {
                let group = DispatchGroup()
                group.enter()
                self.context.perform() {
                    let update = CoreDataUpdate(context: self, group: group)
                    do {
                        try block(update)
                    } catch {
                        self.handleError(error)
                    }
                    group.leave()
                }
                _ = group.wait(timeout: DispatchTime.distantFuture)
            }
        } else {
            self.context.performAndWait() {
                let update = CoreDataUpdate(context: self, group: nil)
                do {
                    try block(update)
                } catch {
                    self.handleError(error)
                }
            }
        }
    }
    
    open func wait() {
        if let queue = self.origin.updateQueue {
            queue.sync {
                // do nothing
            }
        } else {
            self.context.performAndWait() {
                // do nothing
            }
        }
    }

    open func commit() {
        perform() {
            update in
            
            try update.commit()
        }
    }
    
    open func rollback() {
        perform() {
            update in
            
            update.rollback()
        }
    }
}

//---------------------------------------------------------------------------

open class CoreDataUpdate : CoreDataFetch {
    open let context: CoreDataUpdateContext
    let group: DispatchGroup?
    
    init(context: CoreDataUpdateContext, group: DispatchGroup?) {
        self.context = context
        self.group = group

        if let group = self.group {
            group.enter()
        }
    }
    
    deinit {
        if let group = self.group {
            group.leave()
        }
    }

    public final var managedObjectContext: NSManagedObjectContext {
        return self.context.context
    }
    
    public final func metadataForEntityClass(_ type: NSManagedObject.Type) throws -> (entity: NSEntityDescription, store: NSPersistentStore) {
        return try self.context.origin.metadataForEntityClass(type)
    }

    open func create<T: NSManagedObject>(_ type: T.Type) throws -> T {
        let meta = try self.metadataForEntityClass(type)
        let obj = T(entity: meta.entity, insertInto: self.managedObjectContext)
        self.managedObjectContext.assign(obj, to: meta.store)
        return obj
    }

    private func applyProperties(_ obj: NSManagedObject, predicate: NSPredicate) throws {
        if let comp = predicate as? NSComparisonPredicate {
            guard comp.predicateOperatorType == .equalTo else {
                throw CoreDataError("fetchOrCreate: only == and && are supported")
            }
            
            guard comp.leftExpression.expressionType == .keyPath else {
                throw CoreDataError("fetchOrCreate: left hand side of == must be key path")
            }
            
            switch comp.rightExpression.expressionType {
            case .keyPath:
                let value = obj.value(forKeyPath: comp.rightExpression.keyPath)
                obj.setValue(value, forKeyPath: comp.leftExpression.keyPath)
                
            case .constantValue:
                var value = comp.rightExpression.constantValue
                value = value is NSNull ? nil : value
                obj.setValue(value, forKeyPath: comp.leftExpression.keyPath)
                
            default:
                throw CoreDataError("fetchOrCreate: right hand side of == must be key path or constant value")
            }
            return
        }
        
        if let comp = predicate as? NSCompoundPredicate {
            guard comp.compoundPredicateType == .and else {
                throw CoreDataError("fetchOrCreate: only == and && are supported")
            }
            
            try applyProperties(obj, predicate: comp.subpredicates[0] as! NSPredicate)
            try applyProperties(obj, predicate: comp.subpredicates[1] as! NSPredicate)
            return
        }
        
        throw CoreDataError("Only == and && are supported in fetchOrCreate")
    }

    open func fetchOrCreate<T: NSManagedObject>(_ type: T.Type, _ query: CoreDataQuery) throws -> T {
        do {
            return try fetch(type, query)
        } catch (let error as NSError) {
            if error.domain != "CoreDataMonk.NotFound" {
                throw error
            }
            
            let obj = try create(type)
            try applyProperties(obj, predicate: query.predicate)
            return obj
        }
    }

    open func delete<T: NSManagedObject>(_ obj: T) throws {
        self.managedObjectContext.delete(obj)
    }

    open func delete<T: NSManagedObject>(_ objs: [T]) throws {
        for obj in objs {
            self.managedObjectContext.delete(obj)
        }
    }

    open func delete<T: NSManagedObject>(_ type: T.Type, id: NSManagedObjectID) throws {
        let obj = try self.managedObjectContext.existingObject(with: id) as! T
        self.managedObjectContext.delete(obj)
    }

    open func delete<T: NSManagedObject>(_ type: T.Type, ids: [NSManagedObjectID]) throws {
        for id in ids {
            let obj = try self.managedObjectContext.existingObject(with: id) as! T
            self.managedObjectContext.delete(obj)
        }
    }

    public final func deleteAll<T: NSManagedObject>(_ type: T.Type, _ query: CoreDataQuery? = nil) throws -> Int {
        let meta = try self.metadataForEntityClass(type)
        let request = NSFetchRequest<T>()
        request.entity = meta.entity
        request.affectedStores = [ meta.store ]
        request.predicate = query?.predicate
        request.resultType = .managedObjectResultType
        request.returnsObjectsAsFaults = true
        request.includesPropertyValues = false

        let objects = try self.managedObjectContext.fetch(request)
        try self.delete(objects)
        return objects.count
    }
    
    @available(iOS 9.0, *)
    open func batchUpdate<T: NSManagedObject>(_ type: T.Type, _ query: CoreDataQuery? = nil, properties: [String: Any]) throws -> Int {
        let meta = try self.metadataForEntityClass(type)
        let request = NSBatchUpdateRequest(entity: meta.entity)
        request.resultType = .updatedObjectsCountResultType
        request.affectedStores = [ meta.store ]
        request.predicate = query?.predicate
        request.propertiesToUpdate = properties

        let result = try self.managedObjectContext.execute(request) as! NSBatchUpdateResult
        return result.result as! Int
    }

    @available(iOS 9.0, *)
    open func batchDelete<T: NSManagedObject>(_ type: T.Type, ids: [NSManagedObjectID]) throws {
        let request = NSBatchDeleteRequest(objectIDs: ids)
        try self.managedObjectContext.execute(request)
        self.refreshAll()
    }

    @available(iOS 9.0, *)
    open func batchDelete<T: NSManagedObject>(_ type: T.Type, _ query: CoreDataQuery? = nil) throws -> Int {
        let meta = try self.metadataForEntityClass(type)
        let request = NSFetchRequest<NSFetchRequestResult>()
        request.entity = meta.entity
        request.affectedStores = [ meta.store ]
        request.predicate = query?.predicate
        
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        deleteRequest.resultType = .resultTypeCount
        deleteRequest.affectedStores = [ meta.store ]
        
        let r = try self.managedObjectContext.execute(deleteRequest) as! NSBatchDeleteResult
        let count = r.result as! Int
        self.refreshAll()
        return count
    }

    open func perform(_ block: @escaping (CoreDataUpdate) throws -> Void) {
        self.managedObjectContext.perform() {
            do {
                try block(self)
            } catch {
                self.context.handleError(error)
            }
        }
    }

    private func saveContext(_ context: NSManagedObjectContext) throws {
        if !context.hasChanges {
            return
        }
        
        if !context.insertedObjects.isEmpty {
            try context.obtainPermanentIDs(for: Array(context.insertedObjects))
        }
    
        try context.save()
        
        if let parent = context.parent {
            parent.perform() {
                do {
                    try self.saveContext(parent)
                } catch {
                    self.context.handleError(error)
                }
            }
        } else {
            if !self.context.autoMerge {
                NotificationCenter.default.post(name: Notification.Name(rawValue: CoreDataContext.CommitNotification), object: self.context.origin)
            }
        }
    }
    
    open func commit() throws {
        try saveContext(self.managedObjectContext)
    }
    
    open func rollback() {
        self.managedObjectContext.reset()
    }
}
