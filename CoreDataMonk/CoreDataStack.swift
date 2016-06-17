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

func CoreDataError(_ message: String) -> NSError {
    return NSError(domain: "CoreDataStack", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
}

//---------------------------------------------------------------------------

public class CoreDataStack {
    public typealias OnError = (NSError) -> Void
    
    public enum RootContextType {
        case none
        case shared
    }
        
    public var lastError: NSError?
    public var onError: OnError?
    
    private var coordinator: NSPersistentStoreCoordinator!
    private var rootContext: NSManagedObjectContext?
    
    public init(modelName: String? = nil, bundle: Bundle? = nil, rootContext: RootContextType = .shared) throws {
        let bundle = bundle ?? Bundle.main()
        let modelName = modelName ?? Bundle.main().objectForInfoDictionaryKey("CFBundleName") as? String ?? "CoreData"
        
        guard let modelUrl = bundle.urlForResource(modelName, withExtension: "momd"),
                  model = NSManagedObjectModel(contentsOf: modelUrl) else {
            throw CoreDataError("Can not load core data model from '\(modelName)'")
        }
        
        self.coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        
        if rootContext == .shared {
            let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            context.name = "CoreDataStack.RootContext"
            context.persistentStoreCoordinator = self.coordinator
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            context.undoManager = nil
            self.rootContext = context
        }
    }
    
    public final var persistentStoreCoordinator: NSPersistentStoreCoordinator {
        return self.coordinator
    }
    
    public final var rootManagedObjectContext: NSManagedObjectContext? {
        return self.rootContext
    }

    public func addInMemoryStore(configuration: String? = nil) throws {
        let store = try self.coordinator.addPersistentStore(
            ofType: NSInMemoryStoreType,
            configurationName: configuration,
            at: nil,
            options: nil
        )
        try updateMetadata(store)
    }
    
    public func addDatabaseStore(fileName: String, configuration: String? = nil, autoMigrating: Bool = true, resetOnFailure: Bool = false) throws {
        let directory = FileManager.default().urlsForDirectory(.applicationSupportDirectory, inDomains: .userDomainMask).first!
        let fileURL = try! directory.appendingPathComponent(fileName)
        try addDatabaseStore(fileURL: fileURL, configuration: configuration, autoMigrating: autoMigrating, resetOnFailure: resetOnFailure)
    }

    public func addDatabaseStore(fileURL: URL? = nil, configuration: String? = nil, autoMigrating: Bool = true, resetOnFailure: Bool = false) throws {
        var fileURL: URL! = fileURL
        if fileURL == nil {
            let directory = FileManager.default().urlsForDirectory(.applicationSupportDirectory, inDomains: .userDomainMask).first!
            let fileName = (Bundle.main().objectForInfoDictionaryKey("CFBundleName") as? String) ?? "CoreData"
            fileURL = try! directory.appendingPathComponent(fileName + ".sqlite")
        }
    
        if let store = self.coordinator.persistentStore(for: fileURL) {
            if store.type == NSSQLiteStoreType
                    && autoMigrating == (store.options?[NSMigratePersistentStoresAutomaticallyOption] as? Bool)
                    && store.configurationName == (configuration ?? "PF_DEFAULT_CONFIGURATION_NAME") {
                try updateMetadata(store)
                return
            }
            
            throw CoreDataError("Fail to add SQLite persistent store at \"\(fileURL)\", because a different one at that URL already exists")
        }
        
        let fileManager = FileManager.default()
        _ = try? fileManager.createDirectory(at: try! fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        
        var retried = false
        let options: [NSObject : AnyObject] = [
            NSSQLitePragmasOption: ["journal_mode": "WAL"],
            NSInferMappingModelAutomaticallyOption: true,
            NSMigratePersistentStoresAutomaticallyOption: autoMigrating
        ]
        
        while true {
            do {
                let store = try self.coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: configuration, at: fileURL, options: options)
                try updateMetadata(store)
                return
            } catch {
                let error = error as NSError
                guard !retried && resetOnFailure && error.domain == NSCocoaErrorDomain else {
                    throw error
                }
                
                guard error.code == NSPersistentStoreIncompatibleVersionHashError
                        || error.code == NSMigrationMissingSourceModelError
                        || error.code == NSMigrationError else {
                    throw error
                }
                
                _ = try? self.coordinator.destroyPersistentStore(at: fileURL, ofType: NSSQLiteStoreType, options: options)
                
                retried = true
            }
        }
    }

    private var metadata = [String: (entity: NSEntityDescription, store: NSPersistentStore)]()

    private func updateMetadata(_ store: NSPersistentStore) throws {
        if let entities = self.coordinator.managedObjectModel.entities(forConfigurationName: store.configurationName) {
            for entity in entities {
                if let meta = self.metadata[entity.managedObjectClassName] where meta.entity != entity && meta.store != store {
                    throw CoreDataError("Class \(entity.managedObjectClassName) has been mapped to \(meta.entity.name!), and can not be mapped to \(entity.name!), one class can only map to one entity")
                }
                self.metadata[entity.managedObjectClassName] = (entity: entity, store: store)
            }
        }
    }

    public func metadataForEntityClass(_ type: NSManagedObject.Type) throws -> (entity: NSEntityDescription, store: NSPersistentStore) {
        if let meta = self.metadata[NSStringFromClass(type)] {
            return meta
        } else {
            throw CoreDataError("Class \(NSStringFromClass(type)) is not a registered NSManagedObject class")
        }
    }
    
    public func handleError(_ error: ErrorProtocol) {
        let error = error as NSError
        self.lastError = error
        if let onError = self.onError {
            onError(error)
        } else {
            NSLog("CoreData: error = %@", error)
        }
    }
}
