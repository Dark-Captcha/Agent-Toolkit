# Economy

What earns the right to exist, what really counts as duplication, and how to stop making more than the problem asked for.
This expands the fourth principle of [`CORE.md`](../CORE.md): everything must earn its existence.

## Contents

- [Liability accounting](#liability-accounting)
- [The two duplications](#the-two-duplications)
- [Abstraction discipline](#abstraction-discipline)
- [No spam](#no-spam)
- [Deletion](#deletion)
- [Limits](#limits)

## Liability accounting

Value lives in what the code does; cost lives in the text someone has to read to work with it.
Every line added will be read again by every debugging session that passes through it, understood again by every maintainer, and justified again at every rewrite — and next to all of that, writing it was the cheap part.

So the thing to measure is not lines produced but problems solved per line a stranger has to hold in their head.
The best change of all solves the problem and leaves the repository smaller than it found it.

## The two duplications

There are two different things people call duplication, and only one of them is a problem.

Text duplication is the same characters showing up twice.
It is cosmetic, and now and then it is exactly right.

Knowledge duplication is the same decision written down in two places — a constant and a copy of its value pasted somewhere else, a rule enforced in code and restated in a comment, a wire format that two parsers each assume on their own.
This is the one that rots.
The two copies will drift apart — not might, will — and from that day on the system quietly believes two contradictory things at once.

So knowledge gets deduplicated every time; text only when the same characters really do encode one decision.
And when a single fact genuinely has to live in two places, one of them is the source and the other openly points to it — because a pointer goes stale loudly, where a copy goes stale in silence.

## Abstraction discipline

The rule of three: write it the first time, notice it and resist the second, and only on the third consider pulling it into one place — and even then, only if the sameness is essential rather than incidental.

Sameness is essential when the copies have to change together because they express the same decision: a shared spec, a shared invariant.
It is incidental when they merely happen to look alike today, and next quarter's requirements will pull them apart.
Abstracting incidental sameness welds two unrelated things into one, and that weld is expensive to cut later.

A wrong abstraction costs more than the duplication it replaced, and it tends to announce itself:

- flags and mode switches multiplying at the call sites to steer its behavior,
- callers undoing part of what it just did to them,
- every caller leaning on a different third of it.

The way out is honest and allowed: inline it back into each caller, let the copies drift apart, and re-extract later only the part that turns out to be genuinely shared.
Taking an abstraction apart is progress, not regression.

## No spam

The smallest true change, in practice:

- Leave untouched anything the request did not ask about — every gratuitous reflow, reorder, or rename muddies the blame history, bloats the review, and invites a merge conflict for nothing.
- A wall of nearly identical blocks is a loop, a table, or a derivation that has not been written yet — write the thing that generates the sameness, not the sameness itself.
- Build no scaffolding for imagined futures: no empty directories, no unused configuration, no "we might want this later" files. Capacity for a load that never arrives is debt without the loan ([`design.md`](design.md)).
- The same restraint applies to prose: one idea, said once, in the best place for it. A document that repeats itself teaches its readers to skim, and a skimming reader sails right past the one line that mattered.

## Deletion

Dead code is not harmless storage; it is active misinformation.
Every reader assumes it still runs, every search turns it up, every refactor drags it along for the ride.

Delete it rather than comment it out — version control is the archive, and a far better one.
Code that has been deleted cannot rot, cannot leak, and cannot mislead anyone.

Scope still applies: inside the agent's own change, removing the orphans it created is part of the job; outside it, dead code is something to report to the owner, not to quietly clean up unasked.

## Limits

Sometimes duplication is the right call — always as a deliberate choice with a stated reason, never an accident wearing an excuse.

- **Tests** — repetition that keeps each test readable on its own beats a maze of shared helpers; a failing test should be diagnosable without an archaeology dig.
- **Independence boundaries** — two modules meant to evolve apart should not be joined through a shared helper just to save five lines; the coupling will cost more than the lines ever did.
- **Teaching** — an example should stand on its own, even where that means repeating the manual.
- **Measured hot paths** — a deliberate specialized copy, justified by a real measurement and labeled as the copy it is.
