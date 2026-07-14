# Diagnostic Identifier Contract

Stable diagnostics begin with a machine-readable identifier such as
`[HXRS-NO-HXRT-ELIGIBILITY]`. The identifier, severity, and documented trigger are compatibility
contract units; exact English wording, punctuation, and Haxe's source-position rendering are not.
The registry is [`diagnostic-contract.json`](diagnostic-contract.json).

## Consumer rule

Tools should parse only the first bracketed `HXRS-*` identifier. Human text after that identifier
may improve without a SemVer break. A tool must not infer an identifier from English wording.

## Evolution and retirement

- An active identifier is not silently repurposed for a different trigger or severity.
- A new identifier may be added when a genuinely new admitted failure is introduced.
- A deprecated identifier and its documented replacement coexist for the remainder of the current major.
- Removal occurs no earlier than the next major. The manifest records the replacement before removal.
- If one old trigger is split, the old identifier remains as a migration alias where practical and
  release notes explain the more specific replacements.
- Correcting a false-positive trigger to match the written contract is a bug fix; changing the
  written admitted trigger is a compatibility decision.

This contract covers admitted profile, async/no-hxrt, borrow-region, Send/Sync crossing,
native-import, public/internal helper-boundary, structured metadata, Cargo, explicit Dynamic-field
operator, and qualified reflection failures. Internal compiler assertions and experimental
escape-hatch diagnostics remain outside the stable registry until explicitly admitted.
