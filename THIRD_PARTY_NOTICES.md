# Third-party notices

This file lists source code included in the reflaxe.rust release package. It is
an inventory for reviewers and does not replace professional legal advice.

## Reflaxe

License: MIT

Source: https://github.com/SomeRanDev/reflaxe.git

The shipped framework source starts from the recorded commit and includes the exact local patch under vendor/reflaxe.

MIT License

Copyright (c) 2026 Maybee "SomeRanDev" Rezbit

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

License text: vendor/reflaxe/LICENSE

## Haxe Standard Library derived files

License: MIT

Source: https://github.com/HaxeFoundation/haxe/tree/4.3.7

Some std/ files are target overrides derived from Haxe Standard Library source. The file-by-file source record is shipped inside this package at provenance/stdlib-provenance-ledger.json.

Copyright (C)2005-2016 Haxe Foundation

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.

## Rust crate dependencies

These version requirements are shipped, but dependency source is downloaded later by Cargo. A consuming application's Cargo.lock chooses exact versions. The declared requirements are inventoried in
`release-sbom.json`; exact resolved dependency licenses belong to the
application's reviewed lockfile and release process.
