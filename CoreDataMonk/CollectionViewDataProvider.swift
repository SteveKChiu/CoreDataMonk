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

private class CollectionViewDataBridge<EntityType: NSManagedObject>
        : NSObject, UICollectionViewDataSource, NSFetchedResultsControllerDelegate {
    private unowned var provider: CollectionViewDataProvider<EntityType>
    private var insertedSections: NSMutableIndexSet!
    private var deletedSections: NSMutableIndexSet!
    private var insertedItems: [NSIndexPath]!
    private var deletedItems: [NSIndexPath]!
    private var updatedItems: [NSIndexPath]!
    private var movedItems: [(NSIndexPath, NSIndexPath)]!
    
    private var collectionView: UICollectionView? {
        return self.provider.collectionView
    }
    
    private var resultsController: NSFetchedResultsController? {
        return self.provider.resultsController
    }

    private init(provider: CollectionViewDataProvider<EntityType>) {
        self.provider = provider
    }
    
    @objc func numberOfSectionsInCollectionView(collectionView: UICollectionView) -> Int {
        return self.resultsController?.sections?.count ?? 0
    }

    @objc func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if let sections = self.resultsController?.sections where section < sections.count {
            return sections[section].numberOfObjects
        }
        return 0
    }
    
    @objc func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        if let object = self.resultsController?.objectAtIndexPath(indexPath) as? EntityType {
            if let cell = self.provider.onGetCell?(object, indexPath) {
                return cell
            }
        }
        return UICollectionViewCell()
    }
    
    @objc func collectionView(collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, atIndexPath indexPath: NSIndexPath) -> UICollectionReusableView {
        if let view = self.provider.onGetSupplementary?(kind, indexPath) {
            return view
        }
        return UICollectionReusableView()
    }
    
    @objc func controllerWillChangeContent(controller: NSFetchedResultsController) {
        self.insertedSections = NSMutableIndexSet()
        self.deletedSections = NSMutableIndexSet()
        self.insertedItems = [NSIndexPath]()
        self.deletedItems = [NSIndexPath]()
        self.updatedItems = [NSIndexPath]()
        self.movedItems = [(NSIndexPath, NSIndexPath)]()
    }

    @objc func controller(controller: NSFetchedResultsController, didChangeObject anObject: AnyObject, atIndexPath indexPath: NSIndexPath?, forChangeType type: NSFetchedResultsChangeType, newIndexPath: NSIndexPath?) {
        switch type {
        case .Insert:
            self.insertedItems?.append(newIndexPath!)
        case .Delete:
            self.deletedItems?.append(indexPath!)
        case .Move:
            self.movedItems?.append((indexPath!, newIndexPath!))
        case .Update:
            self.updatedItems?.append(indexPath!)
        }
    }
    
    @objc func controller(controller: NSFetchedResultsController, didChangeSection sectionInfo: NSFetchedResultsSectionInfo, atIndex sectionIndex: Int, forChangeType type: NSFetchedResultsChangeType) {
        switch type {
        case .Insert:
            self.insertedSections?.addIndex(sectionIndex)
        case .Delete:
            self.deletedSections?.addIndex(sectionIndex)
        default:
            break
        }
    }
    
    @objc func controllerDidChangeContent(controller: NSFetchedResultsController) {
        assert(NSThread.isMainThread())
        guard let collectionView = self.collectionView
                where self.insertedSections != nil else {
            return
        }

        if !self.movedItems.isEmpty {
            self.movedItems = self.movedItems.filter {
                let (from, to) = $0
                if self.deletedSections.containsIndex(from.section) {
                    if !self.insertedSections.containsIndex(to.section) {
                        self.insertedItems.append(to)
                    }
                    return false
                } else if self.insertedSections.containsIndex(to.section) {
                    self.deletedItems.append(from)
                    return false
                } else {
                    return true
                }
            }
        }
        
        if !self.deletedItems.isEmpty {
            self.deletedItems = self.deletedItems.filter {
                return !self.deletedSections.containsIndex($0.section)
            }
        }
        
        if !self.insertedItems.isEmpty {
            self.insertedItems = self.insertedItems.filter {
                return !self.insertedSections.containsIndex($0.section)
            }
        }
        
        collectionView.performBatchUpdates({
            if self.deletedSections.count > 0 {
                collectionView.deleteSections(self.deletedSections)
            }
            
            if self.insertedSections.count > 0 {
                collectionView.insertSections(self.insertedSections)
            }
            
            if !self.deletedItems.isEmpty {
                collectionView.deleteItemsAtIndexPaths(self.deletedItems)
            }
            
            if !self.insertedItems.isEmpty {
                collectionView.insertItemsAtIndexPaths(self.insertedItems)
            }
            
            if !self.updatedItems.isEmpty {
                collectionView.reloadItemsAtIndexPaths(self.updatedItems)
            }
            
            for (from, to) in self.movedItems {
                collectionView.moveItemAtIndexPath(from, toIndexPath: to)
            }
        }, completion: {
            _ in
            
            self.insertedSections = nil
            self.deletedSections = nil
            self.insertedItems = nil
            self.deletedItems = nil
            self.updatedItems = nil
            self.movedItems = nil
        })
    }
}

//---------------------------------------------------------------------------

public class CollectionViewDataProvider<EntityType: NSManagedObject> {
    private var bridge: CollectionViewDataBridge<EntityType>!
    
    public typealias OnGetCellCallback = (EntityType, NSIndexPath) -> UICollectionViewCell
    public typealias OnGetSupplementaryCallback = (String, NSIndexPath) -> UICollectionReusableView
    
    public var onGetCell: OnGetCellCallback?
    public var onGetSupplementary: OnGetSupplementaryCallback?
    
    public let context: CoreDataMainContext

    public var resultsController: NSFetchedResultsController? {
        willSet {
            self.resultsController?.delegate = nil
        }
        didSet {
            self.resultsController?.delegate = self.bridge
        }
    }

    public weak var collectionView: UICollectionView? {
        willSet {
            if self.collectionView?.dataSource === self.bridge {
                self.collectionView?.dataSource = nil
            }
        }
        didSet {
            self.collectionView?.dataSource = self.bridge
        }
    }

    public init(context: CoreDataMainContext) {
        self.context = context
        self.bridge = CollectionViewDataBridge<EntityType>(provider: self)
    }
    
    public func objectAtIndexPath(indexPath: NSIndexPath) -> EntityType? {
        return self.resultsController?.objectAtIndexPath(indexPath) as? EntityType
    }
    
    public func indexPathForObject(object: EntityType) -> NSIndexPath? {
        return self.resultsController?.indexPathForObject(object)
    }
    
    public func bind(collectionView: UICollectionView, onGetCell: OnGetCellCallback) -> CollectionViewDataProvider<EntityType> {
        self.onGetCell = onGetCell
        self.collectionView = collectionView
        return self
    }
    
    public func query(query: CoreDataQuery? = nil, orderBy: CoreDataOrderBy, sectionBy: CoreDataQueryKey? = nil, options: CoreDataQueryOptions? = nil) throws -> CollectionViewDataProvider<EntityType> {
        self.resultsController = try self.context.fetchResults(EntityType.self, query, orderBy: orderBy, sectionBy: sectionBy, options: options)
        try self.resultsController?.performFetch()
        self.collectionView?.reloadData()
        return self
    }
}
