---
name: reverse-engineering
description: Reverse-engineering and binary or malware analysis harness. Invoke for understanding unknown, obfuscated, undocumented, or hostile artifacts — native binaries (ELF, PE, Mach-O), WebAssembly, shellcode, managed bytecode (Java, .NET, Python), firmware, minified or packed code, and unknown wire protocols. Covers the toolchain (file/strings/binwalk triage, IDA/Ghidra/Binary Ninja/radare2 disassembly, gdb/lldb/Frida/strace dynamic analysis, YARA/capa detection) and carries an active threat-triage posture: high-entropy packing, suspicious imports, embedded payloads, anti-analysis tricks, and network indicators are surfaced as warnings. Triggers on: reverse engineer, disassemble, decompile, deobfuscate, unpack, binary analysis, malware, threat, shellcode, indicator of compromise, IDA, Ghidra, Frida, radare2, WebAssembly, PE, ELF, exe, firmware.
user-invocable: true
metadata:
  short-description: Reverse engineering and binary or malware analysis with threat triage
---

# Reverse Engineering

Recover the structure, behavior, and intent of an artifact whose source is not available — and raise a warning the moment it looks hostile.
This skill serves analysis and defense: interoperability, security research, malware triage, capture-the-flag competitions, and vulnerability research on artifacts that are authorized for examination.
It does not author malware, and it does not build detection-evasion for offensive use — see [Mandate](#mandate).

Its spine is [`verification.md`](../../../../thinking/verification.md): in reverse engineering, memory lies and the artifact is the only referee, so every claim is observed, not assumed.
For obfuscated JavaScript, [`oxc.md`](../../../../reference/oxc.md) is the abstract-syntax-tree companion.

## Contents

- [Containment first](#containment-first)
- [Identify the artifact](#identify-the-artifact)
- [The toolchain](#the-toolchain)
- [The method](#the-method)
- [Threat signals — warn loudly](#threat-signals--warn-loudly)
- [Reporting](#reporting)
- [Mandate](#mandate)

## Containment first

Treat every unknown artifact as live malware until proven otherwise.
This is not paranoia — it is the one rule whose violation cannot be undone; a detonated sample can encrypt, exfiltrate, or persist before the second command runs.

| Rule                                          | Why                                                                                                               |
| --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Hash and record before opening                | `sha256sum` first — the hash is the sample's identity, the anchor for every later note and lookup                 |
| Static analysis never executes the sample     | reading a file cannot trigger it; running it can — exhaust static work before even considering dynamic work       |
| Dynamic analysis only in a disposable machine | no host execution, ever; use an isolated virtual machine, snapshot before, revert after; network off or sinkholed |
| Assume anti-analysis                          | samples detect virtual machines, debuggers, and sleep past timeouts — a quiet sample is not a safe one            |
| Uploading a sample is publishing it           | VirusTotal and online sandboxes are public and permanent; look up the hash first, upload only with authorization  |
| Defang indicators in every report             | write `hxxp://`, `10[.]0[.]0[.]1`, neutralize sample paths — a report is a document, not a launcher               |

Without an isolated environment, say so and stop at static analysis.
Static-only with that limit stated is honest work; dynamic analysis on an unsafe host is a self-inflicted breach.

## Identify the artifact

Never trust the extension — extensions lie, and half the job is refusing the first assumption.

1. **Magic and type:** `file`, `trid`, `detect-it-easy` — the bytes decide, not the name.
2. **Surface strings:** `strings -n 8`, and `-e l` for the wide characters on Windows samples — URLs, keys, format strings, and the compiler's fingerprints surface here for free.
3. **Structure and entropy:** `binwalk` to carve embedded files, `xxd` for the header, an entropy scan for packed or encrypted regions.
4. **Provenance:** compiler, packer, language runtime — knowing the toolchain narrows everything downstream.

| Format        | Confirm with             | Inspect with                            |
| ------------- | ------------------------ | --------------------------------------- |
| ELF           | magic `7F 45 4C 46`      | `readelf -a`, `objdump -d`, `nm`, `ldd` |
| PE            | `MZ` … `PE\0\0`          | `pefile`, `PE-bear`, `capa`             |
| Mach-O        | `FE ED FA CE` / `CF FA`  | `otool -tV`, `nm`, `codesign -dv`       |
| WebAssembly   | `00 61 73 6D`            | `wasm2wat`, `wasm-decompile`            |
| Raw shellcode | no header, position-free | `objdump -b binary -m i386:x86-64 -D`   |

## The toolchain

Pick by the job, not by loyalty, and probe what is installed (`which ida ghidra r2 frida`) rather than assume — the same freshness rule as everywhere else.

- **Recover code from machine code:** IDA Pro with Hex-Rays (deepest decompiler), Ghidra (open-source, headless-scriptable, the default first reach), Binary Ninja, radare2 or rizin with Cutter, `objdump` for a one-shot.
- **Watch it run, inside containment:** gdb with pwndbg or GEF, lldb, x64dbg or WinDbg, Frida (live hooking — the fastest way to defeat runtime obfuscation), strace and ltrace, Unicorn or Qemu for emulation.
- **Managed and web targets, where decompilation is near-total:** `jadx` or CFR for Java, dnSpy or ILSpy for .NET, `dis` and decompyle3 for Python bytecode, WABT for WebAssembly, and abstract-syntax-tree analysis via [`oxc.md`](../../../../reference/oxc.md) for minified JavaScript.

## The method

Reverse engineering is hypothesis discipline against an artifact that never lies — the loop of [`verification.md`](../../../../thinking/verification.md), aimed at recovery instead of repair.

1. **Triage** — identify, hash, string, entropy-scan; decide managed-decompile versus native-disassemble versus dynamic.
2. **Map statically** — entry point, imports and exports, cross-references; label the functions that are understood, and leave the rest named as unknowns rather than guessed.
3. **Confirm dynamically** — only in containment, and only for what static work could not settle: hook the suspect call, watch the real argument, dump the unpacked payload from memory after the loader runs.
4. **Reconstruct** — turn confirmed behavior into artifacts a stranger can use: annotated disassembly, recovered structs, a protocol grammar, pseudocode.
5. **Stop when the question is answered** — the work ends when the specific question is answered, not when the whole binary is understood; total understanding is rarely the goal and never the budget.

One claim, one piece of evidence: a function does what was watched or traced in full, never what its name suggests — malware names its exfiltration routine `update_config`.

## Threat signals — warn loudly

While analyzing, run an active triage pass.
When any signal fires, surface it as a prominent warning, not a footnote, and anchor it to evidence — an offset, an import, a string, a rule — never a bare "looks suspicious."

| Signal             | What it looks like                                                                              | Why it warns                                |
| ------------------ | ----------------------------------------------------------------------------------------------- | ------------------------------------------- |
| High entropy       | sections around 7.8+ bits per byte; a tiny `.text` beside a huge blob                           | packing or encryption hiding the payload    |
| Packer fingerprint | UPX, Themida, VMProtect, ASPack markers                                                         | deliberate obstruction of static analysis   |
| Injection imports  | `VirtualAllocEx` + `WriteProcessMemory` + `CreateRemoteThread`; a read-write-execute `mprotect` | process injection or self-modifying code    |
| Dynamic resolution | `LoadLibrary` + `GetProcAddress`, hashed import names, no static import table                   | hiding true capability from the import view |
| Anti-analysis      | `IsDebuggerPresent`, timing checks, virtual-machine or processor probes                         | the sample knows it may be watched          |
| Network indicators | hardcoded addresses, domains, user-agents, beacon intervals                                     | possible command-and-control — defang it    |
| Embedded payload   | a PE or ELF header inside a data section                                                        | a second stage carried inside the first     |
| Persistence        | run keys, scheduled tasks, systemd units, LaunchAgents                                          | intent to survive reboot                    |
| Known-bad          | a VirusTotal hash hit, a YARA family match, a `capa` capability                                 | corroboration from detection tooling        |

Tooling for the pass: `capa` (maps a binary to attacker techniques), `yara`, an entropy scan, import triage.
Absence of signals is not a clean bill of health — say "no signals fired in the areas examined," never "this is safe," because proving a negative is not what static triage does.

## Reporting

- **Lead with the verdict and any warnings** — hostile, suspicious, or benign-in-scope, then the evidence; a reader skimming the first line must catch a red flag ([`communication.md`](../../../../thinking/communication.md)).
- **Every finding cites its evidence** — an offset, an address, an import, a string, or a trace; a finding that cannot be pointed at is a story.
- **Rank each claim on the ladder** — observed dynamically, traced statically, or inferred — and label the inferences as inferences.
- **Deliver reusable artifacts** — annotated functions, recovered structs, a protocol table, defanged network indicators, YARA candidates; the artifact outlives the session.
- **State coverage honestly** — what was examined, what could not be reached (encrypted, dead code, an unreached branch), and why.

## Mandate

Reverse engineering is a neutral craft with essential, legitimate uses: interoperability, security and vulnerability research, malware analysis and detection, digital forensics, capture-the-flag competitions, and understanding code that must be trusted.
This skill serves those.

- **In scope:** analyzing artifacts authorized for examination; understanding behavior; detecting and documenting threats; recovering structure for defense and interoperability.
- **Out of scope:** authoring malware, building detection-evasion or anti-analysis for offensive deployment, weaponizing a vulnerability against systems that are neither owned nor authorized for testing, or stripping protections purely to enable infringement.
- **When intent is unclear,** the analysis half is almost always fine and the weaponization half is the line — do the understanding, and name where the work stops.
