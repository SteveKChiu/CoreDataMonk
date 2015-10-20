Pod::Spec.new do |s|

  s.name         = "CoreDataMonk"
  s.version      = "0.9.6"

  s.summary      = "A flexible and easy-to-use CoreData library for Swift"
  s.description  = <<-DESC
      CoreDataMonk is a helper library to make using CoreData easier and safer in the concurrent setup.
      The main features of CoreDataMonk are:

      + Allow you to setup CoreData in different ways easily
        (three tier, two-tier with auto merge, multiple main context with manual reload, etc...)
      + API that is easy to use and understand
      + Swift friendly query expression
      + Serialized update to avoid data consistency problem (optional)
      + Use Swift 2.0 error handling model
  DESC

  s.homepage     = "https://github.com/SteveKChiu/CoreDataMonk"
  s.license      = { :type => "MIT", :file => "LICENSE" }
  s.author       = { "Steve K. Chiu" => "steve.k.chiu@gmail.com" }

  s.ios.deployment_target = "8.0"
  s.source       = { :git => "https://github.com/SteveKChiu/CoreDataMonk.git", :tag => "v" + s.version.to_s }
  s.source_files = "CoreDataMonk", "CoreDataMonk/**/*.{swift}"
  s.frameworks   = "Foundation", "UIKit", "CoreData"
  s.requires_arc = true

end
