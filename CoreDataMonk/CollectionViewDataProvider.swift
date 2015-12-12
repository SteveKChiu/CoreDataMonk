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
    weak var provider: CollectionViewDataProvider<EntityType>?
    var pendingActions: [() -> Void] = []
    var updatedIndexPaths: Set<NSIndexPath> = []
    var shouldReloadData = false
    var isFiltering = false
    var semaphore: dispatch_semaphore_t
    
    var collectionView: UICollectionView? {
        return self.provider?.collectionView
    }
    
    init(provider: CollectionViewDataProvider<EntityType>) {
        self.provider = provider
        self.semaphore = dispatch_semaphore_create(1)
    }
    
    @objc func numberOfSectionsInCollectionView(collectionView: UICollectionView) -> Int {
        return self.provider?.numberOfSections() ?? 0
    }

    @objc func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.provider?.numberOfObjectsInSection(section) ?? 0
    }
    
    @objc func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        if let object = self.provider?.objectAtIndexPath(indexPath),
               cell = self.provider?.onGetCell?(object, indexPath) {
            return cell
        }
        return UICollectionViewCell()
    }
    
    @objc func collectionView(collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, atIndexPath indexPath: NSIndexPath) -> UICollectionReusableView {
        if let view = self.provider?.onGetSupplementary?(kind, indexPath) {
            return view
        }
        return UICollectionReusableView()
    }
    
    private func ensureIndexPath(indexPath: NSIndexPath) -> Bool {
        if self.isFiltering || self.shouldReloadData {
            return false
        } else if self.updatedIndexPaths.contains(indexPath) {
            self.updatedIndexPaths.removeAll()
            self.pendingActions.removeAll()
            self.shouldReloadData = true
            return false
        } else {
            self.updatedIndexPaths.insert(indexPath)
            return true
        }
    }
    
    @objc func controllerWillChangeContent(controller: NSFetchedResultsController) {
        self.pendingActions.removeAll()
        self.updatedIndexPaths.removeAll()
        self.shouldReloadData = false
        self.isFiltering = self.provider?.objectFilter != nil
    }

    @objc func controller(controller: NSFetchedResultsController, didChangeObject anObject: AnyObject, atIndexPath indexPath: NSIndexPath?, forChangeType type: NSFetchedResultsChangeType, newIndexPath: NSIndexPath?) {
        switch type {
        case .Insert:
            if ensureIndexPath(newIndexPath!) {
                self.pendingActions.append() {
                    [weak self] in
                    self?.collectionView?.insertItemsAtIndexPaths([ newIndexPath! ])
                }
            }
            
        case .Delete:
            if ensureIndexPath(indexPath!) {
                self.pendingActions.append() {
                    [weak self] in
                    self?.collectionView?.deleteItemsAtIndexPaths([ indexPath! ])
                }
            }
            
        case .Move:
            if ensureIndexPath(indexPath!) && ensureIndexPath(newIndexPath!) {
                self.pendingActions.append() {
                    [weak self] in
                    self?.collectionView?.moveItemAtIndexPath(indexPath!, toIndexPath: newIndexPath!)
                }
            }
            
        case .Update:
            if ensureIndexPath(indexPath!) {
                self.pendingActions.append() {
                    [weak self] in
                    self?.collectionView?.reloadItemsAtIndexPaths([ indexPath! ])
                }
            }
        }
    }
    
    @objc func controller(controller: NSFetchedResultsController, didChangeSection sectionInfo: NSFetchedResultsSectionInfo, atIndex sectionIndex: Int, forChangeType type: NSFetchedResultsChangeType) {
        if self.isFiltering || self.shouldReloadData {
            return
        }

        switch type {
        case .Insert:
            self.pendingActions.append() {
                [weak self] in
                self?.collectionView?.insertSections(NSIndexSet(index: sectionIndex))
                self?.collectionView?.collectionViewLayout.invalidateLayout()
            }
            
        case .Delete:
            self.pendingActions.append() {
                [weak self] in
                self?.collectionView?.deleteSections(NSIndexSet(index: sectionIndex))
                self?.collectionView?.collectionViewLayout.invalidateLayout()
            }
            
        default:
            break
        }
    }
    
    @objc func controllerDidChangeContent(controller: NSFetchedResultsController) {
        if self.isFiltering {
            self.provider?.filter()
            self.provider?.onDataChanged?()
            return
        }

        if self.shouldReloadData || self.collectionView?.window == nil {
            self.pendingActions.removeAll()
            self.updatedIndexPaths.removeAll()
            self.collectionView?.reloadData()
            self.provider?.onDataChanged?()
            return
        }

        guard let collectionView = self.collectionView else {
            return
        }

        // make sure batch update animation is not overlapped
        let semaphore = self.semaphore
        dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, Int64(NSEC_PER_SEC)))
        self.updatedIndexPaths.removeAll()

        collectionView.performBatchUpdates({
            [weak self] in
            if let actions = self?.pendingActions where !actions.isEmpty {
                self?.pendingActions.removeAll()
                for action in actions {
                    action()
                }
            }
        }, completion: {
            [weak self] _ in
            self?.provider?.onDataChanged?()
            dispatch_semaphore_signal(semaphore)
        })
    }
}

//---------------------------------------------------------------------------

public class CollectionViewDataProvider<EntityType: NSManagedObject> : ViewDataProvider<EntityType> {
    public let context: CoreDataMainContext
    private var bridge: CollectionViewDataBridge<EntityType>!
    
    public typealias OnGetCell = (EntityType, NSIndexPath) -> UICollectionViewCell?
    public typealias OnGetSupplementary = (String, NSIndexPath) -> UICollectionReusableView?
    public typealias OnDataChanged = () -> Void
    
    public var onGetCell: OnGetCell?
    public var onGetSupplementary: OnGetSupplementary?
    public var onDataChanged: OnDataChanged?
    
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

    public override var fetchedResultsController: NSFetchedResultsController? {
        get {
            return super.fetchedResultsController
        }
        set {
            super.fetchedResultsController?.delegate = nil
            super.fetchedResultsController = newValue
            newValue?.delegate = self.bridge
        }
    }

    public init(context: CoreDataMainContext) {
        self.context = context
        super.init()
        self.bridge = CollectionViewDataBridge<EntityType>(provider: self)
    }
    
    public func bind(collectionView: UICollectionView, onGetCell: OnGetCell) {
        self.onGetCell = onGetCell
        self.collectionView = collectionView
    }
    
    public func load(query: CoreDataQuery? = nil, orderBy: CoreDataOrderBy, sectionBy: CoreDataQueryKey? = nil, options: CoreDataQueryOptions? = nil) throws {
        self.fetchedResultsController = try self.context.fetchResults(EntityType.self, query, orderBy: orderBy, sectionBy: sectionBy, options: options)
        try reload()
    }
    
    public override func filter() {
        super.filter()
        self.collectionView?.reloadData()
    }
}
