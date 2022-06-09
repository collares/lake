/-
Copyright (c) 2021 Mac Malone. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Mac Malone
-/
import Lake.Build
import Lake.CLI.Error

open Lean (Name)

namespace Lake

def Package.defaultTarget (self : Package) : OpaqueTarget :=
  match self.defaultFacet with
  | .exe | .bin => self.exeTarget.withoutInfo
  | .staticLib => self.staticLibTarget.withoutInfo
  | .sharedLib => self.sharedLibTarget.withoutInfo
  | .leanLib | .oleans => self.libTarget.withoutInfo
  | .none => Target.nil

def parsePackageSpec (ws : Workspace) (spec : String) : Except CliError Package :=
  if spec.isEmpty then
    return ws.root
  else
    match ws.packageByName? spec.toName with
    | some pkg => return pkg
    | none => throw <| CliError.unknownPackage spec

def resolveModuleTarget (pkg : Package) (mod : Name) (facet : String) : Except CliError OpaqueTarget :=
  if pkg.hasModule mod then
    if facet.isEmpty || facet == "olean" then
      return pkg.moduleOleanTarget mod |>.withoutInfo
    else if facet == "c" then
      return pkg.moduleOleanAndCTarget mod |>.withoutInfo
    else if facet == "o" then
      return pkg.moduleOTarget mod |>.withoutInfo
    else
      throw <| CliError.unknownFacet "module" facet
  else
    throw <| CliError.missingModule pkg.name mod

def resolveLibTarget (pkg : Package) (lib : LeanLibConfig) (facet : String) : Except CliError OpaqueTarget :=
  if facet.isEmpty || facet == "lean" || facet == "oleans" then
    return pkg.mkLibTarget lib
  else if facet == "static" then
    return pkg.mkStaticLibTarget lib |>.withoutInfo
  else if facet == "shared" then
    return pkg.mkSharedLibTarget lib |>.withoutInfo
  else
    throw <| CliError.unknownFacet "library" facet

def resolveExeTarget (pkg : Package) (exe : LeanExeConfig) (facet : String) : Except CliError OpaqueTarget :=
  if facet.isEmpty || facet == "exe" then
    return pkg.mkExeTarget exe |>.withoutInfo
  else
    throw <| CliError.unknownFacet "executable" facet

def resolveTargetInPackage (pkg : Package) (target : Name) (facet : String) : Except CliError OpaqueTarget :=
  if let some exe := pkg.findExe? target then
    resolveExeTarget pkg exe facet
  else if let some lib := pkg.findLib? target then
    resolveLibTarget pkg lib facet
  else if pkg.hasModule target then
    resolveModuleTarget pkg target facet
  else
    throw <| CliError.missingTarget pkg.name (target.toString false)

def resolveDefaultPackageTarget (pkg : Package) : Except CliError OpaqueTarget :=
  if pkg.defaultTargets.isEmpty then
    return pkg.defaultTarget
  else
    return Target.collectOpaqueArray <| ←
      pkg.defaultTargets.mapM (resolveTargetInPackage pkg · "")

def resolvePackageTarget (pkg : Package) (facet : String) : Except CliError OpaqueTarget :=
  if facet.isEmpty then
    resolveDefaultPackageTarget pkg
  else if facet == "exe" || facet == "bin" then
    return pkg.exeTarget.withoutInfo
  else if facet == "staticLib" then
    return pkg.staticLibTarget.withoutInfo
  else if facet == "sharedLib" then
    return pkg.sharedLibTarget.withoutInfo
  else if facet == "leanLib" || facet == "oleans" then
    return pkg.libTarget.withoutInfo
  else
    throw <| CliError.unknownFacet "package" facet

def resolveTargetBaseSpec (ws : Workspace) (spec : String) (facet := "") : Except CliError OpaqueTarget := do
  match spec.splitOn "/" with
  | [spec] =>
    if spec.isEmpty then
      resolvePackageTarget ws.root facet
    else if spec.startsWith "@" then
      let pkg ← parsePackageSpec ws <| spec.drop 1
      resolvePackageTarget pkg facet
    else if spec.startsWith "+" then
      let mod := spec.drop 1 |>.toName
      if let some pkg := ws.packageForModule? mod then
        resolveModuleTarget pkg mod facet
      else
        throw <| CliError.unknownModule mod
    else
      if let some (pkg, exe) := ws.findExe? spec then
        resolveExeTarget pkg exe facet
      else if let some (pkg, lib) := ws.findLib? spec then
        resolveLibTarget pkg lib facet
      else if let some pkg := ws.packageByName? spec then
        resolvePackageTarget pkg facet
      else if let some pkg := ws.packageForModule? spec then
        resolveModuleTarget pkg spec facet
      else
        throw <| CliError.unknownTarget spec
  | [pkgSpec, targetSpec] =>
    let pkgSpec := if pkgSpec.startsWith "@" then pkgSpec.drop 1 else pkgSpec
    let pkg ← parsePackageSpec ws pkgSpec
    if targetSpec.startsWith "+" then
      let mod := targetSpec.drop 1 |>.toName
      resolveModuleTarget pkg mod facet
    else
      resolveTargetInPackage pkg spec facet
  | _ =>
    throw <| CliError.invalidTargetSpec spec '/'

def parseTargetSpec (ws : Workspace) (spec : String) : Except CliError OpaqueTarget := do
  match spec.splitOn ":" with
  | [spec] =>
    resolveTargetBaseSpec ws spec
  | [rootSpec, facet] =>
    resolveTargetBaseSpec ws rootSpec facet
  | _ =>
    throw <| CliError.invalidTargetSpec spec ':'

def parseTargetSpecs (ws : Workspace) (specs : List String) : Except CliError (List OpaqueTarget) :=
  specs.mapM <| parseTargetSpec ws
