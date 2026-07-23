# begin Nimble config (version 2)
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config

switch("nimcache", thisDir() & "/build/nimcache")
