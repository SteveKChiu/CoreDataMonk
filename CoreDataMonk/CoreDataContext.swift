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

open class CoreDataContext {
    open static let CommitNotification = "CoreDataDidCommit"

    public enum UpdateTarget {
        case mainContext
        case rootContext(autoMerge: Bool)
        case persistentStore
    }

    public enum UpdateOrder {
        case serial
        case `default`
    }
    
    private class Observer {
        var observer: NSObjectProtocol
        
        init(notification: String, object: AnyObject?, queue: OperationQueue?, block: @escaping (Notification) -> Void) {
            self.observer = NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: notification), object: object, queue: queue, using: block)
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self.observer)
        }
    }

    let mainContext: NSManagedObjectContext?
    let stack: CoreDataStack
    let updateTarget: UpdateTarget
    let updateQueue: DispatchQueue?
    var autoMergeObserver: AnyObject?

    public init(stack: CoreDataStack, mainContext: NSManagedObjectContext? = nil, updateTarget: UpdateTarget = .rootContext(autoMerge: false), updateOrder: UpdateOrder = .default) throws {
        if updateOrder == .serial {
            self.updateQueue = DispatchQueue(label: "CoreDataContext.UpdateQueue", attributes: [])
        } else {
            self.updateQueue = nil
        }
        
        self.stack = stack
        self.mainContext = mainContext
        self.updateTarget = updateTarget

        switch updateTarget {
        case .mainContext:
            guard mainContext != nil else {
                throw CoreDataError("CoreDataContext.UpdateTarget(.MainContext) need MainContext but it is not specified")
            }
        
        case let .rootContext(autoMerge: autoMerge):
            guard let rootContext = stack.rootManagedObjectContext else {
                throw CoreDataError("CoreDataContext.UpdateTarget(.RootContext) need RootContext but CoreDataStack does not have one")
            }
            
            if autoMerge {
                guard let mainContext = mainContext else {
                    throw CoreDataError("CoreDataContext.UpdateTarget(.RootContext) need to auto merge MainContext but it is not specified")
                }

                self.autoMergeObserver = Observer(notification: NSNotification.Name.NSManagedObjectContextDidSave.rawValue, object: rootContext, queue: nil) {
                    [weak mainContext] notification in
                    
                    mainContext?.perform() {
                        mainContext?.mergeChanges(fromContextDidSave: notification)
                    }
                }
            }
            
        default:
            break
        }
    }

    public final func metadataForEntityClass(_ type: NSManagedObject.Type) throws -> (entity: NSEntityDescription, store: NSPersistentStore) {
        return try self.stack.metadataForEntityClass(type)
    }

    open class func observeCommit(queue: OperationQueue? = nil, block: @escaping () -> Void) -> AnyObject {
        return Observer(notification: CoreDataContext.CommitNotification, object: nil, queue: queue ?? OperationQueue.main) {
            _ in
            
            block()
        }
    }

    open func observeCommit(queue: OperationQueue? = nil, block: @escaping () -> Void) -> AnyObject {
        return Observer(notification: CoreDataContext.CommitNotification, object: self, queue: queue ?? OperationQueue.main) {
            _ in
            
            block()
        }
    }

    open func beginUpdate(_ block: @escaping (CoreDataUpdate) throws -> Void) {
        beginUpdateContext().perform(block)
    }

    open func beginUpdateAndWait(_ block: @escaping (CoreDataUpdate) throws -> Void) {
        beginUpdateContext().performAndWait(block)
    }

    open func beginUpdateContext() -> CoreDataUpdateContext {
        let autoMerge: Bool
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.name = "CoreDataUpdateContext"
        
        switch self.updateTarget {
        case .mainContext:
            context.parent = self.mainContext
            autoMerge = true
            
        case let .rootContext(autoMerge: flag):
            context.parent = self.stack.rootManagedObjectContext
            autoMerge = flag
            
        case .persistentStore:
            context.persistentStoreCoordinator = self.stack.persistentStoreCoordinator
            autoMerge = false
        }
        
        return CoreDataUpdateContext(context: context, origin: self, autoMerge: autoMerge)
    }
}

//---------------------------------------------------------------------------

open class CoreDataMainContext : CoreDataContext, CoreDataFetch {
    public init(stack: CoreDataStack, uodateTarget: UpdateTarget = .mainContext, updateOrder: UpdateOrder = .default) throws {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.name = "CoreDataMainContext"
        context.mergePolicy = NSRollbackMergePolicy
        context.undoManager = nil
        if let rootContext = stack.rootManagedObjectContext {
            context.parent = rootContext
        } else {
            context.persistentStoreCoordinator = stack.persistentStoreCoordinator
        }
        
        try super.init(stack: stack, mainContext: context, updateTarget: uodateTarget, updateOrder: updateOrder)
    }
    
    public final var managedObjectContext: NSManagedObjectContext {
        return self.mainContext!
    }

    open func reset() {
        self.managedObjectContext.reset()
    }

    open func fetchResults<T: NSManagedObject>(_ type: T.Type, _ query: CoreDataQuery? = nil, orderBy: CoreDataOrderBy, sectionBy: CoreDataQueryKey? = nil, options: CoreDataQueryOptions? = nil) throws -> NSFetchedResultsController<NSFetchRequestResult> {
        let meta = try self.metadataForEntityClass(type)
        let request = NSFetchRequest<NSFetchRequestResult>()
        request.entity = meta.entity
        request.affectedStores = [ meta.store ]
        request.fetchLimit = 0
        request.resultType = NSFetchRequestResultType()
        request.predicate = query?.predicate
        request.sortDescriptors = orderBy.descriptors
        try options?.apply(request)
                
        return NSFetchedResultsController(fetchRequest: request, managedObjectContext: self.managedObjectContext, sectionNameKeyPath: sectionBy?.path, cacheName: nil)
    }
}

