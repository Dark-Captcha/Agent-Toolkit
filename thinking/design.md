# Design

How to build something that outlives the person who built it — code, schemas, APIs, documents, even the shape of a directory tree.
This expands the third principle of [`CORE.md`](../CORE.md): build the hinge, not the motor.

## Contents

- [What survives](#what-survives)
- [Simplicity compounds](#simplicity-compounds)
- [Constraints are the design](#constraints-are-the-design)
- [Dependencies](#dependencies)
- [Data outlives code](#data-outlives-code)
- [Two kinds of doors](#two-kinds-of-doors)
- [Direction of dependence](#direction-of-dependence)
- [Name the price](#name-the-price)
- [Limits](#limits)

## What survives

Look at the things still standing after a hundred years, and the same few traits keep turning up.
They have few parts, and the parts are passive — nothing that has to be powered, patched, or renewed on a schedule.
Their interfaces are ordinary, so a stranger with common tools can repair them, not only the person who first built them.
How they work is plain from looking at them.
When they fail, they fail a piece at a time and out loud, instead of all at once and in silence.
And nothing they lean on is perishable — there is no single part whose death drags the whole thing down with it.

That list is the target.
Build toward it and time becomes an ally; ignore it and time turns into an attacker that always, eventually, wins.

## Simplicity compounds

Every part of a system can touch every other part, so the cost of a system climbs with the square of its parts while the value climbs, at best, in a straight line.
The scarcest thing a project ever owns is the understanding held in people's heads, and complexity is a tax on it that is never done being collected.

Simple and easy are not the same word.
Easy is whatever takes the least effort right now; simple is having few parts tangled together, and it is usually the harder of the two to reach.
The catch is that the effort of simple is paid once, up front, while the cost of easy is charged again on every future visit — which makes simple the cheaper deal even on the days it feels more expensive.

## Constraints are the design

Designing is mostly deciding what is not allowed to happen.
The strongest way to forbid a wrong state is to leave no way to express it in the first place, rather than to write a check that hunts for it — a type that cannot hold nonsense beats a validator looking for nonsense, and a layout where a misplaced file looks obviously wrong beats a review comment asking someone to move it.

Structure beats vigilance, construction beats discipline, and a good default beats a page of documentation — because vigilance, discipline, and documentation all evaporate the moment the work changes hands, and structure stays.
A system that is safe because of how it is built asks nothing of the people who come after it, and that is the only kind of safety that survives them.

## Dependencies

CORE already states the vow: a dependency is a marriage.
Before entering one, walk the questions:

- Does it solve a problem essential to the work, or just an inconvenience that could be absorbed?
- Is it more likely than not to outlive the project? Age and dullness are evidence here; a star count is not.
- Could the ten percent of it actually used simply be written by hand instead?
- On the worst day, what does its failure look like — and is that survivable?

Preference runs from the standard library, to something established and boring, to something small enough to inline, and only then to something new and clever.
Every dependency is also a bet that its maintainers will keep making the same calls the project would, for years — so the bets are placed rarely, and only on evidence.

## Data outlives code

Spend design effort in the order things are expensive to change: the data format first, then the public interface, then the internal structure, and the implementation last.
An implementation can be rewritten in an afternoon; migrating a data format can take years and shed users along the way.

Data outlives code, so choose formats a stranger with a text editor could still make sense of: plain text over binary until a measurement forces the switch, a standard format over an invented one, self-describing over positional.
Make every schema and interface decision while picturing its migration, because migration is where systems quietly go to die.

## Two kinds of doors

Sort every decision into one of two kinds, and spend accordingly.

A two-way door is cheap to walk back through — internal structure, a private helper, a rough draft.
Push it open, look around, step back if it was wrong; agonizing over these is the real waste.

A one-way door is expensive to reverse — a published name, a wire format, a data layout, anything with users already on the far side.
For these, slow down: prototype the alternatives, decide on evidence, and design the way out before walking in.

Most doors are two-way.
Treat them all as one-way and nothing ever ships; treat them all as two-way and something irreversible breaks; the whole skill is telling which is which.

## Direction of dependence

Inside a system, dependencies point one way — downward — and gather in one place.
A lower layer never knows anything about the layers above it.

A cycle is not a matter of taste.
It fuses everything in the loop into a single block: nothing in it can be tested on its own, reused on its own, or deleted on its own — and being able to delete a piece is the goal state of all code.

## Name the price

Every design choice costs something, and a proposal that mentions no cost is an advertisement, not a design.
State it plainly: **X over Y — it gains A, it pays B, and B is worth paying here because C.**

When the choice is heavier than the simplest thing that would work, name the specific reason that justifies the weight: a measurement, a hard requirement, a regulation.
Never a fashion, and never a future that might not arrive — capacity built for a load that never shows up is a debt taken on without ever seeing the loan.

## Limits

- **A prototype exists to answer one question**, and its proper ending is deletion — build it for speed of learning, because durability spent on it is wasted.
- **A perfect hinge on the wrong door is still wrong.** Durability multiplies whatever it is applied to, the good and the bad alike, so the intent gets validated first ([`intent.md`](intent.md)).
- **A standard that fits the problem badly** costs more than a small, clean invention — boring is the default, not a cage, though the burden of proof always sits on the invention.
