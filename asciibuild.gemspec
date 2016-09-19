Gem::Specification.new do |s|
  s.name           = 'asciibuild'
  s.version        = '0.2.0'
  s.date           = '2016-09-08'
  s.summary        = "Process orchestrator based on Asciidoc"
  s.description    = "Orchestrate and document processes by inlining executable code into an Asciidoc document"
  s.authors        = ["Jon Brisbin"]
  s.email          = 'jon@jbrisbin.com'
  s.files          = [
    "lib/asciibuild.rb",
    "lib/asciibuild/extensions.rb",
    "stylesheets/colony.css"
  ]
  s.executables    = ["asciibuild"]
  s.homepage       = 'http://github.com/jbrisbin/asciibuild'
  s.license        = 'Apache-2.0'
  s.require_paths  = ["lib"]

  s.add_dependency "asciidoctor", "~> 1.5"
  s.add_dependency "pygments.rb", "~> 0.6"
  s.add_dependency "mustache", "~> 1.0"
end
