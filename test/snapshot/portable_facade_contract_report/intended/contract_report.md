# Contract Report

- schema version: `6`
- backend id: `reflaxe.rust`
- contract: `portable`
- family std pin found: `yes`
- family std pin file: `family/family_std_pin.json`
- family std pin name: `reflaxe.family.std`
- family std pin version: `0.1.0-bootstrap.1`
- family std pin source: `in-repo-bootstrap`
- family std migration mode: `dual-run`
- strict boundary: `no`
- strict examples: `yes`
- metal fallback allowed: `no`
- metal contract hard error: `no`
- no hxrt: `no`
- async enabled: `no`
- nullable strings: `yes`
- portable native import strict: `no`
- portable native imports detected: `no`
- used module count: `34`

## Native Import Hits
- none

## Typed Native Import Hits
- none

## Consumed Surfaces
- `reflaxe.std.Option` (`portable_facade` -> `core::option::Option<T>`, no-hxrt eligible: `yes`)
- `reflaxe.std.Result` (`portable_facade` -> `core::result::Result<T,E>`, no-hxrt eligible: `yes`)

## Native Representation Plan
- `reflaxe.std.Option` -> `core::option::Option<T>` (`admitted_portable_facade`)
- `reflaxe.std.Result` -> `core::result::Result<T,E>` (`admitted_portable_facade`)

## Warnings
- none

## Errors
- none
