pub struct LifetimeIsland;

impl LifetimeIsland {
    pub fn first_word_owned(text: String) -> String {
        first_word_view(text.as_str()).to_string()
    }

    pub fn all_words_at_least(text: String, min_len: i32) -> bool {
        with_view(text.as_str(), |view| {
            view.split_whitespace()
                .all(|word| word.len() >= min_len as usize)
        })
    }
}

fn first_word_view<'a>(text: &'a str) -> &'a str {
    text.split_whitespace().next().unwrap_or("")
}

fn with_view<R, F>(text: &str, f: F) -> R
where
    F: for<'a> FnOnce(&'a str) -> R,
{
    f(text)
}
