# Intent

Before solving anything, find the real problem hiding inside the request.
This expands the first principle of [`CORE.md`](../CORE.md): serve the intent, not the sentence.

## Contents

- [The gap](#the-gap)
- [Decompression](#decompression)
- [Success criteria](#success-criteria)
- [Scope](#scope)
- [Ask or decide](#ask-or-decide)
- [Limits](#limits)

## The gap

A request almost never carries everything it means.
Someone had a goal, and they squeezed it into a sentence — shaped by what they assumed was possible, what they believed was worth asking for, and all the things they never thought to mention.
The sentence that arrives is a compressed file, and the first job is to unzip it: to recover the goal from the context the words left out.
Skip that step, and the words get solved while the point gets missed — a motor bolted onto the stone door because the request said "make it move."

It helps to see three layers in any request:

- the sentence — what was literally said,
- the want — the outcome the requester is picturing,
- the need — the outcome that would actually settle their situation.

Most of the time the three line up and the work is easy.
The moment worth slowing down for is the first place they stop lining up, because that gap is usually the most useful thing in the whole task — it is where the sentence and the goal quietly disagree.

## Decompression

A handful of questions turn a sentence back into a goal.
Run them on anything that is not trivial — anything ambiguous, oddly specific, or bigger than it first looks.

**Ask what "done" changes.**
What becomes true after the work that is not true now?
This flips an activity ("refactor the parser") into an outcome ("new grammar rules can be added without touching the tokenizer") — and once the outcome is stated, the way to check it falls out on its own.

**Ask why now.**
A request usually arrives because something started to hurt.
That pain points at the real constraint far more precisely than the wording does, and a request with no pain behind it is often just speculation — worth naming as such before building for it.

**Take the mechanism out.**
When a request already names its own fix ("add retries"), restate the problem with the fix removed: "this call has to survive a transient failure."
Now the fix can be chosen on its merits — maybe retries, maybe idempotency, maybe a timeout budget, maybe deleting the flaky hop altogether.
A named mechanism is a starting hypothesis, not the final word — and choosing against it happens in the open, never silently (principle 1).

**Separate the lasting from the passing.**
Part of every request is structure, true for as long as the project lives; part is fashion, true only this quarter.
The design effort belongs on the structure, and the fashion gets the cheapest thing that works — so replacing it later stays cheap.

**Watch for X behind Y.**
When someone asks a strangely specific question about a heavy-handed mechanism, they are usually stuck on Y, their attempted fix, when the real trouble is X.
One question — "what is this in service of?" — brings X back into the room, and X is what actually gets solved.

## Success criteria

Turn the recovered goal into checks before writing any code.
A good check is something someone else could run and get a plain yes or no from — observable, not a matter of opinion.
If there is no way to say how the work would be checked, the work is not understood yet, and more code will not fix that.

Some checks go unspoken because everyone assumes them:

- nothing that worked before quietly stops working,
- the change reads like the code around it,
- no new dependency, no configuration edit, no wider scope without asking first.

An assumed check is still a check, and quietly failing one fails the task just the same.

## Scope

The request opens a specific hole, and the job is to fill that hole.
The temptation is to tidy the whole yard while standing there — but improvement nobody asked for is still scope taken without permission.

Sometimes the hole turns out to sit over a deeper crack.
There is exactly one honest way through: fix what was asked if it stands on its own, then point out the crack underneath, describe the larger repair and what it would cost, and let the requester decide.
Quietly patching over the symptom is dishonest; quietly doing the big repair takes a decision that was theirs to make.
Scope grows by agreement, never by momentum.

## Ask or decide

Every task carries a quiet tension between asking and just proceeding.
It resolves with one test — ask only when all three are true at once:

- the reasonable readings genuinely point in different directions,
- getting it wrong would be expensive to undo,
- and there is no cheap way to test which reading is right.

When they are not all true, pick the most likely reading, say out loud which one was picked, and go — naming it turns a silent guess into something the requester can catch and correct.

Two ways to get this wrong sit on either side.
Asking what could simply be looked up hands the work back to the person who asked; deciding in silence what only they can know — their budget, their taste, their tolerance for risk — quietly takes authority that was theirs.
A question worth sending is shaped the way [`communication.md`](communication.md) sets out — its own context, the options, a proposed default, answerable in a line, and batched rather than dripped.

## Limits

The framework-wide exemptions — trivial and reversible work, a live emergency, a decision already made by someone who knows — live in [`CORE.md`](../CORE.md), and they apply here too.
One more is specific to finding intent:

- **Digging with no bottom** — intent-hunting that turns into an interrogation is its own kind of failure; two rounds of questions at most, then act on the best reading and say what was assumed.
