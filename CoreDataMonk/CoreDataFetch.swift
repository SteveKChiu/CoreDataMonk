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

public protocol CoreDataFetch {
    var managedObjectContext: NSManagedObjectContext { get }

    func metadataForEntityClass(type: NSManagedObject.Type) throws -> (entity: NSEntityDescription, store: NSPersistentStore)
}

public extension CoreDataFetch {
    public func use<T: NSManagedObject>(obj: T) throws -> T {
        if obj.managedObjectContext === self.managedObjectContext {
            return obj
        } else {
            return try self.managedObjectContext.existingObjectWithID(obj.objectID) as! T
        }
    }

    public func use<T: NSManagedObject>(objs: [T]) throws -> [T] {
        return try objs.map({ try self.use($0) })
    }

    public func fetch<T: NSManagedObject>(type: T.Type, id: NSManagedObjectID) throws -> T {
        return try self.managedObjectContext.existingObjectWithID(id) as! T
    }

    public func fetch<T: NSManagedObject>(type: T.Type, ids: [NSManagedObjectID]) throws -> [T] {
        var objs = [T]()
        for id in ids {
            let obj = try self.managedObjectContext.existingObjectWithID(id) as! T
            objs.append(obj)
        }
        return objs
    }

    public final func fetch<T: NSManagedObject>(type: T.Type, _ query: CoreDataQuery, options: CoreDataQueryOptions? = nil) throws -> T {
        let meta = try self.metadataForEntityClass(type)
        let request = NSFetchRequest()
        request.entity = meta.entity
        request.affectedStores = [ meta.store ]
        request.fetchLimit = 1
        request.resultType = .ManagedObjectResultType
        request.predicate = query.predicate
        try options?.apply(request)
        
        guard let obj = try self.managedObjectContext.executeFetchRequest(request).first else {
            throw NSError(domain: "CoreDataMonk.NotFound", code: 0, userInfo: nil)
        }
        
        return obj as! T
    }

    public final func fetchCount<T: NSManagedObject>(type: T.Type, _ query: CoreDataQuery? = nil, orderBy: CoreDataOrderBy? = nil, options: CoreDataQueryOptions? = nil) throws -> Int {
        let meta = try self.metadataForEntityClass(type)
        let request = NSFetchRequest()
        request.entity = meta.entity
        request.affectedStores = [ meta.store ]
        request.predicate = query?.predicate
        try options?.apply(request)
        
        var error: NSError?
        let count = self.managedObjectContext.countForFetchRequest(request, error: &error)
        if count == NSNotFound {
            throw error!
        }
        return count
    }

    public final func fetchAll<T: NSManagedObject>(type: T.Type, _ query: CoreDataQuery? = nil, orderBy: CoreDataOrderBy? = nil, options: CoreDataQueryOptions? = nil) throws -> [T] {
        let meta = try self.metadataForEntityClass(type)
        let request = NSFetchRequest()
        request.entity = meta.entity
        request.affectedStores = [ meta.store ]
        request.fetchLimit = 0
        request.resultType = .ManagedObjectResultType
        request.predicate = query?.predicate
        request.sortDescriptors = orderBy?.descriptors
        try options?.apply(request)
        
        return try self.managedObjectContext.executeFetchRequest(request) as! [T]
    }

    public final func fetchID<T: NSManagedObject>(type: T.Type, _ query: CoreDataQuery, options: CoreDataQueryOptions? = nil) throws -> NSManagedObjectID {
        let meta = try self.metadataForEntityClass(type)
        let request = NSFetchRequest()
        request.entity = meta.entity
        request.affectedStores = [ meta.store ]
        request.fetchLimit = 1
        request.resultType = .ManagedObjectIDResultType
        request.predicate = query.predicate
        try options?.apply(request)
        
        return try self.managedObjectContext.executeFetchRequest(request).first as! NSManagedObjectID
    }

    public final func fetchAllID<T: NSManagedObject>(type: T.Type, _ query: CoreDataQuery? = nil, orderBy: CoreDataOrderBy? = nil, options: CoreDataQueryOptions? = nil) throws -> [NSManagedObjectID] {
        let meta = try self.metadataForEntityClass(type)
        let request = NSFetchRequest()
        request.entity = meta.entity
        request.affectedStores = [ meta.store ]
        request.fetchLimit = 0
        request.resultType = .ManagedObjectIDResultType
        request.predicate = query?.predicate
        request.sortDescriptors = orderBy?.descriptors
        try options?.apply(request)
        
        return try self.managedObjectContext.executeFetchRequest(request) as! [NSManagedObjectID]
    }

    public func queryValue<T: NSManagedObject>(type: T.Type, _ select: CoreDataSelect, _ query: CoreDataQuery? = nil, options: CoreDataQueryOptions? = nil) throws -> AnyObject {
        let meta = try self.metadataForEntityClass(type)
        let request = NSFetchRequest()
        request.entity = meta.entity
        request.affectedStores = [ meta.store ]
        request.fetchLimit = 1
        request.resultType = .DictionaryResultType
        request.propertiesToFetch = try select.resolve(meta.entity)
        request.predicate = query?.predicate
        try options?.apply(request)
        
        let result = try self.managedObjectContext.executeFetchRequest(request).first as! NSDictionary
        return result.allValues.first!
    }
    
    public func query<T: NSManagedObject>(type: T.Type, _ select: CoreDataSelect, _ query: CoreDataQuery? = nil, orderBy: CoreDataOrderBy? = nil, groupBy: CoreDataQueryKey? = nil, having: CoreDataQuery? = nil, options: CoreDataQueryOptions? = nil) throws -> [[String: AnyObject]] {
        let meta = try self.metadataForEntityClass(type)
        let request = NSFetchRequest()
        request.entity = meta.entity
        request.affectedStores = [ meta.store ]
        request.fetchLimit = 0
        request.resultType = .DictionaryResultType
        request.propertiesToFetch = try select.resolve(meta.entity)
        request.predicate = query?.predicate
        request.sortDescriptors = orderBy?.descriptors
        if let groupBy = groupBy {
            request.propertiesToGroupBy = groupBy.list
            request.havingPredicate = having?.predicate
        }
        try options?.apply(request)
        
        return try self.managedObjectContext.executeFetchRequest(request) as! [[String: AnyObject]]
    }
}
