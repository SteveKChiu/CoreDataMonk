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

public class ViewDataProvider<EntityType: NSManagedObject> {
    private var controller: NSFetchedResultsController?
    private var filteredSections: [[EntityType]]?
    
    public typealias ObjectFilter = ([[EntityType]]) -> [[EntityType]]
    public var objectFilter: ObjectFilter?
    
    public var fetchedResultsController: NSFetchedResultsController? {
        get {
            return self.controller
        }
        set {
            self.controller = newValue
        }
    }
    
    public func numberOfSections() -> Int {
        if let sections = self.filteredSections {
            return sections.count
        } else {
            return self.controller?.sections?.count ?? 0
        }
    }
    
    public func numberOfObjectsInSection(section: Int) -> Int {
        if let sections = self.filteredSections {
            if section < sections.count {
                return sections[section].count
            }
        } else {
            if let sections = self.controller?.sections where section < sections.count {
                return sections[section].numberOfObjects
            }
        }
        return 0
    }
    
    public func objectAtIndexPath(indexPath: NSIndexPath) -> EntityType? {
        if let sections = self.filteredSections {
            if indexPath.section < sections.count {
                let objects = sections[indexPath.section]
                if indexPath.item < objects.count {
                    return objects[indexPath.item]
                }
            }
            return nil
        } else {
            return self.controller?.objectAtIndexPath(indexPath) as? EntityType
        }
    }

    public func indexPathForObject(object: EntityType) -> NSIndexPath? {
        if let sections = self.filteredSections {
            for (sidx, section) in sections.enumerate() {
                for (idx, item) in section.enumerate() {
                    if item == object {
                        return NSIndexPath(forItem: idx, inSection: sidx)
                    }
                }
            }
            return nil
        } else {
            return self.controller?.indexPathForObject(object)
        }
    }

    public func filter() {
        if let objectFilter = self.objectFilter,
               sections = self.controller?.sections {
            var filteredSections = [[EntityType]]()
            for section in sections {
                if let objects = section.objects as? [EntityType] {
                    filteredSections.append(objects)
                } else {
                    filteredSections.append([EntityType]())
                }
            }
            self.filteredSections = objectFilter(filteredSections)
        } else {
            self.filteredSections = nil
        }
    }

    public func reload() throws {
        try self.fetchedResultsController?.performFetch()
        self.filter()
    }
}
