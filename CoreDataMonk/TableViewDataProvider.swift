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
    var updatedIndexPaths: Set<NSIndexPath> = []
    var isFiltering = false
    
    var tableView: UITableView? {
        return self.provider?.tableView
    }
    
    var controller: NSFetchedResultsController? {
        return self.provider?.fetchedResultsController
    }

    init(provider: TableViewDataProvider<EntityType>) {
        self.provider = provider
    }
    
    @objc func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return self.provider?.numberOfSections() ?? 0
    }

    @objc func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.provider?.numberOfObjectsInSection(section) ?? 0
    }
    
    @objc func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        if let object = self.provider?.objectAtIndexPath(indexPath),
               cell = self.provider?.onGetCell?(object, indexPath) {
            return cell
        }
        return UITableViewCell()
    }
    
    @objc func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if let sectionCount = self.provider?.numberOfSections() where sectionCount != self.controller?.sections?.count {
            if let onGetSectionTitle = self.provider?.onGetSectionTitle where section < sectionCount {
                return onGetSectionTitle("", section)
            }
            return nil
        }
        
        if let sections = self.controller?.sections where section < sections.count {
            let title = sections[section].name
            if let onGetSectionTitle = self.provider?.onGetSectionTitle {
                return onGetSectionTitle(title, section)
            }
            return title
        }
        
        return nil
    }
    
    @objc func sectionIndexTitlesForTableView(tableView: UITableView) -> [String]? {
        if let sectionCount = self.provider?.numberOfSections() where sectionCount != self.controller?.sections?.count {
            return nil
        } else {
            return self.controller?.sectionIndexTitles
        }
    }
    
    @objc func tableView(tableView: UITableView, sectionForSectionIndexTitle title: String, atIndex index: Int) -> Int {
        if let sectionCount = self.provider?.numberOfSections() where sectionCount != self.controller?.sections?.count {
            return 0
        } else {
            return self.controller?.sectionForSectionIndexTitle(title, atIndex: index) ?? 0
        }
    }
    
    @objc func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        return self.provider?.onDeleteCell != nil
    }

    @objc func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == .Delete {
            if let onDeleteCell = self.provider?.onDeleteCell,
                   object = self.provider?.objectAtIndexPath(indexPath) {
                onDeleteCell(object, indexPath)
            }
        }
    }
    
    @objc func controllerWillChangeContent(controller: NSFetchedResultsController) {
        self.updatedIndexPaths.removeAll()
        self.isFiltering = self.provider?.objectFilter != nil
        
        if !self.isFiltering {
            self.tableView?.beginUpdates()
        }
    }

    @objc func controller(controller: NSFetchedResultsController, didChangeObject anObject: AnyObject, atIndexPath indexPath: NSIndexPath?, forChangeType type: NSFetchedResultsChangeType, newIndexPath: NSIndexPath?) {
        if self.isFiltering {
            return
        }
        
        switch type {
        case .Insert:
            self.tableView?.insertRowsAtIndexPaths([ newIndexPath! ], withRowAnimation: .Automatic)
            
        case .Delete:
            self.tableView?.deleteRowsAtIndexPaths([ indexPath! ], withRowAnimation: .Automatic)
            self.updatedIndexPaths.remove(indexPath!)
            
        case .Move:
            self.tableView?.deleteRowsAtIndexPaths([ indexPath! ], withRowAnimation: .Automatic)
            self.tableView?.insertRowsAtIndexPaths([ newIndexPath! ], withRowAnimation: .Automatic)
            self.updatedIndexPaths.remove(indexPath!)
            
        case .Update:
            self.updatedIndexPaths.insert(indexPath!)
        }
    }
    
    @objc func controller(controller: NSFetchedResultsController, didChangeSection sectionInfo: NSFetchedResultsSectionInfo, atIndex sectionIndex: Int, forChangeType type: NSFetchedResultsChangeType) {
        if self.isFiltering {
            return
        }

        switch type {
        case .Insert:
            self.tableView?.insertSections(NSIndexSet(index: sectionIndex), withRowAnimation: .Automatic)
            
        case .Delete:
            self.tableView?.deleteSections(NSIndexSet(index: sectionIndex), withRowAnimation: .Automatic)
            
        default:
            break
        }
    }
    
    @objc func controller(controller: NSFetchedResultsController, sectionIndexTitleForSectionName sectionName: String) -> String? {
        if let onGetIndexTitle = self.provider?.onGetIndexTitle {
            return onGetIndexTitle(sectionName)
        }
        return sectionName
    }

    @objc func controllerDidChangeContent(controller: NSFetchedResultsController) {
        if self.isFiltering {
            self.provider?.filter()
            return
        }

        self.tableView?.endUpdates()
        
        if !self.updatedIndexPaths.isEmpty {
            let indexPaths = Array(self.updatedIndexPaths)
            self.updatedIndexPaths.removeAll()
            self.tableView?.reloadRowsAtIndexPaths(indexPaths, withRowAnimation: .Automatic)
        }
    }
}

//---------------------------------------------------------------------------

public class TableViewDataProvider<EntityType: NSManagedObject> : ViewDataProvider<EntityType> {
    public let context: CoreDataMainContext
    private var bridge: TableViewDataBridge<EntityType>!
    
    public typealias OnGetCellCallbck = (EntityType, NSIndexPath) -> UITableViewCell
    public typealias OnDeleteCellCallbck = (EntityType, NSIndexPath) -> Void
    public typealias OnGetSectionTitle = (String, Int) -> String
    public typealias OnGetIndexTitle = (String) -> String
    
    public var onGetCell: OnGetCellCallbck?
    public var onDeleteCell: OnDeleteCellCallbck?
    public var onGetSectionTitle: OnGetSectionTitle?
    public var onGetIndexTitle: OnGetIndexTitle?
    
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
        self.bridge = TableViewDataBridge<EntityType>(provider: self)
    }
    
    public func bind(tableView: UITableView, onGetCell: OnGetCellCallbck) {
        self.onGetCell = onGetCell
        self.tableView = tableView
    }
    
    public func load(query: CoreDataQuery? = nil, orderBy: CoreDataOrderBy, sectionBy: CoreDataQueryKey? = nil, options: CoreDataQueryOptions? = nil) throws {
        self.fetchedResultsController = try self.context.fetchResults(EntityType.self, query, orderBy: orderBy, sectionBy: sectionBy, options: options)
        try reload()
    }

    public override func filter() {
        super.filter()
        self.tableView?.reloadData()
    }
}
