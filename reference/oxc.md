# OXC

OXC (the JavaScript Oxidation Compiler) is a Rust crate ecosystem for parsing, analyzing, transforming, and printing JavaScript and TypeScript.
Read this when writing Rust that consumes the `oxc_*` crates: arena allocation, AST construction, semantic queries, AST traversal, or code generation.
It is organized bottom-up by dependency layer; each layer depends only on those above it.

> oxc 0.139.0 · verified against 0.135.0 sources on disk + 0.135→0.139 release notes · 2026-07-09

---

## Contents

| #   | Section                                  |
| --- | ---------------------------------------- |
| 1   | [Invariants](#invariants)                |
| 2   | [Memory / Allocator](#memory--allocator) |
| 3   | [Primitives](#primitives)                |
| 4   | [AST](#ast)                              |
| 5   | [Parser](#parser)                        |
| 6   | [Semantics](#semantics)                  |
| 7   | [Traversal](#traversal)                  |
| 8   | [Analysis](#analysis)                    |
| 9   | [Codegen](#codegen)                      |
| 10  | [Common patterns](#common-patterns)      |
| 11  | [Anti-patterns](#anti-patterns)          |
| 12  | [Limits](#limits)                        |

---

## Invariants

These hold across every layer.
Violating any causes a compile error, a panic, or silent corruption.

| #   | Rule                            | Detail                                                                                                                  |
| --- | ------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| 1   | Arena allocation                | All AST nodes live in an `Allocator`. Arena types have no `Drop`.                                                       |
| 2   | `clone_in` resets semantic IDs  | `clone_in` clears `SymbolId`/`ReferenceId`/`ScopeId` and resets `NodeId`. `clone_in_with_semantic_ids` preserves them.  |
| 3   | "Without" type safety           | Traversal ancestor types prevent aliasing the child field descended from, at compile time.                              |
| 4   | Generated code is authoritative | Files under `*/generated/` are auto-generated. Never edit.                                                              |
| 5   | IDs are `NonMaxU32`             | Valid IDs are never `u32::MAX`. Semantic IDs live in `Cell<Option<_>>`; `NodeId` lives in `Cell<NodeId>`.               |
| 6   | Semantic analysis assigns IDs   | After parsing alone, semantic ID cells are `None` and every `node_id` is `NodeId::DUMMY`. `SemanticBuilder` fills them. |

---

## Memory / Allocator

Foundation crate `oxc_allocator`.
Every AST node and arena collection allocates here.

### Allocator

```rust
let mut allocator = Allocator::default();               // Lazy, empty
let mut allocator = Allocator::with_capacity(1 << 20);  // Pre-size the bump arena
allocator.reset();                                      // Reclaim for reuse without freeing
```

Recycle one allocator across units of work with `reset()`.
Allocating a fresh `Allocator` per file is expensive; never calling `reset()` grows memory without bound.

### Arena types

| Type                | Creation                                                                                        |
| ------------------- | ----------------------------------------------------------------------------------------------- |
| `Box<'a, T>`        | `Box::new_in(value, &allocator)`                                                                |
| `Vec<'a, T>`        | `Vec::new_in(&allocator)`, `with_capacity_in`, `from_iter_in`, `from_array_in`, `from_value_in` |
| `HashMap<'a, K, V>` | `HashMap::new_in(&allocator)`                                                                   |
| `HashSet<'a, T>`    | `HashSet::new_in(&allocator)`                                                                   |
| `StringBuilder<'a>` | `StringBuilder::new_in(&allocator)`, `from_strs_array_in`                                       |

Thread safety:

| Type                          | `Send` | `Sync`                 |
| ----------------------------- | ------ | ---------------------- |
| `Allocator`                   | Yes    | No                     |
| `Box<'a, T>`                  | No     | No                     |
| `Vec` / `HashMap` / `HashSet` | No     | If contents are `Sync` |

Arena `Vec`/`HashMap`/`HashSet` are deliberately never `Send`, even when `T: Send`.
They are `Sync` only when their contents are `Sync`.

### CloneIn / TakeIn / ReplaceWith

| Operation                    | Effect                        | Semantic IDs             | Use when                                            |
| ---------------------------- | ----------------------------- | ------------------------ | --------------------------------------------------- |
| `clone_in`                   | Deep arena copy               | Reset (`None` / `DUMMY`) | The copy feeds a fresh `SemanticBuilder` run        |
| `clone_in_with_semantic_ids` | Deep arena copy               | Preserved                | Reusing a copy while the current `Scoping` is valid |
| `take_in`                    | Move out, leave a dummy       | Preserved (moved intact) | Moving a node to a new location                     |
| `take_in_box`                | Move out boxed, leave a dummy | Preserved (moved intact) | As `take_in`, returning `Box<'a, Self>`             |
| `replace_with`               | Rebuild in place via closure  | Preserved (moved intact) | Wrapping/unwrapping a node back into its own slot   |
| Direct `*expr = ...`         | In-place overwrite            | N/A                      | Simple replacement                                  |

`CloneIn<'new_alloc>` defines both `clone_in(&self, &Allocator)` and `clone_in_with_semantic_ids(&self, &Allocator)`.
The plain form resets `node_id` and every semantic-id cell to their defaults; only the `_with_semantic_ids` form copies them across.

`take_in` replaces a node with a type-specific dummy and returns the original: `Expression` → `NullLiteral`, `Statement` → `DebuggerStatement`, `Vec` → empty, `Box<[T]>` → empty boxed slice, `Option` → `None`.
The dummy left behind **must** be replaced or removed.
At 0.135 the argument is `take_in<A: AllocatorAccessor<'a>>(&mut self, A)` — the accessor is passed by value.
At 0.138 the trait was renamed `AllocatorAccessor` → `GetAllocator` (and `GetAllocator::allocator` takes `&self`).
Pass the allocator source directly — `&allocator`, or `ctx.ast` inside a traverse.
<!-- VERIFY: at 0.139 docs.rs shows `take_in<A: GetAllocator<'a>>(&mut self, &A)` (by reference); if `ctx.ast` is rejected, pass `&ctx.ast`. -->

`ReplaceWith<'a>: Dummy<'a>` provides `replace_with(&mut self, replacer: impl FnOnce(Self) -> Self)` (added during the 0.136–0.139 window).
The closure receives the owned node and its return value is written back into the same slot.
Prefer it over `take_in` + write-back when wrapping or extracting in place: take-then-assign writes a dummy into the arena that lives there forever, whereas `replace_with` never creates one.

```rust
// Clone for storage — keep IDs only while the current Scoping stays valid
self.stored.insert(id, expr.clone_in_with_semantic_ids(ctx.ast.allocator));

// Take for movement (leaves a dummy that must be overwritten, as it is here)
*expr = replacement.take_in(ctx.ast);

// Rebuild in place — no dummy left in the arena
expr.replace_with(|old| Expression::new_unary(SPAN, UnaryOperator::LogicalNot, old, &ctx.ast));
// VERIFY: `Expression::new_unary` follows the verified `new_*` pattern but was not individually confirmed at 0.139.

// Vector rebuild
let mut new_stmts = Vec::new_in(ctx.ast.allocator);
for stmt in stmts.take_in(ctx.ast) {
    if keep(&stmt) { new_stmts.push(stmt); }
}
*stmts = new_stmts;
```

### Address stability

`Box<T>` contents are always address-stable.
`Vec<T>` items are not stable after any push or mutation.

### FromIn

`FromIn<'a, T>` mirrors `std::convert::From` but threads an allocator: `T::from_in(value, &allocator)` (companion `IntoIn`/`into_in`).

### AllocatorPool

```rust
let pool = AllocatorPool::new(num_threads);         // Also: AllocatorPool::new_fixed_size(n)
let guard = pool.get();                             // AllocatorGuard — returns to the pool on drop
```

---

## Primitives

`Span` and `SourceType` live in `oxc_span`.
String types live in `oxc_str` (split out of `oxc_span` in v0.125).
The umbrella `oxc` crate does **not** re-export `oxc_str` — depend on it directly.
`oxc_ast::ast` re-exports `Str`.

### Span

```rust
pub struct Span { pub start: u32, pub end: u32, /* private _align field */ }  // 8 bytes, byte range
pub const SPAN: Span = Span::new(0, 0);                                       // Every generated node uses this
```

| Method                     | Purpose                         |
| -------------------------- | ------------------------------- |
| `size()`                   | `end - start`                   |
| `is_empty()`               | `start == end`                  |
| `is_unspanned()`           | `self == SPAN` (generated node) |
| `merge(other)`             | Smallest span containing both   |
| `expand(n)` / `shrink(n)`  | Grow or cut both ends           |
| `contains_inclusive(span)` | Range containment               |
| `source_text(src)`         | Extract the source substring    |

Also present: `expand_left`/`expand_right`, `shrink_left`/`shrink_right`, `move_left`/`move_right`.
Traits: `GetSpan` on all AST nodes; `GetSpanMut` for the rare case of modifying a node's location.

### Ident<'a> (oxc_str)

Identifier string with a precomputed hash; replaces the former `Atom`.
Stores pointer + length + hash — 16 bytes on 64-bit — and the hash makes `HashMap` lookups and equality fast.
Its lifetime is tied to the allocator that owns the text.

```rust
Ident::from("str")                                 // Borrows &str, computes hash
Ident::from_str_in("str", &ctx.ast)                // Copies into arena; A: GetAllocator (added 0.136–0.139)
let i: Ident = FromIn::from_in("str", &allocator); // Copies into arena (oxc_allocator::FromIn)
Ident::from_strs_array_in(["a", "b"], &allocator)  // Concatenation in arena; A: GetAllocator
static_ident!("use strict")                        // Compile-time hash, 'static
```

`from_str_in` did not exist at 0.135; it is a 0.136–0.139 addition with signature `from_str_in<A: GetAllocator<'a>>(&str, &A)`.
Companion collections: `IdentHashMap`, `IdentHashSet`, `ArenaIdentHashMap`.

### Str<'a> (oxc_str)

Plain arena string — a `&'a str` wrapper (`pub struct Str<'a>(&'a str)`) for non-identifier text such as string-literal values and raw literal text.
Provides `as_str()` and `Deref<Target = str>`.

### CompactStr (oxc_str)

Owned string, no lifetime.
`CompactStr::new("s")`; `CompactStr::new_const` stores up to `MAX_INLINE_LEN` (16) bytes inline at compile time.
Convert from arena strings via `Ident::to_compact_str` / `Str::to_compact_str` (and their `into_*` forms).

### ContentEq

Import from `oxc_span::ContentEq` (umbrella: `oxc::span::ContentEq`).

```rust
use oxc_span::ContentEq;
expr1.content_eq(&expr2)  // Structural equality; ignores spans and node IDs
```

`f64` comparison is bit-pattern equality (`to_bits`): `f64::NAN.content_eq(&f64::NAN) == true` for identical bits, but NaNs produced by arithmetic are not guaranteed to match, and `0.0.content_eq(&-0.0) == false`.

### SourceType

```rust
pub struct SourceType { /* pub(super) */ language: Language, module_kind: ModuleKind, variant: LanguageVariant }
```

| Constructor                  | Result                              |
| ---------------------------- | ----------------------------------- |
| `SourceType::from_path(p)`   | `Result` — auto-detect by extension |
| `SourceType::from_extension` | `Result` — from extension string    |
| `SourceType::unambiguous()`  | Parser detects module kind          |
| `SourceType::mjs()`          | JavaScript + Module                 |
| `SourceType::cjs()`          | JavaScript + CommonJS               |
| `SourceType::script()`       | JavaScript + Script                 |
| `SourceType::jsx()`          | JavaScript + Module + JSX           |
| `SourceType::ts()`           | TypeScript + Module                 |
| `SourceType::tsx()`          | TypeScript + Module + JSX           |
| `SourceType::d_ts()`         | TypeScript declaration file         |

Queries: `is_javascript()`, `is_typescript()`, `is_module()`, `is_commonjs()`, `is_jsx()`, `is_strict()`, `is_script()`.
Modules are always strict mode.

---

## AST

Crate `oxc_ast`.
Depends on the allocator and the primitives above.

### NodeId

Every AST node's first field is `pub node_id: Cell<NodeId>`.
`NodeId::DUMMY == NodeId::ROOT == 0` (the `Program` node carries `ROOT`), and non-root nodes hold `DUMMY` until `SemanticBuilder` assigns real IDs.
`AstBuilder` always creates nodes with `DUMMY`.

### Expression (43 variants, `#[repr(C, u8)]`)

All variants are boxed, e.g. `Expression::StringLiteral(Box<'a, StringLiteral<'a>>)`.
Discriminants 0–39 run sequentially; the three member-expression variants keep discriminants 48–50.

| Range | Category   | Variants                                                                                                                                                                                         |
| ----- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 0-6   | Literals   | Boolean, Null, Numeric, BigInt, RegExp, String, Template                                                                                                                                         |
| 7     | Identifier | `IdentifierReference`                                                                                                                                                                            |
| 8-9   | Meta       | MetaProperty, Super                                                                                                                                                                              |
| 10-31 | Operations | Array, Arrow, Assignment, Await, Binary, Call, Chain, Class, Conditional, Function, Import, Logical, New, Object, Parenthesized, Sequence, TaggedTemplate, This, Unary, Update, Yield, PrivateIn |
| 32-33 | JSX        | JSXElement, JSXFragment                                                                                                                                                                          |
| 34-38 | TypeScript | TSAs, TSSatisfies, TSTypeAssertion, TSNonNull, TSInstantiation                                                                                                                                   |
| 39    | Intrinsics | V8IntrinsicExpression                                                                                                                                                                            |
| 48-50 | Members    | Computed, Static, PrivateField (via `inherit_variants!`)                                                                                                                                         |

`inherit_variants!` flattens the nested `MemberExpression` enum into `Expression`, so `Expression::ComputedMemberExpression` exists directly.
**`Expression::MemberExpression` does NOT exist** — match the specific variants, or use `match_member_expression!()` / `match_expression!()`.
For the grouped view, `expr.as_member_expression()` / `as_member_expression_mut()` return `Option<&MemberExpression>` / `Option<&mut MemberExpression>`.
These converters were added at 0.139 (absent at 0.135); `is_member_expression()` accompanies them.

### Statement (~30 variants)

Key variants: `ExpressionStatement`, `ReturnStatement`, `IfStatement`, `SwitchStatement`, `WhileStatement`, `ForStatement`, `VariableDeclaration`, `FunctionDeclaration`, `BlockStatement`, `EmptyStatement`.

### Identifiers (4 types — do NOT mix)

| Type                  | Purpose               | Semantic ID field                         |
| --------------------- | --------------------- | ----------------------------------------- |
| `IdentifierName`      | Property names        | None                                      |
| `IdentifierReference` | Variable reads/writes | `reference_id: Cell<Option<ReferenceId>>` |
| `BindingIdentifier`   | Declarations          | `symbol_id: Cell<Option<SymbolId>>`       |
| `LabelIdentifier`     | Loop/block labels     | None                                      |

All four also carry `node_id: Cell<NodeId>` like every node.

### Key structs

```rust
pub struct VariableDeclaration<'a> {
    pub node_id: Cell<NodeId>,
    pub span: Span,
    pub kind: VariableDeclarationKind,  // Var, Let, Const, Using, AwaitUsing
    pub declarations: Vec<'a, VariableDeclarator<'a>>,
    pub declare: bool,
}

pub struct VariableDeclarator<'a> {
    pub node_id: Cell<NodeId>,
    pub span: Span,
    pub kind: VariableDeclarationKind,
    pub id: BindingPattern<'a>,
    pub type_annotation: Option<Box<'a, TSTypeAnnotation<'a>>>,
    pub init: Option<Expression<'a>>,
    pub definite: bool,
}

pub struct Function<'a> {
    pub node_id: Cell<NodeId>,
    pub span: Span,
    pub r#type: FunctionType,
    pub id: Option<BindingIdentifier<'a>>,
    pub generator: bool,
    pub r#async: bool,
    pub declare: bool,
    pub type_parameters: Option<Box<'a, TSTypeParameterDeclaration<'a>>>,
    pub this_param: Option<Box<'a, TSThisParameter<'a>>>,
    pub params: Box<'a, FormalParameters<'a>>,
    pub return_type: Option<Box<'a, TSTypeAnnotation<'a>>>,
    pub body: Option<Box<'a, FunctionBody<'a>>>,
    pub scope_id: Cell<Option<ScopeId>>,
    pub pure: bool,  // /* @__PURE__ */ annotation
    pub pife: bool,  // Possibly-invoked function expression
}
```

`BindingPattern` is an **enum** (`BindingIdentifier` | `ObjectPattern` | `ArrayPattern` | `AssignmentPattern`), not a struct.
The old struct's `type_annotation` / `optional` fields now live on `VariableDeclarator` and on the parameter nodes.

### AstBuilder

`AstBuilder` (reached via `ctx.ast` inside a traverse) is being migrated to type-associated constructors (oxc issue #23043).
At 0.139 nodes are created with `new_*` / `new_*_with_scope_id` associated functions on the AST type itself, whose final parameter is `&impl GetAstBuilder<'a>` (which `AstBuilder` implements).
Name parameters accept `impl Into<Ident<'a>>` and string values accept `impl Into<Str<'a>>`, so a `&str` passes directly.

```rust
// Literals
Expression::new_string_literal(SPAN, "value", None, &ctx.ast)                     // raw: Option<Str>
Expression::new_numeric_literal(SPAN, 42.0, None, NumberBase::Decimal, &ctx.ast)
Expression::new_boolean_literal(SPAN, true, &ctx.ast)
Expression::new_null_literal(SPAN, &ctx.ast)

// Identifier expression
Expression::new_identifier(SPAN, "name", &ctx.ast)

// Statements
Statement::new_expression_statement(SPAN, expr, &ctx.ast)
Statement::new_return_statement(SPAN, Some(expr), &ctx.ast)
Statement::new_block_statement(SPAN, stmts, &ctx.ast)                              // _with_scope_id variant exists
```

The `new_*` names above are individually verified against 0.139 docs.rs.
Every other node type exposes constructors of the same shape (`new_binary`, `new_unary`, `new_variable_declarator`, …); those follow the verified pattern but were not each confirmed.

Arena collections and the string helpers moved off `AstBuilder` at 0.138 — the following `AstBuilder` methods are deprecated at 0.139, with these replacements:

| Deprecated `AstBuilder` method | Replacement                                               |
| ------------------------------ | --------------------------------------------------------- |
| `ctx.ast.vec()`                | `Vec::new_in(ctx.ast.allocator)`                          |
| `ctx.ast.vec1(item)`           | `Vec::from_value_in(item, ctx.ast.allocator)`             |
| `ctx.ast.alloc(node)`          | `Box::new_in(node, ctx.ast.allocator)`                    |
| `ctx.ast.ident("x")`           | `Ident::from_str_in("x", &ctx.ast)` (or `Ident::from_in`) |
| `ctx.ast.str("text")`          | `Str::from_in("text", ctx.ast.allocator)`                 |

The legacy node methods (`ctx.ast.expression_string_literal(SPAN, "value", None)`, `ctx.ast.statement_return(SPAN, Some(expr))`, …) still compile at 0.139.
<!-- VERIFY: whether the legacy `expression_*` / `statement_*` AstBuilder methods carry a `#[deprecated]` marker at 0.139 could not be confirmed; two docs.rs reads of the same page disagreed. The type-associated `new_*` constructors above are the confirmed current API. -->

`NONE` is a unit struct exported as `oxc_ast::NONE` and from the `builder` module; pass it where a builder call needs an absent `Option<Box<'a, ...>>` (e.g. a missing `type_annotation`).

---

## Parser

Crate `oxc_parser`.
Depends on the allocator, primitives, and AST.

```rust
let ret = Parser::new(&allocator, source, source_type)
    .with_options(ParseOptions {
        preserve_parens: true,  // Emit ParenthesizedExpression nodes
        ..ParseOptions::default()
    })
    .parse();
```

`ParserReturn<'a>` is `#[non_exhaustive]`:

| Field                       | Type               | Notes                                                 |
| --------------------------- | ------------------ | ----------------------------------------------------- |
| `ret.program`               | `Program<'a>`      | Empty if `panicked`                                   |
| `ret.diagnostics`           | `Diagnostics`      | Syntax errors and warnings (see below)                |
| `ret.panicked`              | `bool`             | `true` = unrecoverable, AST empty                     |
| `ret.module_record`         | `ModuleRecord<'a>` | ESM import/export metadata                            |
| `ret.tokens`                | `Vec<'a, Token>`   | Arena vec; only populated when token collection is on |
| `ret.irregular_whitespaces` | `Box<[Span]>`      | For oxlint                                            |
| `ret.is_flow_language`      | `bool`             | Flow syntax detected                                  |

The diagnostics collection changed between 0.135 and 0.139: at 0.135 the field is `errors: Vec<OxcDiagnostic>`; by 0.139 it is `diagnostics: Diagnostics`, the `oxc_diagnostics::Diagnostics` newtype.
`Diagnostics` is a drop-in replacement for `Vec<OxcDiagnostic>` (it derefs to one) and adds `has_errors()`, `has_warnings()`, `errors()`, `warnings()`, `into_vec()`, plus `is_empty()`/`iter()` via `Deref`.

`ParseOptions` fields:

| Field                           | Notes                                                |
| ------------------------------- | ---------------------------------------------------- |
| `preserve_parens`               | Default `true`; keep `ParenthesizedExpression` nodes |
| `allow_return_outside_function` | Default `false`                                      |
| `allow_v8_intrinsics`           | Default `false`                                      |
| `parse_regular_expression`      | Gated behind the `regular_expression` cargo feature  |

Expression-only parsing: `Parser::new(...).parse_expression()` returns a `Result` whose `Ok` is `Expression<'a>`.
The error type is the diagnostics collection (`Vec<OxcDiagnostic>` at 0.135). <!-- VERIFY: whether parse_expression's error type is `Diagnostics` or `Vec<OxcDiagnostic>` at 0.139 was not confirmed. -->

Always check `diagnostics` (or `errors`) and `panicked`.
The parser recovers, so the AST is structurally valid even with syntax errors.
Use `preserve_parens: true` when transforming.
Parser-side checks are not comprehensive — run `SemanticBuilder::new().with_check_syntax_error(true)` for full syntax validation.

---

## Semantics

Crate `oxc_semantic`.
Consumes the AST and produces the symbol table, reference table, and scope tree — and assigns every `node_id`.

```rust
let ret = SemanticBuilder::new().build(&program);
// ret.diagnostics: Diagnostics   (field was `errors: Vec<OxcDiagnostic>` at 0.135)
// ret.semantic: Semantic<'a>

let scoping = ret.semantic.scoping();       // &Scoping (borrow)
let scoping = ret.semantic.into_scoping();  // Scoping (owned, consumes Semantic)
```

`build` takes `&'a Program<'a>`.
As with the parser, the return's diagnostic field was renamed/wrapped from `errors: Vec<OxcDiagnostic>` (0.135) to `diagnostics: Diagnostics` (0.139).

### Builder options (all off by default)

| Option                          | Effect                                                               |
| ------------------------------- | -------------------------------------------------------------------- |
| `with_check_syntax_error(true)` | Full syntax error validation                                         |
| `with_build_nodes(true)`        | Populate `Semantic::nodes()` — required for `AstNodes` random access |
| `with_class_table(true)`        | Build the class table                                                |
| `with_enum_eval(true)`          | Evaluate TS enum member values (const enum inlining)                 |
| `with_cfg(true)`                | Build the control flow graph (cargo feature `cfg`)                   |
| `with_stats(stats)`             | Pre-size allocations from AST stats (else computed by a pre-pass)    |
| `with_excess_capacity(f64)`     | Over-allocate tables by the given fraction                           |

`with_build_nodes` did not exist at 0.135; it is a 0.136–0.139 addition.
Presets `SemanticBuilder::new_compiler()` and `new_linter()` set common option bundles.

Accessors on `Semantic`: `scoping()`, `scoping_mut()`, `into_scoping()`, `nodes()`, `into_scoping_and_nodes()`, `comments()`, `cfg()`.

### Scoping (SoA layout)

Unified structure holding symbols, references, and the scope tree in an internal arena.
No lifetime parameter on the type itself — and it is `Send + Sync`.
<!-- VERIFY: some accessors below return arena-borrowed data carrying `'a` (e.g. root_unresolved_references); confirm against 0.139 whether Scoping owns its data outright or borrows from the arena. -->

Mutation requires exclusive access.

### IDs

| Type          | Represents            | Storage on the AST node              |
| ------------- | --------------------- | ------------------------------------ |
| `SymbolId`    | Declaration (binding) | `Cell<Option<SymbolId>>`             |
| `ReferenceId` | Usage (reference)     | `Cell<Option<ReferenceId>>`          |
| `ScopeId`     | Lexical scope         | `Cell<Option<ScopeId>>`              |
| `NodeId`      | AST node identity     | `Cell<NodeId>` (`DUMMY` until built) |

### Flags

| Type             | Key values                                                                                                                                                                                         | Key queries                                                                     |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `SymbolFlags`    | `FunctionScopedVariable`, `BlockScopedVariable`, `ConstVariable`, `Class`, `CatchVariable`, `Function`, `Import`, `TypeAlias`, `Interface`, `RegularEnum`, `ConstEnum`, `TypeParameter`, `Ambient` | `is_const_variable()`, `is_function()`, `is_value()`                            |
| `ReferenceFlags` | `Read`, `Write`, `Type`, `ValueAsType`, `Namespace`, `MemberWriteTarget`                                                                                                                           | `is_read()`, `is_write()`, `is_read_only()`                                     |
| `ScopeFlags`     | `Top`, `Function`, `Arrow`, `StrictMode`, `ClassStaticBlock`, `TsModuleBlock`, `Constructor`, `GetAccessor`, `SetAccessor`, `CatchClause`, `DirectEval`, `TsConditional`, `With`                   | `is_var()` (hoisting boundary = Top, Function, ClassStaticBlock, TsModuleBlock) |

`SymbolFlags` also carries `TypeImport`, `EnumMember`, `NamespaceModule`, `ValueModule`, `FunctionExpression`, `AsyncOrGeneratorFunction`.

### Safe ID resolution

Generated accessors `.reference_id()` / `.symbol_id()` / `.scope_id()` **panic** if the cell is unset (they call `.unwrap()`) — use them only on post-semantic ASTs.
Use the underlying `Cell::get()` when unsure; `set_*` counterparts exist.

```rust
// IdentifierReference -> SymbolId
let ref_id = ident.reference_id.get()?;
let symbol_id = scoping.get_reference(ref_id).symbol_id()?;  // None = global/unresolved

// BindingIdentifier -> SymbolId
let symbol_id = binding.symbol_id.get()?;

// VariableDeclarator -> SymbolId
decl.id.get_binding_identifier().and_then(|b| b.symbol_id.get())

// Function -> SymbolId
func.id.as_ref().and_then(|id| id.symbol_id.get())
```

### Queries

```rust
scoping.symbol_name(id)                              // &str
scoping.symbol_flags(id)                             // SymbolFlags
scoping.symbol_scope_id(id)                          // ScopeId
scoping.get_resolved_references(id)                  // impl DoubleEndedIterator<Item = &Reference>
scoping.get_reference(ref_id)                        // &Reference: symbol_id(), node_id(), flags()
scoping.root_unresolved_references()                 // &ArenaIdentHashMap<'a, ArenaVec<'a, ReferenceId>>
scoping.get_binding(scope_id, Ident::from("name"))   // This scope only
scoping.find_binding(scope_id, Ident::from("name"))  // Walks parent scopes
scoping.rename_symbol(symbol_id, scope_id, Ident::from("new"))
scoping.scope_is_descendant_of(scope_id, ancestor)   // Scope containment test (added 0.136–0.139)
scoping.remove_symbol_declaration(symbol_id, span)   // Drop one declaration site (added 0.136–0.139)
scoping.retain_resolved_references_excluding(&bits)  // Bulk-prune references by BitSet (added 0.136–0.139)
```

`get_binding` / `find_binding` / `rename_symbol` take `Ident`, not `&str` — wrap with `Ident::from("x")` or `static_ident!("x")`.
The three `*_descendant_of` / `remove_symbol_declaration` / `retain_resolved_references_excluding` methods are absent at 0.135; a differently-named `retain_resolved_references(&BitSet)` exists at 0.135.

### Reference counting

```rust
// Read count
scoping.get_resolved_references(id).filter(|r| r.flags().is_read()).count()

// Write count
scoping.get_resolved_references(id).filter(|r| r.flags().is_write()).count()
```

### Scoping rebuild rules

| Situation                  | Action  | Reason                      |
| -------------------------- | ------- | --------------------------- |
| Read-only pass             | Share   | IDs still valid             |
| Collect + apply (no decls) | Share   | References unchanged        |
| Add/remove declarations    | Rebuild | IDs may invalidate          |
| Rename identifiers         | Rebuild | Binding lookups change      |
| Before unused detection    | Rebuild | Need fresh reference counts |

Rebuild: `scoping = SemanticBuilder::new().build(&program).semantic.into_scoping();`

---

## Traversal

Crate `oxc_traverse`.
Depends on the allocator, AST, and semantics.

### Traverse trait

```rust
impl<'a> Traverse<'a, ()> for MyPass {
    fn enter_expression(&mut self, expr: &mut Expression<'a>, ctx: &mut TraverseCtx<'a, ()>) {}
    fn exit_expression(&mut self, expr: &mut Expression<'a>, ctx: &mut TraverseCtx<'a, ()>) {}
    // Vec = oxc_allocator::Vec
    fn enter_statements(&mut self, stmts: &mut Vec<'a, Statement<'a>>, ctx: &mut TraverseCtx<'a, ()>) {}
    fn exit_statements(&mut self, stmts: &mut Vec<'a, Statement<'a>>, ctx: &mut TraverseCtx<'a, ()>) {}
    // ... hundreds of enter_*/exit_* hooks
}
```

The second type parameter is user state, exposed as `ctx.state`; use `()` when unneeded.

**Rule**: collect in `enter_*` (top-down), transform in `exit_*` (bottom-up, after children are processed).

Key hooks: `expression`, `statements`, `function`, `variable_declarator`, `call_expression`, `identifier_reference`, `binding_identifier`.

### TraverseCtx

| Access                | Purpose                     |
| --------------------- | --------------------------- |
| `ctx.state`           | User state (`State` param)  |
| `ctx.ast`             | `AstBuilder` — create nodes |
| `ctx.ast.allocator`   | `&Allocator`                |
| `ctx.alloc(node)`     | Box a node in the arena     |
| `ctx.scoping()`       | Immutable scoping           |
| `ctx.scoping_mut()`   | Mutable scoping (rare)      |
| `ctx.parent()`        | Parent ancestor             |
| `ctx.ancestor(level)` | Nth ancestor (0 = parent)   |
| `ctx.ancestors()`     | Iterator parent → root      |

### Ancestor system

Each `Ancestor` variant encodes parent type plus the child direction descended from.
"Without" payload types prevent accessing the child field on that path, at compile time:

```rust
match ctx.parent() {
    Ancestor::CallExpressionCallee(call) => { /* in callee position */ }
    Ancestor::BinaryExpressionLeft(bin) => {
        bin.operator();  // OK
        bin.right();     // OK: sibling
        // bin.left();   // Does not exist: compile-time prevented (payload is BinaryExpressionWithoutLeft)
    }
    _ => {}
}
```

### Traverse vs VisitMut

| Feature       | `Traverse` (`oxc_traverse`) | `VisitMut` (`oxc_ast_visit`) |
| ------------- | --------------------------- | ---------------------------- |
| Context       | Full `TraverseCtx`          | None                         |
| Ancestors     | Yes                         | No                           |
| Symbol access | Yes                         | No                           |
| Use for       | **Any semantic-aware pass** | Simple subtree transforms    |

Use `Traverse` for any pass that needs symbol resolution, ancestor context, or scope tracking.
Use `VisitMut` only for syntactic subtree operations (e.g. parameter substitution in a cloned body); it lives in `oxc_ast_visit` and auto-recurses through `walk_mut::*`.

### Running a pass

```rust
let scoping = traverse_mut(&mut my_pass, &allocator, &mut program, scoping, state);  // -> Scoping
```

For many files with the same pass, build a `ReusableTraverseCtx::new(state, scoping, allocator)` once and call `traverse_mut_with_ctx(&mut my_pass, &mut program, ctx)`.

---

## Analysis

Crate `oxc_ecmascript`.
Depends on the AST and semantics.
Every analysis query takes a context; `GlobalContext` supplies global-identifier knowledge, and `WithoutGlobalReferenceInformation` is the null implementation when none is available.

### ECMAScript coercion

| Trait        | Method              | Returns                              |
| ------------ | ------------------- | ------------------------------------ |
| `ToBoolean`  | `to_boolean(ctx)`   | `Option<bool>` — `None` undetermined |
| `ToNumber`   | `to_number(ctx)`    | `Option<f64>`                        |
| `ToJsString` | `to_js_string(ctx)` | `Option<Cow<'a, str>>`               |

Each takes `ctx: &impl GlobalContext<'a>`.
Also exported: `ToBigInt`, `ToInt32`, `ToUint32`, `ToPrimitive`, `StringToNumber`, `ArrayJoin`, `PropName`, `BoundNames`.

### Constant evaluation

```rust
expr.evaluate_value(ctx)              // Option<ConstantValue> — ignores side effects
expr.evaluate_value_to_boolean(ctx)   // Option<bool>; also _to_number, _to_bigint, _to_string
expr.get_side_free_number_value(ctx)  // None if the expression has side effects
```

Use `get_side_free_{number,bigint,boolean,string}_value` before folding.
`ctx` implements `ConstantEvaluationCtx` (`= MayHaveSideEffectsContext + ast() -> AstBuilder`).

### Side-effect analysis

```rust
expr.may_have_side_effects(ctx) -> bool  // ctx: &impl MayHaveSideEffectsContext
```

`MayHaveSideEffectsContext` (supertrait `GlobalContext`) configures the analysis:

| Method                          | Controls                           |
| ------------------------------- | ---------------------------------- |
| `annotations()`                 | Respect `/* @__PURE__ */` comments |
| `manual_pure_functions(callee)` | Treat listed callees as pure       |
| `property_read_side_effects()`  | `PropertyReadSideEffects` policy   |
| `property_write_side_effects()` | Property-write policy              |
| `unknown_global_side_effects()` | Unknown-global-access policy       |

No side effects: literals, resolved identifiers, pure unary/binary/logical, function/arrow expressions.
Side effects: calls, assignments, `delete`, `new`, update expressions, and property access (per policy).

### Value type

```rust
expr.value_type(ctx) -> ValueType  // trait DetermineValueType; ctx: &impl GlobalContext
// Undefined, Null, Number, BigInt, String, Boolean, Object, Undetermined
```

### Operators (oxc_syntax)

| Category | Enum              | Key methods                                                                                     |
| -------- | ----------------- | ----------------------------------------------------------------------------------------------- |
| Binary   | `BinaryOperator`  | `is_equality()`, `is_arithmetic()`, `compare_inverse_operator()`, `equality_inverse_operator()` |
| Unary    | `UnaryOperator`   | `is_keyword()` (typeof, void, delete)                                                           |
| Logical  | `LogicalOperator` | `Or`, `And`, `Coalesce`, `to_assignment_operator()`                                             |
| Update   | `UpdateOperator`  | `Increment`, `Decrement`                                                                        |

Precedence: `expr.precedence()` or `op.precedence()` (trait `GetPrecedence`) — used by codegen for parenthesization.

### Control flow graph

```rust
let ret = SemanticBuilder::new().with_cfg(true).build(&program);  // cargo feature "cfg"
let cfg = ret.semantic.cfg().expect("built with with_cfg(true)");

cfg.basic_block(block_id).is_unreachable()
cfg.is_reachable(from, to)
cfg.is_cyclic(node)
```

Edge types include `Jump` (conditional branch), `Normal` (sequential), `Backedge` (loop), `NewFunction` (nested function entry), `Finalize` (into `finally`), `Error(ErrorEdgeKind)` (exception path, a tuple variant), `Unreachable` (dead code), and `Join` (post-finalizer convergence).
<!-- VERIFY: the CFG types were only verifiable against oxc_cfg 0.49 locally (oxc_cfg 0.135 is not vendored); the crate is behind the `cfg` feature, so exact 0.139 shapes are unconfirmed. -->

---

## Codegen

Crate `oxc_codegen`.
Depends on the AST, and optionally on `oxc_mangler` output for identifier renaming.

```rust
Codegen::new().build(&program).code                                          // Pretty
Codegen::new().with_options(CodegenOptions::minify()).build(&program).code   // Minified

// Mangled identifiers (oxc_mangler)
let mangled = Mangler::new().build(&program);  // ManglerReturn
Codegen::new()
    .with_scoping(Some(mangled.scoping))
    .with_private_member_mappings(Some(mangled.class_private_mappings))
    .build(&program)
    .code
```

`build` takes `&Program<'a>`.
`CodegenReturn<'a>` carries a lifetime (added at 0.136; it was `CodegenReturn` with no lifetime at 0.135) because the sourcemap now borrows from the codegen:

| Field            | Type                    | Notes                                                                                                  |
| ---------------- | ----------------------- | ------------------------------------------------------------------------------------------------------ |
| `code`           | `String`                | Generated source                                                                                       |
| `map`            | `Option<SourceMap<'a>>` | Feature `sourcemap` + `CodegenOptions::source_map_path`. Was `Option<OwnedSourceMap>` (owned) at 0.135 |
| `legal_comments` | `Vec<Comment>`          | From `LegalComment::Linked` / `External`                                                               |

`Codegen` builder methods: `new()`, `with_options(CodegenOptions)`, `with_scoping(Option<Scoping>)`, `with_private_member_mappings(Option<IndexVec<ClassId, FxHashMap<String, CompactStr>>>)`, `build(&Program) -> CodegenReturn`.
`Mangler` builder methods: `new()`, `new_with_temp_allocator()`, `with_options(...)`, `build(&Program) -> ManglerReturn`, `build_with_semantic(...)`; `ManglerReturn` carries `scoping: Scoping` and `class_private_mappings`.
`Mangler` has no `with_stats` method (the 0.135 sources have none, contrary to earlier documentation).

---

## Common patterns

### Expression replacement (in exit_*)

```rust
fn exit_expression(&mut self, expr: &mut Expression<'a>, ctx: &mut TraverseCtx<'a, ()>) {
    if let Expression::Identifier(ident) = expr {
        if let Some(new_expr) = self.try_replace(ident, ctx) {
            *expr = new_expr;
            self.modifications += 1;
        }
    }
}
```

### Statement-list rebuild (in exit_statements)

```rust
fn exit_statements(&mut self, stmts: &mut Vec<'a, Statement<'a>>, ctx: &mut TraverseCtx<'a, ()>) {
    let mut new_stmts = Vec::new_in(ctx.ast.allocator);
    for stmt in stmts.take_in(ctx.ast) {
        if should_keep(&stmt) { new_stmts.push(stmt); }
    }
    *stmts = new_stmts;
}
```

### Store and reuse an expression

```rust
// Reusing while the current Scoping stays valid — keep IDs
self.stored.insert(sym_id, expr.clone_in_with_semantic_ids(ctx.ast.allocator));

// Rebuilding semantics afterwards anyway — plain copy, IDs reset
self.stored.insert(sym_id, expr.clone_in(ctx.ast.allocator));
```

### Value extraction (handles ParenthesizedExpression)

```rust
fn extract_string<'a>(expr: &'a Expression) -> Option<&'a str> {
    match expr {
        Expression::StringLiteral(lit) => Some(lit.value.as_str()),
        Expression::ParenthesizedExpression(p) => extract_string(&p.expression),
        _ => None,
    }
}
```

### Inlining safety check

```rust
let safe_to_inline = ident.reference_id.get()
    .and_then(|ref_id| scoping.get_reference(ref_id).symbol_id())
    .map(|sym_id| !scoping.get_resolved_references(sym_id).any(|r| r.flags().is_write()))
    .unwrap_or(false);  // Unknown/global = not safe
```

### Subtree substitution (VisitMut)

```rust
let mut visitor = ParamSubstituter { subs: &map, alloc: allocator };
visitor.visit_expression(&mut cloned_body);  // Auto-recursion via walk_mut
```

---

## Anti-patterns

| #   | Mistake                                   | Fix                                                                           |
| --- | ----------------------------------------- | ----------------------------------------------------------------------------- |
| 1   | `.reference_id()` / `.symbol_id()` early  | Use `.get()?` — the direct accessors panic on pre-semantic ASTs               |
| 2   | Stale scoping after structural changes    | Rebuild: `SemanticBuilder::new().build(&program)`                             |
| 3   | Expecting `clone_in` to keep semantic IDs | Use `clone_in_with_semantic_ids` (`.clone()` does not compile on arena types) |
| 4   | Storing `&Expression` references          | Clone into `HashMap<SymbolId, Expression>`                                    |
| 5   | Replacing in `enter_*`                    | Use `exit_*` (children not yet processed in enter)                            |
| 6   | Manual recursion over ~50 variants        | Use `VisitMut` + `walk_mut::*`                                                |
| 7   | Skipping `ParenthesizedExpression`        | Always recurse into parens                                                    |
| 8   | Matching `Expression::MemberExpression`   | Does not exist — use specific variants or `as_member_expression()`            |
| 9   | `VisitMut` for semantic transforms        | Use `Traverse` (needs symbols/ancestors)                                      |
| 10  | Reading `semantic.nodes()` by default     | Empty unless `with_build_nodes(true)`                                         |
| 11  | `find_binding(scope_id, "name")`          | Takes `Ident` — wrap with `Ident::from` / `static_ident!`                     |
| 12  | Leaving `take_in` dummies in the AST      | Replace or remove them — or use `replace_with`, which never creates one       |
| 13  | New `ctx.ast.vec()` / `ctx.ast.alloc()`   | Deprecated at 0.139 — use `Vec::new_in` / `Box::new_in`                       |

---

## Limits

OXC is a fast-moving crate ecosystem; its public API shifts across minor releases.

The facts here were verified against **0.139.0** as of **2026-07-09**, using the 0.135.0 crate sources on disk plus the 0.135→0.139 release notes and docs.rs pages.
Re-probe against the installed crate version before relying on any specific signature.

Items that could not be fully confirmed at 0.139 (each marked inline above):

- Whether the legacy `AstBuilder::expression_*` / `statement_*` node methods carry `#[deprecated]` at 0.139 — two reads of the docs.rs page disagreed. The type-associated `new_*` constructors are the confirmed current API; the individual `new_*` names beyond those enumerated follow the same verified pattern but were not each checked.
- The exact receiver form of `take_in` / `take_in_box` at 0.139 (`A` by value at 0.135; docs.rs suggests `&A` at 0.139).
- The error type of `Parser::parse_expression` at 0.139 (`Vec<OxcDiagnostic>` at 0.135; possibly the `Diagnostics` newtype at 0.139).
- The control-flow-graph types (`oxc_cfg`), verifiable only against 0.49 locally and gated behind the `cfg` cargo feature.

Genuinely changed between 0.135 and 0.139 (folded into the content above):
`AllocatorAccessor` → `GetAllocator` (0.138, `allocator()` now `&self`); the `AstBuilder` migration to type-associated `new_*` constructors and deprecation of the `vec`/`vec1`/`alloc`/`ident`/`str` helpers (0.138, issue #23043); the `ReplaceWith` trait; `Ident::from_str_in` / `Str::from_str_in`; the borrowed `CodegenReturn<'a>` sourcemap (0.136); parser and semantic diagnostics moving to the `Diagnostics` newtype; `with_build_nodes`; `as_member_expression` converters; and the `scope_is_descendant_of` / `remove_symbol_declaration` / `retain_resolved_references_excluding` scoping methods.
