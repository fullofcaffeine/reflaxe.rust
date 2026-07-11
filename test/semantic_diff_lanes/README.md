# Lane Semantic Diff Suite

This suite verifies that canonical `@:rustMetal` lane enforcement inside portable builds does not
change runtime semantics for lane-clean programs. The dispatch fixture also exercises the
`@:haxeMetal` compatibility alias.

Runner:

- `python3 test/run-semantic-diff.py --suite lanes`
- `npm run test:semantic-diff:lanes`
