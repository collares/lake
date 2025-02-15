/-
Copyright (c) 2022 Mac Malone. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Mac Malone
-/
import Lake.Build.Trace
import Lake.Config.LeanLib

namespace Lake
open Std System

/-- A buildable Lean module of a `LeanLib`. -/
structure Module where
  lib : LeanLib
  name : Name
  /--
  The name of the module as a key.
  Used to create private modules (e.g., executable roots).
  -/
  keyName : Name := name
  deriving Inhabited

abbrev ModuleSet := RBTree Module (·.name.quickCmp ·.name)
@[inline] def ModuleSet.empty : ModuleSet := RBTree.empty

abbrev ModuleMap (α) := RBMap Module α (·.name.quickCmp ·.name)
@[inline] def ModuleMap.empty : ModuleMap α := RBMap.empty

/-- Locate the named module in the library (if it is buildable and local to it). -/
def LeanLib.findModule? (mod : Name) (self : LeanLib) : Option Module :=
  if self.isBuildableModule mod then some {lib := self, name := mod} else none

/-- Get an `Array` of the library's modules. -/
def LeanLib.getModuleArray (self : LeanLib) : IO (Array Module) :=
  (·.2) <$> StateT.run (s := #[]) do
    self.config.globs.forM fun glob => do
      glob.forEachModuleIn self.srcDir fun mod => do
        modify (·.push {lib := self, name := mod})

namespace Module

abbrev pkg (self : Module) : Package :=
  self.lib.pkg

@[inline] def rootDir (self : Module) : FilePath :=
  self.lib.rootDir

@[inline] def filePath (dir : FilePath) (ext : String) (self : Module) : FilePath :=
  Lean.modToFilePath dir self.name ext

@[inline] def srcPath (ext : String) (self : Module) : FilePath :=
  self.filePath self.lib.srcDir ext

@[inline] def leanFile (self : Module) : FilePath :=
  self.srcPath "lean"

@[inline] def leanLibPath (ext : String) (self : Module) : FilePath :=
  self.filePath self.pkg.oleanDir ext

@[inline] def oleanFile (self : Module) : FilePath :=
  self.leanLibPath "olean"

@[inline] def ileanFile (self : Module) : FilePath :=
  self.leanLibPath "ilean"

@[inline] def traceFile (self : Module) : FilePath :=
  self.leanLibPath "trace"

@[inline] def irPath (ext : String) (self : Module) : FilePath :=
  self.filePath self.pkg.irDir ext

@[inline] def cFile (self : Module) : FilePath :=
  self.irPath "c"

@[inline] def cTraceFile (self : Module) : FilePath :=
  self.irPath "c.trace"

@[inline] def oFile (self : Module) : FilePath :=
  self.irPath "o"

@[inline] def dynlibName (self : Module) : String :=
  -- NOTE: file name MUST be unique on Windows
  self.name.toStringWithSep "-" (escape := true)

@[inline] def dynlibFile (self : Module) : FilePath :=
  self.pkg.libDir / nameToSharedLib self.dynlibName

@[inline] def buildType (self : Module) : BuildType :=
  self.lib.buildType

@[inline] def leanArgs (self : Module) : Array String :=
  self.lib.leanArgs

@[inline] def leancArgs (self : Module) : Array String :=
  self.lib.leancArgs

@[inline] def linkArgs (self : Module) : Array String :=
  self.lib.linkArgs

@[inline] def shouldPrecompile (self : Module) : Bool :=
  self.lib.precompileModules

@[inline] def nativeFacets (self : Module) : Array (ModuleFacet (BuildJob FilePath)) :=
  self.lib.nativeFacets

@[inline] def isLeanOnly (self : Module) : Bool :=
  self.pkg.isLeanOnly && !self.shouldPrecompile

/-! ## Trace Helpers -/

protected def getMTime (self : Module) : IO MTime := do
  return mixTrace (← getMTime self.oleanFile) (← getMTime self.ileanFile)

instance : GetMTime Module := ⟨Module.getMTime⟩

protected def computeHash (self : Module) : IO Hash := do
  return mixTrace (← computeHash self.oleanFile) (← computeHash self.ileanFile)

instance : ComputeHash Module IO := ⟨Module.computeHash⟩

protected def checkExists (self : Module) : BaseIO Bool := do
  return (← checkExists self.oleanFile) && (← checkExists self.ileanFile)

instance : CheckExists Module := ⟨Module.checkExists⟩
