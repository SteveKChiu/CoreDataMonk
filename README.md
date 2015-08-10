CoreDataMonk
============

CoreDataMonk is a helper library to make using CoreData easier and safer in the concurrent setup.
The main features of CoreDataMonk are:

+ Allow you to setup CoreData in different ways easily
(three tier, two-tier with auto merge, multiple main context with manual reload, etc...)
+ API that is easy to use and understand
+ Swift friendly query expression
+ Serialized update to avoid data consistency problem (optional)
+ Use exception for error handling

CoreDataMonk class
------------------

CoreDataMonk provides some class that you may need to know, here is the relationship with CoreData class:

CoreDataMonk class      | CoreData classes
------------------------|-----------------
`CoreDataStack`         | `NSPersistentStoreCoordinator`, `NSManagedObjectContext` (PrivateQueueConcurrencyType, root saving context, optional)
`CoreDataMainContext`   | `NSManagedObjectContext` (MainQueueConcurrencyType, main context), it is sub class of `CoreDataContext`
`CoreDataContext`       | none, but it act as factory to create `CoreDataUpdateContext`
`CoreDataUpdateContext` | `NSManagedObjectContext` (PrivateQueueConcurrencyType, update context)
`CoreDataUpdate`        | interface to `CoreDataUpdateContext`

You only need to explicitly create `CoreDataStack` and `CoreDataMainContext` as in the getting started section, other classes are created via methods and can not be created by user.

You may need to create `CoreDataContext` if you are using custom setup, please see more info in the advance setup section.

Getting started
---------------

Setup CoreDataMonk is easy, and the default provides three-tier `NSManagedObjectContext` setup,
that is good for most applications. You can do this with:

````swift
// first pick the name you want for the global main context
var World: CoreDataMainContext!

// then in your AppDelegate
func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
    do {
        let dataStack = try CoreDataStack()
        try dataStack.addDatabaseStore()
        World = try CoreDataMainContext(stack: dataStack)

        ...
    } catch let error {
        fatalError("fail to init core data: \(error)")
    }
    ...
}
````

It is possible to use multiple store by the configuration in Xcode model:

````swift
func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
    do {
        let dataStack = try CoreDataStack()
        try dataStack.addInMemoryStore(configuration: "InMemory")
        try dataStack.addDatabaseStore(configuration: "Database", resetOnFailure: true)
        World = try CoreDataMainContext(stack: dataStack)

        ...
    } catch let error {
        fatalError("fail to init core data: \(error)")
    }
    ...
}
````

Fetch object
------------

OK now you can fetch data from main context in the view controller:

````swift
// you can add % prefix to tell CoreDataMonk it is for key name
let monk = try World.fetch(Person.self, %"name" == "Monk")

let warrior = try World.fetch(Person.self, %"name" == "Warrior" && %"location" == "Taipei")

````

To fetch a list of objects:

````swift
let monks = try World.fetchAll(Person.self)
````

To give more conditions:

````swift
let monks = try World.fetchAll(Person.self,
    %"age" >= 18 || %"location" == "Taipei",
    orderBy: .Ascending("name") | .Descending("age"),
    options: .Limit(100) | .Offset(20)
)
````

And you can query value too:

````swift
let age = try World.queryValue(Person.self, .Average("age")) as! NSNumber
````

And of course more values:

````swift
let info_list = try World.query(Person.self,
    .Select("location") | .Average("age"),
    %"name" == "Monk",
    orderBy: .Descending("age"),
    groupBy: %"location"
)

for info in info_list {
    let location = info["location"] as! String
    let age = info["age"] as! NSNumber
    ...
}
````

Create and update object
------------------------

To create or update object, you have to call `.beginUpdate()`, and you need to call `.commit()` before the block ends,
otherwise all changes will be discarded.


````swift
World.beginUpdate() {
    update in

    let farmer = try update.create(Person.self)
    farmer.name = "Framer"
    farmer.age = 28

    let knight = try update.fetchOrCreate(Person.self, %"name" == "Knight" && %"age" == 18)
    knight.friend = farmer

    let monk = try update.fetch(Person.self, %"name" == "Monk")
    monk.age = 44
    monk.friend = knight

    try update.commit()
}

// or you prefer to wait for the update to complete
World.beginUpdateAndWait() {
    update in

    ...
}
````

If you already fetch object in the main context, you can use that in the update:

````swift
let warrior = try World.fetch(Person.self, %"name" == "Warrior" && %"location" == "Taipei")

World.beginUpdate() {
    update in

    let warrior = try update.use(warrior)

    let monk = try update.fetch(Person.self, %"name" == "Monk")
    monk.friend = warrior

    try update.commit()
}
````

Update can be used in nested block. The changes are discarded only after it is de-inited.
For example, if you need to fetch data from server to update data:

````swift
World.beginUpdate() {
    update in

    let monk = try update.fetch(Person.self, %"name" == "Monk")

    // this will start network connection and return result in callback block
    remote_server.findAge(monk.name, location: monk.location) {
        age in

        // you need to call .perform() in nested block
        update.perform() {
            update in

            // it is safe to use the object directly in the same update
            monk.age = age

            try update.commit()
        }
    }
}
````

If the update takes multiple steps and can not be done in one block, you can use `.beginUpdateContext()`:

````swift
let context = World.beginUpdateContext()

context.perform() {
    update in

    ...
}

...

context.perform() {
    update in

    ...
}

...

context.perform() {
    update in

    ...
    try update.commit()
}
````

In fact, `.beginUpdate()` is just a temporary update context with perform:
````swift
public func beginUpdate(block: (CoreDataUpdate) throws -> Void) {
    beginUpdateContext().perform(block)
}
````

Predicate expression
--------------------

CoreDataMonk add some syntactic sugar to the predicate expression, so the code looks more natural.

First you need a way specify key name, thus not to confuse with constant value:

Expression              | Example                   | Description
------------------------|---------------------------|-------------
`%String`               | `%"name"`                 | key "name"
`%String%.any`          | `%"friend.age"%.any`      | key "friend.age" with ANY modifier
`%String%.all`          | `%"friend.age"%.all`      | key "friend.age" with ALL modifier

CoreDataMonk has some mappings to the predicate:

Expression                | Example                     | Description
--------------------------|-----------------------------|-------------
`%String == Any`          | `%"name" == "monk"`         | The same as `NSPredicate(format: "%K == %@", "name", "monk")`
`%String == %String`      | `%"name" == %"location"`    | The same as `NSPredicate(format: "%K == %K", "name", "location")`
`!=`, `>`, `<`, `>=`, `<=` |                            | Just like `==`
`.Where(String, Any...)`  | `.Where("name like %@", pattern)` | The same as `NSPredicate(format: "name like %@", pattern)`
`.Predicate(NSPredicate)` | `.Predicate(my_predicate)`  | The same as `my_predicate`

You use `&&`, `||` and `!` operators to combine predicate:

Operator    | Example                               | Description
------------|---------------------------------------|-------------
`&&`        | `%"name" == name && %"age" > age`     | The same as `NSPredicate(format: "name == %@ and age > %@", name, age)`
`||`        | `%"name" == name || %"name" == name + " sam"` | The same as `NSPredicate(format: "name == %@ or name = %@", name, name + " sam")`
`!`         | `!(%"name" == name && %"age" > age)`  | The same as `NSPredicate(format: "not (name == %@ and age > %@)", name, age)`

`orderBy:` expression
---------------------

The `orderBy:` is supported by `.fetchAll`, `.fetchResults` and `.query` methods:

Expression              | Example                   | Description
------------------------|---------------------------|-------------
`.Ascending(String)`    | `.Ascending("name")`      | The same as `NSSortDescriptor(key: "name", ascending: true)`
`.Descending(String)`   | `.Descending("name")`     | The same as `NSSortDescriptor(key: "name", ascending: false)`

You can use `|` operator to combine two or more expressions:

Operator    | Example                                        | Description
------------|------------------------------------------------|-------------
`|`         | `.Ascending("name") | .Descending("location")` | The same as `[NSSortDescriptor(key: "name", ascending: true), NSSortDescriptor(key: "location", ascending: false)]`

`options:` expression
---------------------

You can set options to adjust `NSFetchRequest`, it is supported by all `.fetch` and `.query` methods:

Expression                  | Description
----------------------------|------------
`.NoSubEntities`            | `fetchRequest.includesSubentities = false`
`.NoPendingChanges`         | `fetchRequest.includesPendingChanges = false`
`.NoPropertyValues`         | `fetchRequest.includesPropertyValues = false`
`.Limit(Int)`               | `fetchRequest.fetchLimit = Int`
`.Offset(Int)`              | `fetchRequest.fetchOffset = Int`
`.Batch(Int)`               | `fetchRequest.fetchBatchSize = Int`
`.Prefetch([String])`       | `fetchRequest.relationshipKeyPathsForPrefetching = [String]`
`.PropertiesOnly([String])` | `fetchRequest.propertiesToFetch = [String]` // ignored in .query
`.Distinct`                 | `fetchRequest.returnsDistinctResults = true`
`.Tweak(NSFetchRequest -> Void)` | allow block to modify fetchRequest

You can use `|` operator to combine two or more options:

Operator    | Example                      | Description
------------|------------------------------|-------------
`|`         | `.Limit(200) | .Offset(100)` | The same as `[.Limit(200), .Offset(100)]`

`.query` and `.queryValue` select expression
--------------------------------------------

In `.query`, you need to specify the select targets you want to return. You can specify
property, expression or aggregated function. The aggregated function may have optional alias,
if user does not specify one, the default is to use property name. It is important to make sure
each select target having unique alias, as it is used as key in returned dictionary.

Expression                               | Description
-----------------------------------------|-------------
`.Select(String...)`                     | to get value of properties, `.Select("name", "age")` will add two targets
`.Expression(NSExpressionDescription)`   | to get value of  `my_expression`
`.Average(String, alias: String? = nil)` | to get average of property
`.Sum(String, alias: String? = nil)`     | to get sum of property
`.StdDev(String, alias: String? = nil)`  | to get standard deviation of property
`.Min(String, alias: String? = nil)`     | to get minimum value of property
`.Max(String, alias: String? = nil)`     | to get maximum value of property
`.Median(String, alias: String? = nil)`  | to get median value of property
`.Count(String, alias: String? = nil)`   | to get the number of returned values

You can use `|` operator to combine two or more select targets:

Operator    | Example                                           | Description
------------|---------------------------------------------------|-------------
`|`         | `.Average("age") | .Min("age", alias: "min_age")` | Combine them into select targets

`groupBy:` expression
---------------------

The same key expression, but only apply to by `.query` method:

Expression              | Example                   | Description
------------------------|---------------------------|-------------
`%String`               | `%"name"`                 | "name" as object property name

You can use `|` operator to combine two or more keys:

Operator    | Example                               | Description
------------|---------------------------------------|-------------
`|`         | `%"name" | %"location"`               | The same as `["name", "location"]`

`having:` expression
--------------------

The same as predicate expression, but only apply to `.query` method with `groupBy:`.

Data source for UITableView and UICollectionView
------------------------------------------------

Most applications will use `NSFetchedResultsController` together with `UITableView` or `UICollectionView`.
CoreDataMonk have two classes to make this easier, it is `TableViewDataProvider` and `CollectionViewDataProvider`.

Take `TableViewDataProvider` for example:

````swift
class MyViewController : UIViewController, UITableViewDelegate {
    @IBOutlet weak var tableView: UITableView!
    var dataProvider: TableViewDataProvider<Person>!

    override func viewDidLoad() {
        super.viewDidLoad()

        do {
            self.dataProvider = TableViewDataProvider(context: World).bind(self.tableView) {
                person, indexPath in

                let cell = self.tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath) as! MyTableCell
                cell.title.text = person.title
                ...
                return cell
            }

            try self.dataProvider.query(orderBy: .Ascending("title"))
        } catch let error {
            fatalError("fail to query main context: \(error)")
        }
    }
}
````

Advanced setup: default three-tier setup
----------------------------------------

By default CoreDataMonk provides three tier setup of `NSManagedObjectContext`, it looks like the following.
Note the `CoreDataUpdateContext` is temporary, it is created and then released after completed.

````
UPDATE                                     <-- MAIN.beginUpdate
[CoreDataUpdateContext]
(NSManagedObjectContext/PrivateQueue)
        |
        |
MAIN (Global)                               --> MAIN.fetch
[CoreDataMainContext]
(NSManagedObjectContext/MainQueue)
        |
        V
ROOT (OPTIONAL)
[CoreDataStack]
(NSManagedObjectContext/PrivateQueue)
        |
        |
STORE   V
[CoreDataStack]
(NSPersistentStoreCoordinator)
````

If you look at `.init` of `CoreDataStack`, you will find you can skip root context:

````swift
public enum RootContextType {
    case None
    case Shared
}

public init(modelName: String? = nil,
        bundle: NSBundle? = nil,
        rootContext: RootContextType = .Shared) throws
````

Advanced setup: Two-tier with auto merge
----------------------------------------

This is not the only way to setup CoreData, here is yet another popular setup. The TRANSACTION context
set its parent to ROOT, and MAIN get merged data from notification. The advantage is MAIN does not
have to handle all the merge work, it only need to merge registered objects, it may be faster in some cases.
The disadvantage is it may not get all the data, especially if you need some properties from relationship,
you may not get notification at all.

````
UPDATE                                     <-- MAIN.beginUpdate
[CoreDataUpdateContext]
(NSManagedObjectContext/PrivateQueue)
        |
        |           MAIN (Global)           --> MAIN.fetch
        |           [CoreDataMainContext]
        |           (NSManagedObjectContext/MainQueue)
        |              |         ^
        V              |         |
ROOT (OPTIONAL)        |         | MERGE via notification
[CoreDataStack]        V         |
(NSManagedObjectContext/PrivateQueue)
        |
        |
STORE   V
[CoreDataStack]
(NSPersistentStoreCoordinator)
````

You can easily setup this via CoreDataMonk, let's take a look at `.init` of `CoreDataMainContext`:

````swift
public enum UpdateTarget {
    case MainContext
    case RootContext(autoMerge: Bool)
    case PersistentStore
}

public enum UpdateOrder {
    case Serial
    case Default
}

public init(stack: CoreDataStack,
        updateTarget: UpdateTarget = .MainContext,
        updateOrder: UpdateOrder = .Default) throws
````

The `updateTarget` specify what is the parent context of `CoreDataUpdateContext`, the default is `.MainContext`.
Now we only need to change it to `.RootContext(autoMerge: true)` to have it connect to ROOT with auto merge, then we are done.

````swift
func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
    do {
        let dataStack = try CoreDataStack()
        try dataStack.addDatabaseStore(resetOnFailure: true)
        World = try CoreDataMainContext(stack: dataStack, updateTarget: .RootContext(autoMerge: true))

        ...
    } catch let error {
        fatalError("fail to init core data: \(error)")
    }
    ...
}
````

Note, you have to have ROOT context in order to make auto merge works, if you skip ROOT while create `CoreDataStack`,
then you have to merge to reload the context by yourself.

Advanced setup: Every ViewController has its own CoreDataMainContext
--------------------------------------------------------------------

This is yet another interesting setup, that you don't have merge at all, you simply reset the MAIN context after receive
commit notification.

````
UPDATE                                 <-- (UPDATER or MAIN).beginUpdate
[CoreDataUpdateContext]
(NSManagedObjectContext/PrivateQueue)
        |                                          UPDATER
        |                                          [CoreDataContext]
        |                                          (no NSManagedObjectContext)
        |
        |
        |       MAIN (ViewController1)             MAIN (ViewController2)
        |      [CoreDataMainContext]               [CoreDataMainContext]
        |      (NSManagedObjectContext/MainQueue)  (NSManagedObjectContext/MainQueue)
        |                |                             |
        |                |                             |
STORE   V                |                             |
[CoreDataStack]          V                             V
(NSPersistentStoreCoordinator)
````

There is no global `CoreDataMainContext`, and you create `CoreDataMainContext` in the `.viewDidLoad` method of `UIViewController`.

Also you may need to create global UPDATER (one or many, or just use MAIN), all the update is via UPDATER, `UIViewController` need register notification observer by `CoreDataContext.observeCommit`:

It is likely you don't want ROOT in this setup, just pass `.PersistentStore`, or `.RootContext(autoMerge: false)` if ROOT is still needed.

````swift
var DataStack: CoreDataStack!
var Updater: CoreDataContext!

class AppDelegate {
    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        do {
            DataStack = try CoreDataStack(rootContext: .None)
            try DataStack.addDatabaseStore(resetOnFailure: true)
            Updater = try CoreDataContext(stack: DataStack, updateTarget: .PersistentStore)
            ...
        } catch let error {
            fatalError("fail to init core data: \(error)")
        }
        ...
    }
    ...
}

class ViewController : UIViewController {
    var context: CoreDataMainContext!

    // it is important to keep this reference, it will removeObserver after it is de-inited
    var observer: AnyObject!

    override func viewDidLoad() {
        super.viewDidLoad()

        do {
            self.context = try CoreDataMainContext(stack: DataStack, updateTarget: .PersistentStore)
            self.observer = Updater.observeCommit() {
                self.context.reset()
                ...
                // reload data here
            }
            ...
        } catch let error {
            fatalError("fail to init main context: \(error)")
        }
    }
}

class BackgroundWorker {
    func process() {
        Updater.beginUpdate() {
            update in

            ...
        }
    }
}
````

Advanced setup: Force update in serial order
--------------------------------------------

By default CoreDataMonk will allow different threads to call `.beginUpdate` at the same time.
This is good for performance, but as you might think, if there are different threads working on
the same entity, it might have data race problem.

The problem may not be as serious as you think, that is why we allow it by default.
The key is how different threads process entities. In most cases, most applications use different threads
to process different entities, thus you don't have data race problem.

But if you do, you can pass `.Serial` while creating CoreDataMainContext:

````swift
func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
    do {
        let dataStack = try CoreDataStack()
        try dataStack.addDatabaseStore(resetOnFailure: true)
        World = try CoreDataMainContext(stack: dataStack, updateOrder: .Serial)

        ...
    } catch let error {
        fatalError("fail to init core data: \(error)")
    }
    ...
}
````

To be clear, each `.perform()` in the same update context is always in serial, it is different update contexts may have its `.perform()`
running at the same time.

What `updateOrder: .Serial` does is to ensure only one `.perform()` can be running at a time globally. But it might still have data
consistency problem if you are using long running update context, as there will be `.perform()` from other update context in between
your call to `.perform()` of the long running update context.

The rule to avoid that is actually very simple, just don't call `.beginUpdateContext()` if you are using `updateOrder: .Serial`,
use `.beginUpdate()` exclusively.

