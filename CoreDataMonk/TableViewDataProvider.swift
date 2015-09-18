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
    private unowned var provider: TableViewDataProvider<EntityType>
    
    private var tableView: UITableView? {
        return self.provider.tableView
    }
    
    private var resultsController: NSFetchedResultsController? {
        return self.provider.resultsController
    }

    private init(provider: TableViewDataProvider<EntityType>) {
        self.provider = provider
    }
    
    @objc func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return self.resultsController?.sections?.count ?? 0
    }

    @objc func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if let sections = self.resultsController?.sections where section < sections.count {
            return sections[section].numberOfObjects
        }
        return 0
    }
    
    @objc func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        if let object = self.resultsController?.objectAtIndexPath(indexPath) as? EntityType {
            if let cell = self.provider.onGetCell?(object, indexPath) {
                return cell
            }
        }
        return UITableViewCell()
    }
    
    @objc func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if let sections = self.resultsController?.sections where section < sections.count {
            let title = sections[section].name
            if let onGetSectionTitle = self.provider.onGetSectionTitle {
                return onGetSectionTitle(title, section)
            }
            return title
        }
        return nil
    }
    
    @objc func sectionIndexTitlesForTableView(tableView: UITableView) -> [String]? {
        return self.resultsController?.sectionIndexTitles
    }
    
    @objc func tableView(tableView: UITableView, sectionForSectionIndexTitle title: String, atIndex index: Int) -> Int {
        return self.resultsController?.sectionForSectionIndexTitle(title, atIndex: index) ?? 0
    }
    
    @objc func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        return self.provider.onDeleteCell != nil
    }

    @objc func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == .Delete {
            if let onDeleteCell = self.provider.onDeleteCell,
                   object = self.resultsController?.objectAtIndexPath(indexPath) as? EntityType {
                onDeleteCell(object, indexPath)
            }
        }
    }
    
    @objc func controllerWillChangeContent(controller: NSFetchedResultsController) {
        self.tableView?.beginUpdates()
    }

    @objc func controller(controller: NSFetchedResultsController, didChangeObject anObject: AnyObject, atIndexPath indexPath: NSIndexPath?, forChangeType type: NSFetchedResultsChangeType, newIndexPath: NSIndexPath?) {
        switch type {
        case .Insert:
            self.tableView?.insertRowsAtIndexPaths([ newIndexPath! ], withRowAnimation: .Automatic)
        case .Delete:
            self.tableView?.deleteRowsAtIndexPaths([ indexPath! ], withRowAnimation: .Automatic)
        case .Move:
            self.tableView?.deleteRowsAtIndexPaths([ indexPath! ], withRowAnimation: .Automatic)
            self.tableView?.insertRowsAtIndexPaths([ newIndexPath! ], withRowAnimation: .Automatic)
        case .Update:
            self.tableView?.reloadRowsAtIndexPaths([ indexPath! ], withRowAnimation: .Automatic)
        }
    }
    
    @objc func controller(controller: NSFetchedResultsController, didChangeSection sectionInfo: NSFetchedResultsSectionInfo, atIndex sectionIndex: Int, forChangeType type: NSFetchedResultsChangeType) {
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
        return self.provider.onGetIndexTitle?(sectionName)
    }

    @objc func controllerDidChangeContent(controller: NSFetchedResultsController) {
        self.tableView?.endUpdates()
    }
}

//---------------------------------------------------------------------------

public class TableViewDataProvider<EntityType: NSManagedObject> {
    private var bridge: TableViewDataBridge<EntityType>!
    
    public typealias OnGetCellCallbck = (EntityType, NSIndexPath) -> UITableViewCell
    public typealias OnDeleteCellCallbck = (EntityType, NSIndexPath) -> Void
    public typealias OnGetSectionTitle = (String, Int) -> String
    public typealias OnGetIndexTitle = (String) -> String

    public var onGetCell: OnGetCellCallbck?
    public var onDeleteCell: OnDeleteCellCallbck?
    public var onGetSectionTitle: OnGetSectionTitle?
    public var onGetIndexTitle: OnGetIndexTitle?

    public let context: CoreDataMainContext
    
    public var resultsController: NSFetchedResultsController? {
        willSet {
            self.resultsController?.delegate = nil
        }
        didSet {
            self.resultsController?.delegate = self.bridge
        }
    }

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

    public init(context: CoreDataMainContext) {
        self.context = context
        self.bridge = TableViewDataBridge<EntityType>(provider: self)
    }
    
    public func objectAtIndexPath(indexPath: NSIndexPath) -> EntityType? {
        return self.resultsController?.objectAtIndexPath(indexPath) as? EntityType
    }
    
    public func indexPathForObject(object: EntityType) -> NSIndexPath? {
        return self.resultsController?.indexPathForObject(object)
    }

    public func indexPathForObjectID(id: NSManagedObjectID) -> NSIndexPath? {
        do {
            let object = try self.context.fetch(EntityType.self, id: id)
            return self.resultsController?.indexPathForObject(object)
        } catch {
            return nil
        }
    }

    public func bind(tableView: UITableView, onGetCell: OnGetCellCallbck) -> TableViewDataProvider<EntityType> {
        self.onGetCell = onGetCell
        self.tableView = tableView
        return self
    }
    
    public func query(query: CoreDataQuery? = nil, orderBy: CoreDataOrderBy, sectionBy: CoreDataQueryKey? = nil, options: CoreDataQueryOptions? = nil) throws -> TableViewDataProvider<EntityType> {
        self.resultsController = try self.context.fetchResults(EntityType.self, query, orderBy: orderBy, sectionBy: sectionBy, options: options)
        try self.resultsController?.performFetch()
        self.tableView?.reloadData()
        return self
    }
}
