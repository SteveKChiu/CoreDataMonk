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
    private var pendingActions: [ () -> Void ] = []
    
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
        self.pendingActions.removeAll()
    }

    @objc func controller(controller: NSFetchedResultsController, didChangeObject anObject: AnyObject, atIndexPath indexPath: NSIndexPath?, forChangeType type: NSFetchedResultsChangeType, newIndexPath: NSIndexPath?) {
        switch type {
        case .Insert:
            self.pendingActions.append() {
                self.collectionView?.insertItemsAtIndexPaths([ newIndexPath! ])
            }
        case .Delete:
            self.pendingActions.append() {
                self.collectionView?.deleteItemsAtIndexPaths([ indexPath! ])
            }
        case .Move:
            self.pendingActions.append() {
                self.collectionView?.moveItemAtIndexPath(indexPath!, toIndexPath: newIndexPath!)
            }
        case .Update:
            self.pendingActions.append() {
                self.collectionView?.reloadItemsAtIndexPaths([ indexPath! ])
            }
        }
    }
    
    @objc func controller(controller: NSFetchedResultsController, didChangeSection sectionInfo: NSFetchedResultsSectionInfo, atIndex sectionIndex: Int, forChangeType type: NSFetchedResultsChangeType) {
        switch type {
        case .Insert:
            self.pendingActions.append() {
                self.collectionView?.insertSections(NSIndexSet(index: sectionIndex))
                self.collectionView?.collectionViewLayout.invalidateLayout()
            }
        case .Delete:
            self.pendingActions.append() {
                self.collectionView?.deleteSections(NSIndexSet(index: sectionIndex))
                self.collectionView?.collectionViewLayout.invalidateLayout()
            }
        default:
            break
        }
    }
    
    @objc func controllerDidChangeContent(controller: NSFetchedResultsController) {
        if self.collectionView?.window == nil {
            self.pendingActions.removeAll()
            self.collectionView?.reloadData()
            return
        }
        
        self.collectionView?.performBatchUpdates({
            for action in self.pendingActions {
                action()
            }
        }, completion: {
            finished in
            
            self.pendingActions.removeAll()
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
