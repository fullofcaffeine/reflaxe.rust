# [0.16.0](https://github.com/fullofcaffeine/reflaxe.rust/compare/v0.15.1...v0.16.0) (2026-01-25)


### Bug Fixes

* **snapshot:** track rusty_mut_slice intended ([cadb77f](https://github.com/fullofcaffeine/reflaxe.rust/commit/cadb77fab2c584a12ef4386034f8439236a00fa7))


### Features

* **rusty:** borrow-first slices + mut slice ([4ddfaa8](https://github.com/fullofcaffeine/reflaxe.rust/commit/4ddfaa8f90df2609c51b9f86f1aa88447a9dec76))

## [0.15.1](https://github.com/fullofcaffeine/reflaxe.rust/compare/v0.15.0...v0.15.1) (2026-01-25)


### Bug Fixes

* **tui:** quiet headless + tidy nullable init ([d3cdb6e](https://github.com/fullofcaffeine/reflaxe.rust/commit/d3cdb6e4c04ce5357ef810e6c529027a1dbd8548))

# [0.15.0](https://github.com/fullofcaffeine/reflaxe.rust/compare/v0.14.0...v0.15.0) (2026-01-25)


### Features

* milestone 14 stdlib + operators ([f6374ad](https://github.com/fullofcaffeine/reflaxe.rust/commit/f6374ad411a4ef8d60e33cc8a991c48e1ff74a83))

# [0.14.0](https://github.com/fullofcaffeine/reflaxe.rust/compare/v0.13.0...v0.14.0) (2026-01-25)


### Features

* **lang:** Null<T> Option coercions + optional args ([08b6f8e](https://github.com/fullofcaffeine/reflaxe.rust/commit/08b6f8e1b2d462750c4dc1d07291a3414cdcc764))

# [0.13.0](https://github.com/fullofcaffeine/reflaxe.rust/compare/v0.12.0...v0.13.0) (2026-01-25)


### Features

* **std:** inline Lambda helpers + snapshot ([a2f542d](https://github.com/fullofcaffeine/reflaxe.rust/commit/a2f542d608209552529c34b6fa5d16f197c33dea))

# [0.12.0](https://github.com/fullofcaffeine/reflaxe.rust/compare/v0.11.0...v0.12.0) (2026-01-25)


### Features

* **lang:** generics traits + phantom params ([da1a1cb](https://github.com/fullofcaffeine/reflaxe.rust/commit/da1a1cb03b89cdefe107fcb8dfe445f047a56b0c))

# [0.11.0](https://github.com/fullofcaffeine/reflaxe.rust/compare/v0.10.0...v0.11.0) (2026-01-25)


### Features

* **std:** haxe.ds maps + iterator runtime ([0537559](https://github.com/fullofcaffeine/reflaxe.rust/commit/0537559710126ba6edd939afcc965e65d89db13f))
* **tui:** add TestBackend harness + cargo tests ([d4a4424](https://github.com/fullofcaffeine/reflaxe.rust/commit/d4a442449ac75c15d12724077d4880bb37775580))

# [0.10.0](https://github.com/fullofcaffeine/reflaxe.rust/compare/v0.9.0...v0.10.0) (2026-01-25)


### Bug Fixes

* **compiler:** reduce Rust warnings (mut + type idents) ([8c6f407](https://github.com/fullofcaffeine/reflaxe.rust/commit/8c6f40789e6ba7552a5abf081604fa331323a343))


### Features

* **compiler:** baseline function values via Rc<dyn Fn> ([f51c816](https://github.com/fullofcaffeine/reflaxe.rust/commit/f51c8164b706f54a93b784aba308289725149e8a))

# [0.9.0](https://github.com/fullofcaffeine/reflaxe.rust/compare/v0.8.1...v0.9.0) (2026-01-25)


### Features

* **compiler:** support general abstracts and numeric casts ([790dab8](https://github.com/fullofcaffeine/reflaxe.rust/commit/790dab8fa113026e6da19ce8ac365f05a53a7f5e))

## [0.8.1](https://github.com/fullofcaffeine/reflaxe.rust/compare/v0.8.0...v0.8.1) (2026-01-24)


### Performance Improvements

* **compiler:** use copied() for Copy iterables ([aa7185b](https://github.com/fullofcaffeine/reflaxe.rust/commit/aa7185b166ed458d26694a8cf43eddac161fb43e))

# [0.8.0](https://github.com/fullofcaffeine/reflaxe.rust/compare/v0.7.0...v0.8.0) (2026-01-24)


### Features

* **rusty:** add okOr/okOrElse and Result context ([8ed36d7](https://github.com/fullofcaffeine/reflaxe.rust/commit/8ed36d7b7d659b96bd324070122e64b6c8a82803))

# [0.7.0](https://github.com/fullofcaffeine/reflaxe.rust/compare/v0.6.0...v0.7.0) (2026-01-24)


### Features

* **rusty:** support HashMap key iteration and owned iter adapters ([af48fff](https://github.com/fullofcaffeine/reflaxe.rust/commit/af48fff79cfad897163de82bc3c3adf190cf46ef))

# [0.6.0](https://github.com/fullofcaffeine/reflaxe.rust/compare/v0.5.0...v0.6.0) (2026-01-24)


### Features

* **rusty:** support scoped &mut borrows in codegen ([b3963da](https://github.com/fullofcaffeine/reflaxe.rust/commit/b3963dabdfe14a906b0e5e48aab29435c8a4bf92))

# [0.5.0](https://github.com/fullofcaffeine/reflaxe.rust/compare/v0.4.1...v0.5.0) (2026-01-24)


### Features

* **tui:** interactive todo + CI headless mode ([43c7ec7](https://github.com/fullofcaffeine/reflaxe.rust/commit/43c7ec766d2f33c8071a1b676dc34035f6322608))

## [0.4.1](https://github.com/fullofcaffeine/reflaxe.rust/compare/v0.4.0...v0.4.1) (2026-01-24)


### Performance Improvements

* **compiler:** reduce cloning of literal strings/arrays ([f8ddf85](https://github.com/fullofcaffeine/reflaxe.rust/commit/f8ddf8530bed4ba9141b62e4079a2b5148e988a8))

# [0.4.0](https://github.com/fullofcaffeine/reflaxe.rust/compare/v0.3.1...v0.4.0) (2026-01-24)


### Features

* **rusty:** support for-loops on Vec/Slice ([0bae813](https://github.com/fullofcaffeine/reflaxe.rust/commit/0bae813db93de8622880f3973da477f35be0cfa3))

## [0.3.1](https://github.com/fullofcaffeine/reflaxe.rust/compare/v0.3.0...v0.3.1) (2026-01-24)


### Performance Improvements

* **compiler:** reduce enum match clones ([f31c859](https://github.com/fullofcaffeine/reflaxe.rust/commit/f31c859255084307d319aa80aef0e841ffc3fda5))

# [0.3.0](https://github.com/fullofcaffeine/reflaxe.rust/compare/v0.2.0...v0.3.0) (2026-01-24)


### Features

* **compiler:** add rust_deny_warnings ([464b2b3](https://github.com/fullofcaffeine/reflaxe.rust/commit/464b2b3d32b59028dcfc539204fb70a3790f1a37))

# [0.2.0](https://github.com/fullofcaffeine/reflaxe.rust/compare/v0.1.0...v0.2.0) (2026-01-24)


### Features

* **rusty:** add option/result helpers ([a1f672d](https://github.com/fullofcaffeine/reflaxe.rust/commit/a1f672d6da7867024b737b0df590ffffb13a3d96))

# [0.1.0](https://github.com/fullofcaffeine/reflaxe.rust/compare/v0.0.1...v0.1.0) (2026-01-24)


### Features

* **rusty:** add path and time primitives ([0aa3986](https://github.com/fullofcaffeine/reflaxe.rust/commit/0aa39865396c4f8be1f172e97c7cfe59dc9e1c46))

# Changelog

This project uses semantic-release. See GitHub Releases for published versions.
