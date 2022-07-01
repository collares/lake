/-
Copyright (c) 2021 Mac Malone. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Mac Malone
-/
import Lean.Elab.Frontend
import Lake.DSL.Attributes
import Lake.DSL.Extensions
import Lake.Config.ModuleFacetConfig
import Lake.Config.PackageFacetConfig
import Lake.Config.TargetConfig

namespace Lake
open Lean System

/-- Main module `Name` of a Lake configuration file. -/
def configModuleName : Name := `lakefile

/-- The default name of the Lake configuration file (i.e., `lakefile.lean`). -/
def defaultConfigFile : FilePath := "lakefile.lean"

/-- Evaluate a `package` declaration to its respective `PackageConfig`. -/
unsafe def evalPackageDecl (env : Environment) (declName : Name)
(dir : FilePath) (args : List String := []) (leanOpts := Options.empty)
: LogIO PackageConfig := do
  let m := env.evalConstCheck IOPackager leanOpts ``IOPackager declName
  if let Except.ok ioPackager := m.run.run then
    logWarning "Support for IO in package declarations may be dropped. Raise an issue if you disagree."
    return ← ioPackager dir args
  let m := env.evalConstCheck Packager leanOpts ``Packager declName
  if let Except.ok packager := m.run.run then
    logWarning "Package parameters have been deprecated. Use __dir__ or __args__ instead."
    return packager dir args
  let m := env.evalConstCheck PackageConfig leanOpts ``PackageConfig declName
  if let Except.ok config := m.run.run then
    return config
  error <| s!"unexpected type at `{declName}`, " ++
    "`Lake.IOPackager`, `Lake.Packager`, or `Lake.PackageConfig` expected"

/-- Evaluate a `script` declaration to its respective `Script`. -/
unsafe def evalScriptDecl
(env : Environment) (declName : Name) (leanOpts := Options.empty) : IO Script := do
  let fn ← IO.ofExcept <| Id.run <| ExceptT.run <|
    env.evalConstCheck ScriptFn leanOpts ``ScriptFn declName
  return {fn, doc? := (← findDocString? env declName)}

deriving instance BEq, Hashable for Import

/- Cache for the imported header environment of Lake configuration files. -/
initialize importEnvCache : IO.Ref (Std.HashMap (List Import) Environment) ← IO.mkRef {}

/-- Like `Lean.Elab.processHeader`, but using `importEnvCache`. -/
def processHeader (header : Syntax) (opts : Options) (trustLevel : UInt32)
(inputCtx : Parser.InputContext) : StateT MessageLog IO Environment := do
  try
    let imports := Elab.headerToImports header
    if let some env := (← importEnvCache.get).find? imports then
      return env
    let env ← importModules imports opts trustLevel
    importEnvCache.modify (·.insert imports env)
    return env
  catch e =>
    let pos := inputCtx.fileMap.toPosition <| header.getPos?.getD 0
    modify (·.add { fileName := inputCtx.fileName, data := toString e, pos })
    mkEmptyEnvironment

namespace Package

/-- Unsafe implementation of `load`. -/
unsafe def loadUnsafe (dir : FilePath) (args : List String := [])
(configFile := dir / defaultConfigFile) (leanOpts := Options.empty)
: LogIO Package := do

  -- Read File & Initialize Environment
  let input ← IO.FS.readFile configFile
  let inputCtx := Parser.mkInputContext input configFile.toString
  let (header, parserState, messages) ← Parser.parseHeader inputCtx
  let (env, messages) ← processHeader header leanOpts 1024 inputCtx messages
  let env := env.setMainModule configModuleName

  -- Configure Extensions
  let env := dirExt.setState env dir
  let env := argsExt.setState env args

  -- Elaborate File
  let commandState := Elab.Command.mkState env messages leanOpts
  let s ← Elab.IO.processCommands inputCtx parserState commandState
  for msg in s.commandState.messages.toList do
    match msg.severity with
    | MessageSeverity.information => logInfo (← msg.toString)
    | MessageSeverity.warning     => logWarning (← msg.toString)
    | MessageSeverity.error       => logError (← msg.toString)

  -- Extract Configuration
  let env := s.commandState.env
  if !s.commandState.messages.hasErrors then
    match packageAttr.ext.getState env |>.toList with
    | [] => error s!"configuration file is missing a `package` declaration"
    | [pkgDeclName] =>
      -- Load Package Configuration
      let config ← evalPackageDecl env pkgDeclName dir args leanOpts
      unless config.dependencies.isEmpty do
        logWarning "Syntax for package dependencies has changed. Use the new `require` syntax."
      unless config.moreLibTargets.isEmpty do
        logWarning "Syntax for `moreLibTargets` has changed. Use the new `extern_lib` syntax."
      if config.defaultFacet = PackageFacet.bin then
        logWarning "The `bin` package facet has been deprecated in favor of `exe`."
      if config.defaultFacet = PackageFacet.oleans then
        logWarning "The `oleans` package facet has been deprecated in favor of `leanLib`."
      let config := {config with dependencies := depsExt.getState env ++ config.dependencies}
      -- Tag Load Helpers
      let mkTagMap {α} (attr) (f : Name → IO α) : IO (NameMap α) :=
        attr.ext.getState env |>.foldM (init := {}) fun map declName =>
          return map.insert declName <| ← f declName
      let evalConst (α typeName declName) : IO α :=
        IO.ofExcept (env.evalConstCheck α leanOpts typeName declName).run.run
      let evalConstMap {α β} (f : α → β) (declName) : IO β :=
        match env.evalConst α leanOpts declName with
        | .ok a => pure <| f a
        | .error e => throw <| IO.userError e
       -- Load Target & Script Configurations
      let scripts ← mkTagMap scriptAttr
        (evalScriptDecl env · leanOpts)
      let leanLibConfigs ← mkTagMap leanLibAttr
        (evalConst LeanLibConfig ``LeanLibConfig)
      let leanExeConfigs ← mkTagMap leanExeAttr
        (evalConst LeanExeConfig ``LeanExeConfig)
      let externLibConfigs ← mkTagMap externLibAttr
        (evalConst ExternLibConfig ``ExternLibConfig)
      let opaqueModuleFacetConfigs ← mkTagMap moduleFacetAttr
        (evalConstMap OpaqueModuleFacetConfig.mk)
      let opaquePackageFacetConfigs ← mkTagMap packageFacetAttr
        (evalConstMap OpaquePackageFacetConfig.mk)
      let opaqueTargetConfigs ← mkTagMap targetAttr
        (evalConstMap OpaqueTargetConfig.mk)
      let defaultTargets := defaultTargetAttr.ext.getState env |>.toArray
      -- Construct the Package
      if leanLibConfigs.isEmpty && leanExeConfigs.isEmpty && config.defaultFacet ≠ .none then
        logWarning <| "Package targets are deprecated. " ++
          "Add a `lean_exe` and/or `lean_lib` default target to the package instead."
      return {
        dir, config, scripts,
        leanLibConfigs, leanExeConfigs, externLibConfigs,
        opaqueModuleFacetConfigs, opaquePackageFacetConfigs, opaqueTargetConfigs,
        defaultTargets
      }
    | _ => error s!"configuration file has multiple `package` declarations"
  else
    error s!"package configuration `{configFile}` has errors"

/--
Load the package located in
the given directory with the given configuration file.
-/
@[implementedBy loadUnsafe]
opaque load (dir : FilePath) (args : List String := [])
(configFile := dir / defaultConfigFile) (leanOpts := Options.empty) : LogIO Package
