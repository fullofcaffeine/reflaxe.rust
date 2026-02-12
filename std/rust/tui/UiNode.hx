package rust.tui;

/**
	A small, Haxe-friendly UI DSL that the Rust backend can render via ratatui.

	Why
	- Passing only newline-delimited strings is enough for toy demos, but not for a real app.
	- For a compiler harness we want:
	  - multiple screens/widgets
	  - deterministic headless rendering for CI snapshots
	  - a typed Haxe surface (no `__rust__` in apps)

	What
	- `Layout(dir, constraints, children)` is the primary composition primitive.
	- Widgets: `Paragraph`, `List`, `Tabs`, `Gauge`, `Block`.
	- `Overlay(children)` draws multiple nodes over the same area (useful for modals/toasts).

	How
	- The Rust runtime implements a renderer that recursively walks this tree and draws widgets
	  into ratatui frames (`std/rust/tui/native/tui_demo.rs`).
	- Avoid direct recursion like `UiNode(Block(child:UiNode))`: that would be an infinitely-sized
	  Rust type. We represent nesting using `Array<UiNode>` so Rust stores children in heap-backed
	  vectors.
**/
enum UiNode {
	/** Render nothing. **/
	Empty;

	/** A layout split node. **/
	Layout(dir:LayoutDir, constraints:Array<Constraint>, children:Array<UiNode>);

	/**
		Draw children over the same area in order.

		Typical usage: `[baseLayout, modalNode, toastNode]`.
	**/
	Overlay(children:Array<UiNode>);

	/** A bordered block container. Children are rendered into the inner area. **/
	Block(title:String, children:Array<UiNode>, style:StyleToken);

	/** Paragraph widget (optionally wrapped). **/
	Paragraph(text:String, wrap:Bool, style:StyleToken);

	/** Tabs widget. **/
	Tabs(titles:Array<String>, selected:Int, style:StyleToken);

	/** A progress gauge (0..100). **/
	Gauge(title:String, percent:Int, style:StyleToken);

	/**
		List widget.

		Notes:
		- `selected = -1` means no selection.
	**/
	List(title:String, items:Array<String>, selected:Int, style:StyleToken);

	/**
		Centered modal/popup.

		Notes:
		- `wPercent`/`hPercent` are clamped to sane ranges by the backend.
	**/
	Modal(title:String, body:Array<String>, wPercent:Int, hPercent:Int, style:StyleToken);

	/**
		Animated text block with deterministic effects.

		Why
		- Gives apps an explicit way to express motion/energy in the UI without raw target injection.
		- Keeps animation deterministic for CI by driving it from an explicit `phase` integer.

		What
		- Renders a bordered block (`title`) containing transformed `text`.
		- `effect` controls the visual transformation.
		- `phase` is the animation position (usually advanced on `Tick` events).

		How
		- The Rust renderer applies the effect algorithm and then draws the result as a paragraph.
	**/
	FxText(title:String, text:String, effect:FxKind, phase:Int, style:StyleToken);
}
