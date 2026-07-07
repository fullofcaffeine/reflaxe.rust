use std::io::{self, Read};

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();

    if input == "m50-stdin-ok\n" {
        println!("stdin-ok");
    } else {
        eprintln!("unexpected stdin: {input:?}");
        std::process::exit(7);
    }
}
