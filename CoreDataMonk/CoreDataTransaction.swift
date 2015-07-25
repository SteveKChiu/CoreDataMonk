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

public class CoreDataTransaction {
    public let context: NSManagedObjectContext
    let origin: CoreDataContext
    let autoMerge: Bool
    
    init(context: NSManagedObjectContext, origin: CoreDataContext, autoMerge: Bool) {
        self.context = context
        self.origin = origin
        self.autoMerge = autoMerge
    }

    public func perform(block: (CoreDataUpdate) throws -> Void) {
        if let queue = self.origin.updateQueue {
            dispatch_async(queue) {
                let group = dispatch_group_create()
                dispatch_group_enter(group)
                self.context.performBlock() {
                    let update = CoreDataUpdate(context: self.context, transaction: self, performGroup: group)
                    do {
                        try block(update)
                    } catch let error {
                        self.origin.coreDataStack.handleError(error as NSError)
                    }
                    dispatch_group_leave(group)
                }
                dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
            }
        } else {
            self.context.performBlock() {
                let update = CoreDataUpdate(context: self.context, transaction: self, performGroup: nil)
                do {
                    try block(update)
                } catch let error {
                    self.origin.coreDataStack.handleError(error as NSError)
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
                    let update = CoreDataUpdate(context: self.context, transaction: self, performGroup: group)
                    do {
                        try block(update)
                    } catch let error {
                        self.origin.coreDataStack.handleError(error as NSError)
                    }
                    dispatch_group_leave(group)
                }
                dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
            }
        } else {
            self.context.performBlockAndWait() {
                let update = CoreDataUpdate(context: self.context, transaction: self, performGroup: nil)
                do {
                    try block(update)
                } catch let error {
                    self.origin.coreDataStack.handleError(error as NSError)
                }
            }
        }
    }
    
    public func commit() {
        perform() {
            trans in
            
            do {
                try trans.commit()
            } catch let error {
                trans.coreDataStack.handleError(error as NSError)
            }
        }
    }
    
    public func rollback() {
        perform() {
            trans in
            
            trans.rollback()
        }
    }
}

//---------------------------------------------------------------------------

public class CoreDataUpdate : CoreDataFetch {
    let context: NSManagedObjectContext
    let transaction: CoreDataTransaction
    let performGroup: dispatch_group_t?
    
    public var managedObjectContext: NSManagedObjectContext {
        return self.context
    }
    
    public var coreDataStack: CoreDataStack {
        return self.transaction.origin.coreDataStack
    }
    
    init(context: NSManagedObjectContext, transaction: CoreDataTransaction, performGroup: dispatch_group_t?) {
        self.context = context
        self.transaction = transaction
        self.performGroup = performGroup
    }

    public func create<T: NSManagedObject>(type: T.Type) throws -> T {
        let meta = try self.coreDataStack.metadataForEntityClass(type)
        let obj = T(entity: meta.entity, insertIntoManagedObjectContext: self.context)
        self.context.assignObject(obj, toPersistentStore: meta.store)
        return obj
    }

    public func fetchOrCreate<T: NSManagedObject>(type: T.Type, key: String, value: AnyObject) throws -> T {
        do {
            return try fetch(type, .Where("%K == %@", key, value))
        } catch {
            let obj = try create(type)
            (obj as NSManagedObject).setValue(value, forKey: key)
            return obj
        }
    }

    public func delete<T: NSManagedObject>(obj: T) throws {
        self.context.deleteObject(obj)
    }

    public func delete<T: NSManagedObject>(objs: [T]) throws {
        for obj in objs {
            try self.delete(obj)
        }
    }

    public final func deleteAll<T: NSManagedObject>(type: T.Type, _ query: CoreDataQuery? = nil) throws {
        let meta = try self.coreDataStack.metadataForEntityClass(type)
        let request = NSFetchRequest()
        request.entity = meta.entity
        request.fetchLimit = 0
        request.resultType = .ManagedObjectResultType
        request.returnsObjectsAsFaults = true
        request.includesPropertyValues = false
        
        try self.delete(try self.context.executeFetchRequest(request) as! [T])
    }
    
    public func perform(block: (CoreDataUpdate) throws -> Void) {
        if let group = self.performGroup {
            dispatch_group_enter(group)
            self.context.performBlock() {
                do {
                    try block(self)
                } catch let error {
                    self.coreDataStack.handleError(error as NSError)
                }
                dispatch_group_leave(group)
            }
        } else {
            self.context.performBlock() {
                do {
                    try block(self)
                } catch let error {
                    self.coreDataStack.handleError(error as NSError)
                }
            }
        }
    }

    private func saveContext(context: NSManagedObjectContext) throws {
        try context.save()
        
        if let parent = context.parentContext {
            parent.performBlock() {
                do {
                    try self.saveContext(parent)
                } catch let error {
                    self.coreDataStack.handleError(error as NSError)
                }
            }
        } else {
            if !self.transaction.autoMerge {
                NSNotificationCenter.defaultCenter().postNotificationName(CoreDataContext.DidCommitNotification, object: self.transaction.origin)
            }
        }
    }
    
    public func commit() throws {
        try saveContext(self.context)
    }
    
    public func rollback() {
        self.context.reset()
    }
}
