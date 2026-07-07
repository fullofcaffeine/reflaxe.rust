const KEEP: &str = env!("M49_KEEP");

const _: () = match option_env!("M49_REMOVE") {
    None => (),
    Some(_) => panic!("M49_REMOVE leaked into rustc"),
};

pub fn marker() -> &'static str {
    KEEP
}
