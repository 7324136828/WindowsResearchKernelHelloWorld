# WRK documentation

Start with these guides for the current WRK 1.2 x86 environment:

| Guide | Contents |
|---|---|
| [Components](components.md) | Kernel subsystems, HAL/BOOTVID/KDCOM, boot/runtime modules, major functions and source boundaries. |
| [Boot process](boot.md) | BIOS and loader stages, kernel phases, native SMSS startup, installed-system route and current demo reproduction. |
| [Failures and solutions](failures.md) | Recorded loader/0x9A/0x69/0x19 failures, verified repairs, diagnostic workflow and adjacent startup failure paths. |
| [Native Hello World experiment](WRK_HELLO_BOOT.md) | Detailed build provenance, historical experiments, VM observations and native execution evidence. |
| [Runtime dependencies](../dependency.md) | Required files/registry data and the original loader/payload ISO's missing-runtime limitation. |
| [FreeLoader](FREELOADER.md) | Build and package the NT-compatible loader. |
| [VirtualBox](VIRTUALBOX.md) | Provision a VM and install WRK into a compatible Server 2003 SP1 guest. |
| [BIOS bootstrap lab](BOOTLOADER.md) | Separate two-stage teaching bootstrap and chainloader. |

The latest recorded setup-mode RAM-disk test displayed
`Hello world from WRK SMSS!`; see the
native audit (`artifacts/wrk-hello-20261003-setup-pnp/verification/native-smss-audit.json`).
That recorded result establishes the small native demo. The original FreeLoader
ISO was a separate loader/payload disc, and ordinary installed-system startup
requires valid compatible installation state.

Source links point into the repository. Verification paths under `artifacts/`
identify historical local test outputs. Cleanup removed the generated evidence,
ISOs, VMs, and build trees; the guides preserve the recorded observations and
reproduction commands. Rebuild and rerun to produce fresh evidence.

Use `tools\Clean-GeneratedFiles.ps1 -WhatIf` to preview future cleanup and
`tools\Clean-GeneratedFiles.ps1` to perform it. Downloaded prerequisites in
`.tools/` are preserved separately from disposable `artifacts/` output.
