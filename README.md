# Strata engine builder

Builds the [Strata](https://github.com/Niko1221/Strata) engine for Linux and
publishes it as a release asset, so the official launcher downloads a finished
engine instead of trying to compile one on your machine.

## Why this exists

The launcher compiles its own engine when no prebuilt one fits, and on a current
distro that path fails twice for reasons that have nothing to do with your setup:

- **gcc 16 vs CUDA 13.0/13.2.** `crt/host_config.h` refuses `__GNUC__ > 15`.
  Overriding it with `-allow-unsupported-compiler` gets past the check and then
  fails harder: nvcc's own frontend cannot parse gcc 16's `<type_traits>`
  (`__type_identity is undefined` in `include/c++/16/type_traits`). CUDA 13.4
  raises the limit to `> 16`.
- **glibc 2.42 vs CUDA 13.0/13.2.** glibc 2.42 added `rsqrt`/`rsqrtf` declared
  `noexcept(true)`; CUDA declares the same two without it, and the mismatched
  exception specification is a hard error from
  `/usr/include/bits/mathcalls.h`. CUDA 13.2 and newer add `noexcept` behind
  `_NV_GLIBC_VERSION_GE_2_42`.

So the build pins **CUDA 13.4** and takes the compiler the machine already has.

## Does it need a GPU?

No. `CMAKE_CUDA_ARCHITECTURES` is given explicitly, so nvcc only compiles and
nothing opens a device. A clean checkout was built for `sm_89` on a machine with
no NVIDIA card: a 55 MB engine, exit 0.

## Use it

Run the workflow (`workflow_dispatch`), pick your architecture, and point the
launcher at the published asset:

```bash
./setup.sh --prebuilt https://github.com/garfi-kod/strata-engine-builder/releases/download/v0.1.41/
```

| archs | card |
|-------|------|
| `75`  | RTX 20 (Turing) |
| `86`  | RTX 30 (Ampere) |
| `89`  | RTX 40 (Ada) |
| `120` | RTX 50 (Blackwell) |

Several at once is fine, for a machine with more than one card: `86;89`.

The archive contains the engine, `BUILD.json`, and `lib/` with the CUDA runtime
libraries. The binary's RUNPATH is rewritten to `$ORIGIN/lib`, so it starts
without a CUDA installation and without an environment variable.

## What the gate checks

A green build is not the same as a usable artifact, so the workflow asserts on
the binary itself: the requested architectures are present in it, it links
`cudart` (a CPU-only build would pass every other check), its RUNPATH is
`$ORIGIN`-relative and no absolute build path survived, it prints its version,
and it fails again once the bundled libraries are moved aside. That last one is
the control: without it, "it starts" proves nothing.

## Layout

- `scripts/install-cuda.sh` — assembles CUDA 13.4 into `./cuda-13.4` from
  NVIDIA's pip wheels and the redistributable `cccl` archive. No sudo, no
  `/usr/local`, about 600 MB instead of the 4.3 GB runfile. Two things the
  wheels do not provide and CMake needs are added: `lib64/` with the
  unversioned `libcudart.so` / `libcublas.so` names, and `include/cccl`.

The workflow checks out upstream `Niko1221/Strata` into `engine-src/`; this
repository carries only the recipe.
