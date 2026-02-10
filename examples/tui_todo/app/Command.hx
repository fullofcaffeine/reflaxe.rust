package app;

/**
	A command palette entry.

	Why
	- The palette filters and sorts commands. Keeping them as data (id + label + keywords)
	  keeps the app deterministic and easy to test.
**/
class Command {
	public final id: CommandId;
	public final title: String;
	public final keywords: Array<String>;

	public function new(id: CommandId, title: String, ?keywords: Array<String>) {
		this.id = id;
		this.title = title;
		this.keywords = keywords != null ? keywords : [];
	}

	public function haystack(): String {
		var out = title;
		for (k in keywords) out = out + " " + k;
		return out.toLowerCase();
	}
}

