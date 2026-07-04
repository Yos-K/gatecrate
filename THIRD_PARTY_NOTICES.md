# Third-Party Notices

gatecrate itself is licensed under Apache License 2.0 (see [LICENSE](./LICENSE)).

This file acknowledges third-party software that gatecrate **optionally integrates with or
references**. gatecrate does **not** bundle or redistribute the source code of any of the
tools below — they are external dependencies the user installs separately. Listed here for
transparency and attribution.

## TAKT

- **Project**: [nrslib/takt](https://github.com/nrslib/takt) (npm package `takt`)
- **License**: MIT License
- **Copyright**: Copyright (c) 2026 Masanobu Naruse
- **How gatecrate uses it**: The optional `gatecrate-setup` agent skill can drive the
  mutation-config iteration loop with TAKT. gatecrate ships only its **own** files written to
  TAKT's workflow schema (`.claude/skills/gatecrate-setup/takt/harness-config-derive.yaml`,
  `personas/gatecrate-setup.md`, and a README). TAKT itself is installed by the user via
  `npm install -g takt`; none of TAKT's source is copied into this repository.

MIT permits free use, modification, and distribution; its only condition is to include the
copyright notice and license text when redistributing the Software (TAKT's code). gatecrate
does not redistribute TAKT's code, so this notice is provided as courtesy attribution.

MIT License text: https://github.com/nrslib/takt/blob/main/LICENSE

## cc-sdd

- **Project**: [gotalab/cc-sdd](https://github.com/gotalab/cc-sdd) (npm package `cc-sdd`)
- **License**: MIT License
- **Copyright**: Copyright (c) Gota
- **How gatecrate uses it**: gatecrate INTEGRATES WITH cc-sdd (Kiro-style Spec-Driven Development)
  without modifying or bundling any of its source. gatecrate ships only its **own** custom steering
  template (`templates/kiro-steering/gatecrate-spec-test-loop.md`) which a consumer installs into
  their `.kiro/steering/` directory — cc-sdd's OWN sanctioned extension point (`/kiro:steering-custom`,
  "Load entire `.kiro/steering/` as project memory"). Through it, gatecrate's spec-test-loop runs
  inside the cc-sdd phases (steering / validate-gap / spec-design / spec-impl / validate-impl) while
  cc-sdd's 11 command files stay vanilla. cc-sdd itself is installed by the user via `npx cc-sdd@latest`;
  none of cc-sdd's source is copied into this repository.

MIT permits free use, modification, and distribution; its only condition is to include the copyright
notice and license text when redistributing the Software (cc-sdd's code). gatecrate does not
redistribute cc-sdd's code, so this notice is provided as courtesy attribution.

MIT License text: https://github.com/gotalab/cc-sdd/blob/main/LICENSE
