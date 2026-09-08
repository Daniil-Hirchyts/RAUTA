# Third-party notices

## exercises-dataset

Gym Lib includes a compact snapshot of the English exercise records from
[`hasaneyldrm/exercises-dataset`](https://github.com/hasaneyldrm/exercises-dataset),
reviewed at commit `7455efae41b330c265e7cd4b78dfa848e7ce5ebd`. Text and data
fields (name, equipment, target/secondary muscles) are included under that
repository's MIT license.

Gym Lib also includes the per-exercise animations from the same dataset
(`public/assets/exercises/webp/{id}.webp`, 1,324 files). They were copied via
`scripts/copy-exercise-gifs.mjs`, upscaled to 360×360, and encoded as animated
WebP for on-demand mobile delivery. That media is **not** covered by the
dataset's MIT license — it is © Gym visual (https://gymvisual.com/) and
redistributed by `hasaneyldrm/exercises-dataset` under permission that does
not automatically extend downstream (their `NOTICE.md` states "cloning this
repo is not a license"). Including these GIFs here assumes the maintainer of
this repository has independently reviewed and holds any license required by
Gym visual's Terms & Conditions
(https://gymvisual.com/content/3-terms-and-conditions-of-use) for this use.
Anyone redistributing this repository or its `public/assets/exercises/webp`
directory further should do the same. The required copyright notice, "© Gym
visual — https://gymvisual.com/", is preserved in-app wherever the animations
are shown.

The GIFs were additionally upscaled from their originally distributed
180×180 resolution to 360×360 via `scripts/upscale_exercise_gifs.py` (see
"ESPCN" below). Gym visual's `NOTICE.md` states media "must be shared only at
180×180 resolution only" — this upscale is a further, explicit deviation from
that distribution term, on top of the general licensing assumption above, and
is the maintainer's decision and responsibility, not a use permitted by the
dataset's stated terms.

## ESPCN

The GIF upscaling in `scripts/upscale_exercise_gifs.py` uses the ESPCN x2
super-resolution model (`scripts/models/ESPCN_x2.pb`) from
[`fannymonori/TF-ESPCN`](https://github.com/fannymonori/TF-ESPCN), reviewed
at the `master` branch, `export/ESPCN_x2.pb`.

Apache License 2.0 — see https://www.apache.org/licenses/LICENSE-2.0 for the
full text.

MIT License

Copyright (c) 2026 Hasan Emir Yıldırım

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation and data files (the "Software"),
to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
sell copies of the Software, and to permit persons to whom the Software is
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

## transitions.dev

The staged page motion, animated counters, selection checks, and staggered reveals use copy-ready CSS transition patterns and semantic motion tokens from
[`Jakubantalik/transitions.dev`](https://github.com/Jakubantalik/transitions.dev), reviewed at commit `be0489a3ca29a533485a61153f9179d66d840b10`.

## MuscleMap

Gym Lib's local React anatomy path data was converted from the Swift geometry in
[`melihcolpan/MuscleMap`](https://github.com/melihcolpan/MuscleMap), reviewed at commit `7dc03071e03052e8bd4f6351e9176994cd28aa7d`.

MIT License

Copyright (c) 2026 Melih Colpan

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

## Matrix Sans Print

Matrix Sans Print v1.722, by The Matrix Sans Project Authors.
Source: https://github.com/FriedOrange/MatrixSans/releases/tag/v1.722
Licensed under SIL Open Font License 1.1. The unmodified webfont and full
license are distributed in `public/fonts/matrix-sans-print/`.
