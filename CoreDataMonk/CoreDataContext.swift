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

public class CoreDataContext {
    public static let CommitNotification = "CoreDataDidCommit"

    public enum TransactionTarget {
        case MainContext
        case RootContext(autoMerge: Bool)
        case PersistentStore
    }

    public enum TransactionOrder {
        case Serial
        case Concurrent
    }
    
    public class Observer {
        var observer: NSObjectProtocol
        
        init(notification: String, object: AnyObject?, queue: NSOperationQueue?, block: (NSNotification) -> Void) {
            self.observer = NSNotificationCenter.defaultCenter().addObserverForName(notification, object: object, queue: queue, usingBlock: block)
        }
        
        deinit {
            NSNotificationCenter.defaultCenter().removeObserver(self.observer)
        }
    }

    let mainContext: NSManagedObjectContext?
    let stack: CoreDataStack
    let transactionTarget: TransactionTarget
    let transactionQueue: dispatch_queue_t?
    var autoMergeObserver: Observer?

    public init(stack: CoreDataStack, mainContext: NSManagedObjectContext? = nil, transactionTarget: TransactionTarget = .RootContext(autoMerge: false), transactionOrder: TransactionOrder = .Concurrent) throws {
        if transactionOrder == .Serial {
            self.transactionQueue = dispatch_queue_create("CoreDataContext.TransactionQueue", DISPATCH_QUEUE_SERIAL)
        } else {
            self.transactionQueue = nil
        }
        
        self.stack = stack
        self.mainContext = mainContext
        self.transactionTarget = transactionTarget

        switch transactionTarget {
        case .MainContext:
            guard mainContext != nil else {
                throw CoreDataError("CoreDataContext.UpdateTarget(.MainContext) need MainContext but it is not specified")
            }
        
        case let .RootContext(autoMerge: autoMerge):
            guard let rootContext = stack.rootManagedObjectContext else {
                throw CoreDataError("CoreDataContext.UpdateTarget(.RootContext) need RootContext but CoreDataStack does not have one")
            }
            
            if autoMerge {
                guard let mainContext = mainContext else {
                    throw CoreDataError("CoreDataContext.UpdateTarget(.RootContext) need to auto merge MainContext but it is not specified")
                }

                self.autoMergeObserver = Observer(notification: NSManagedObjectContextDidSaveNotification, object: rootContext, queue: nil) {
                    [weak mainContext] notification in
                    
                    mainContext?.performBlock() {
                        mainContext?.mergeChangesFromContextDidSaveNotification(notification)
                    }
                }
            }
            
        default:
            break
        }
    }

    public final func metadataForEntityClass(type: NSManagedObject.Type) throws -> (entity: NSEntityDescription, store: NSPersistentStore) {
        return try self.stack.metadataForEntityClass(type)
    }

    public class func observeCommit(queue queue: NSOperationQueue? = nil, block: () -> Void) -> Observer {
        return Observer(notification: CoreDataContext.CommitNotification, object: nil, queue: queue ?? NSOperationQueue.mainQueue()) {
            _ in
            
            block()
        }
    }

    public func observeCommit(queue queue: NSOperationQueue? = nil, block: () -> Void) -> Observer {
        return Observer(notification: CoreDataContext.CommitNotification, object: self, queue: queue ?? NSOperationQueue.mainQueue()) {
            _ in
            
            block()
        }
    }

    public func beginUpdate(block: (CoreDataUpdate) throws -> Void) {
        beginTransaction().perform(block)
    }

    public func beginUpdateAndWait(block: (CoreDataUpdate) throws -> Void) {
        beginTransaction().performAndWait(block)
    }

    public func beginTransaction() -> CoreDataTransaction {
        let autoMerge: Bool
        let context = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        context.name = "CoreDataTransaction"
        
        switch self.transactionTarget {
        case .MainContext:
            context.parentContext = self.mainContext
            autoMerge = true
            
        case let .RootContext(autoMerge: flag):
            context.parentContext = self.stack.rootManagedObjectContext
            autoMerge = flag
            
        case .PersistentStore:
            context.persistentStoreCoordinator = self.stack.persistentStoreCoordinator
            autoMerge = false
        }
        
        return CoreDataTransaction(context: context, origin: self, autoMerge: autoMerge)
    }
}

//---------------------------------------------------------------------------

public class CoreDataMainContext : CoreDataContext, CoreDataFetch {
    public init(stack: CoreDataStack, transactionTarget: TransactionTarget = .MainContext, transactionOrder: TransactionOrder = .Concurrent) throws {
        let context = NSManagedObjectContext(concurrencyType: .MainQueueConcurrencyType)
        context.name = "CoreDataMainContext"
        context.mergePolicy = NSRollbackMergePolicy
        context.undoManager = nil
        if let rootContext = stack.rootManagedObjectContext {
            context.parentContext = rootContext
        } else {
            context.persistentStoreCoordinator = stack.persistentStoreCoordinator
        }
        
        try super.init(stack: stack, mainContext: context, transactionTarget: transactionTarget, transactionOrder: transactionOrder)
    }
    
    public final var managedObjectContext: NSManagedObjectContext {
        return self.mainContext!
    }

    public func reset() {
        self.managedObjectContext.reset()
    }

    public func fetchResults<T: NSManagedObject>(type: T.Type, _ query: CoreDataQuery? = nil, orderBy: CoreDataOrderBy, sectionBy: CoreDataQueryKey? = nil, options: CoreDataQueryOptions? = nil) throws -> NSFetchedResultsController {
        let meta = try self.metadataForEntityClass(type)
        let request = NSFetchRequest()
        request.entity = meta.entity
        request.affectedStores = [ meta.store ]
        request.fetchLimit = 0
        request.resultType = .ManagedObjectResultType
        request.predicate = query?.predicate
        request.sortDescriptors = orderBy.descriptors
        try options?.apply(request)
                
        return NSFetchedResultsController(fetchRequest: request, managedObjectContext: self.managedObjectContext, sectionNameKeyPath: sectionBy?.path, cacheName: nil)
    }
}

