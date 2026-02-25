pub fn is_true<S>(value: bool, message: S)
where
    S: AsRef<str>,
{
    if !value {
        panic!("{}", message.as_ref());
    }
}

pub fn is_false<S>(value: bool, message: S)
where
    S: AsRef<str>,
{
    if value {
        panic!("{}", message.as_ref());
    }
}

pub fn equals_int<S>(expected: i32, actual: i32, message: S)
where
    S: AsRef<str>,
{
    if expected != actual {
        panic!(
            "{}: expected `{}`, got `{}`",
            message.as_ref(),
            expected,
            actual
        );
    }
}

pub fn equals_string<Expected, Actual, Message>(
    expected: Expected,
    actual: Actual,
    message: Message,
) where
    Expected: AsRef<str>,
    Actual: AsRef<str>,
    Message: AsRef<str>,
{
    if expected.as_ref() != actual.as_ref() {
        panic!(
            "{}: expected `{}`, got `{}`",
            message.as_ref(),
            expected.as_ref(),
            actual.as_ref()
        );
    }
}

pub fn contains<Haystack, Needle, Message>(haystack: Haystack, needle: Needle, message: Message)
where
    Haystack: AsRef<str>,
    Needle: AsRef<str>,
    Message: AsRef<str>,
{
    if !haystack.as_ref().contains(needle.as_ref()) {
        panic!(
            "{}: expected substring `{}`",
            message.as_ref(),
            needle.as_ref()
        );
    }
}

pub fn starts_with<Value, PrefixValue, Message>(
    value: Value,
    prefix_value: PrefixValue,
    message: Message,
) where
    Value: AsRef<str>,
    PrefixValue: AsRef<str>,
    Message: AsRef<str>,
{
    if !value.as_ref().starts_with(prefix_value.as_ref()) {
        panic!(
            "{}: expected prefix `{}`",
            message.as_ref(),
            prefix_value.as_ref()
        );
    }
}

pub fn line_count<Value, Message>(value: Value, expected: i32, message: Message)
where
    Value: AsRef<str>,
    Message: AsRef<str>,
{
    let count = value.as_ref().split('\n').count() as i32;
    if count != expected {
        panic!(
            "{}: expected {} lines, got {}",
            message.as_ref(),
            expected,
            count
        );
    }
}
