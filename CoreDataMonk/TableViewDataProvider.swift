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

private class TableViewDataBridge<EntityType: NSManagedObject>
        : NSObject, UITableViewDataSource, NSFetchedResultsControllerDelegate {
    weak var provider: TableViewDataProvider<EntityType>?
    var updatedIndexPaths: Set<IndexPath> = []
    var isFiltering = false
    
    var tableView: UITableView? {
        return self.provider?.tableView
    }
    
    var controller: NSFetchedResultsController<NSFetchRequestResult>? {
        return self.provider?.fetchedResultsController
    }

    init(provider: TableViewDataProvider<EntityType>) {
        self.provider = provider
    }
    
    @objc func numberOfSections(in tableView: UITableView) -> Int {
        return self.provider?.numberOfSections() ?? 0
    }

    @objc func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.provider?.numberOfObjectsInSection(section) ?? 0
    }
    
    @objc func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let object = self.provider?.objectAtIndexPath(indexPath),
               let cell = self.provider?.onGetCell?(object, indexPath) {
            return cell
        }
        return UITableViewCell()
    }
    
    @objc func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if let sectionCount = self.provider?.numberOfSections(), sectionCount != self.controller?.sections?.count {
            if let onGetSectionTitle = self.provider?.onGetSectionTitle, section < sectionCount {
                return onGetSectionTitle("", section)
            }
            return nil
        }
        
        if let sections = self.controller?.sections, section < sections.count {
            let title = sections[section].name
            if let onGetSectionTitle = self.provider?.onGetSectionTitle {
                return onGetSectionTitle(title, section)
            }
            return title
        }
        
        return nil
    }
    
    @objc func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        if let sectionCount = self.provider?.numberOfSections(), sectionCount != self.controller?.sections?.count {
            return nil
        } else {
            return self.controller?.sectionIndexTitles
        }
    }
    
    @objc func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
        if let sectionCount = self.provider?.numberOfSections(), sectionCount != self.controller?.sections?.count {
            return 0
        } else {
            return self.controller?.section(forSectionIndexTitle: title, at: index) ?? 0
        }
    }
    
    @objc func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        self.updatedIndexPaths.removeAll()
        self.isFiltering = self.provider?.objectFilter != nil
        
        if !self.isFiltering {
            self.tableView?.beginUpdates()
        }
    }

    @objc func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        if self.isFiltering {
            return
        }
        
        switch type {
        case .insert:
            if !self.updatedIndexPaths.contains(newIndexPath!) {
                self.tableView?.insertRows(at: [ newIndexPath! ], with: .automatic)
            }
            
        case .delete:
            self.tableView?.deleteRows(at: [ indexPath! ], with: .automatic)
            self.updatedIndexPaths.remove(indexPath!)
            
        case .move:
            self.tableView?.deleteRows(at: [ indexPath! ], with: .automatic)
            self.tableView?.insertRows(at: [ newIndexPath! ], with: .automatic)
            self.updatedIndexPaths.remove(indexPath!)
            
        case .update:
            self.updatedIndexPaths.insert(indexPath!)
        }
    }
    
    @objc func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        if self.isFiltering {
            return
        }

        switch type {
        case .insert:
            self.tableView?.insertSections(IndexSet(integer: sectionIndex), with: .automatic)
            
        case .delete:
            self.tableView?.deleteSections(IndexSet(integer: sectionIndex), with: .automatic)
            
        default:
            break
        }
    }
    
    @objc func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, sectionIndexTitleForSectionName sectionName: String) -> String? {
        if let onGetIndexTitle = self.provider?.onGetIndexTitle {
            return onGetIndexTitle(sectionName)
        }
        return sectionName
    }

    @objc func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        if self.isFiltering {
            self.provider?.filter()
            self.provider?.onDataChanged?()
            return
        }

        self.tableView?.endUpdates()
        
        if !self.updatedIndexPaths.isEmpty {
            let indexPaths = Array(self.updatedIndexPaths)
            self.updatedIndexPaths.removeAll()
            self.tableView?.reloadRows(at: indexPaths, with: .automatic)
        }
        
        self.provider?.onDataChanged?()
    }
}

//---------------------------------------------------------------------------

open class TableViewDataProvider<EntityType: NSManagedObject> : ViewDataProvider<EntityType> {
    public let context: CoreDataMainContext
    private var bridge: TableViewDataBridge<EntityType>!
    
    public typealias OnGetCell = (EntityType, IndexPath) -> UITableViewCell?
    public typealias OnGetSectionTitle = (String, Int) -> String
    public typealias OnGetIndexTitle = (String) -> String
    public typealias OnDataChanged = () -> Void
    
    public var onGetCell: OnGetCell?
    public var onGetSectionTitle: OnGetSectionTitle?
    public var onGetIndexTitle: OnGetIndexTitle?
    public var onDataChanged: OnDataChanged?
    
    public weak var tableView: UITableView? {
        willSet {
            if self.tableView?.dataSource === self.bridge {
                self.tableView?.dataSource = nil
            }
        }
        didSet {
            self.tableView?.dataSource = self.bridge
        }
    }

    open override var fetchedResultsController: NSFetchedResultsController<NSFetchRequestResult>? {
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
        self.bridge = TableViewDataBridge<EntityType>(provider: self)
    }
    
    public func bind(_ tableView: UITableView, onGetCell: @escaping OnGetCell) {
        self.onGetCell = onGetCell
        self.tableView = tableView
    }
    
    public func load(_ query: CoreDataQuery? = nil, orderBy: CoreDataOrderBy, sectionBy: CoreDataQueryKey? = nil, options: CoreDataQueryOptions? = nil) throws {
        self.fetchedResultsController = try self.context.fetchResults(EntityType.self, query, orderBy: orderBy, sectionBy: sectionBy, options: options)
        try reload()
    }

    open override func filter() {
        super.filter()
        self.tableView?.reloadData()
    }
}
