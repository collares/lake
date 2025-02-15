/-
Copyright (c) 2021 Mac Malone. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Mac Malone
-/
import Lean.Attributes

open Lean
namespace Lake

initialize packageAttr : TagAttribute ←
  registerTagAttribute `package "mark a definition as a Lake package configuration"

initialize packageDepAttr : TagAttribute ←
  registerTagAttribute `packageDep "mark a definition as a Lake package dependency"

initialize scriptAttr : TagAttribute ←
  registerTagAttribute `script "mark a definition as a Lake script"

initialize leanLibAttr : TagAttribute ←
  registerTagAttribute `leanLib "mark a definition as a Lake Lean library target configuration"

initialize leanExeAttr : TagAttribute ←
  registerTagAttribute `leanExe "mark a definition as a Lake Lean executable target configuration"

initialize externLibAttr : TagAttribute ←
  registerTagAttribute `externLib "mark a definition as a Lake external library target"

initialize targetAttr : TagAttribute ←
  registerTagAttribute `target "mark a definition as a custom Lake target"

initialize defaultTargetAttr : TagAttribute ←
  registerTagAttribute `defaultTarget "mark a Lake target as the package's default"
    fun name => do
      let valid ← getEnv <&> fun env =>
        leanLibAttr.hasTag env name ||
        leanExeAttr.hasTag env name ||
        externLibAttr.hasTag env name ||
        targetAttr.hasTag env name
      unless valid do
        throwError "attribute `defaultTarget` can only be used on a target (e.g., `lean_lib`, `lean_exe`)"

initialize moduleFacetAttr : TagAttribute ←
  registerTagAttribute `moduleFacet "mark a definition as a Lake module facet"

initialize packageFacetAttr : TagAttribute ←
  registerTagAttribute `packageFacet "mark a definition as a Lake package facet"

initialize libraryFacetAttr : TagAttribute ←
  registerTagAttribute `libraryFacet "mark a definition as a Lake library facet"
