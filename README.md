# ee-standard-consumer

A repository that did not author the Equal Experts control register and adopts
it as an ordinary consumer. It exists to be the standard's first outside
adopter, so that anything the standard assumes about its own repository fails
here first rather than at a client.

Its register is `controls.yaml`, fetched from a tag of
[`Eaiger-Ent/ee-standard`](https://github.com/Eaiger-Ent/ee-standard) and
committed. The gates are deployed by the `control-register` plugin's skills;
what to run and in which order is
[`docs/08-adopting.md`](https://github.com/Eaiger-Ent/ee-standard/blob/main/docs/08-adopting.md)
in that repository, which is the guide rather than anything written here.

## Adoption record

### 2026-08-26 — Phase 4, the first adoption

Closed 6/6, with one bounded deviation recorded at the time: `control-register`
was installed from the standard's own directory used as a marketplace, not from
a published one.

### 2026-08-30 — re-adopted from the marketplace

The run that settles that deviation, per
[`docs/16-marketplace-readoption.md`](https://github.com/Eaiger-Ent/ee-standard/blob/main/docs/16-marketplace-readoption.md).
The Phase 4 install was removed and `control-register` re-installed from
`EqualExperts/ee-skills`, the promoted copy. What it found:

- The two marketplaces are byte-identical. `diff -rq` over the `ee-standard`
  and `ee-skills` plugin caches is silent, so the public route an adopter
  follows and the promoted copy the criterion names are one artefact.
- `/register-adopt` dispatched every gate and **wrote nothing**. Each
  applicable control was already stamped at register contract 30 by its gate at
  `0.1.0`, which is what a re-adoption of an unchanged repository should look
  like.
- The checker is unchanged from the Phase 4 measurement: 12 passed, 0 failed,
  1 skipped on the `terraform` predicate, 1 unclassified, 3/3 meta-controls,
  **exit 3**. Exit `3` is the pass — SEC-003's remote blocks answer only inside
  a GitHub Actions job, so a `0` here would mean something had been skipped.
- Both workflows are green on `push` and on `pull_request`.

One thing the runbook asks for could not be produced. It expects
`register-check deployments`, but this repository's checker is pinned to
`v0.5.0` at register contract 30 and that subcommand does not exist there — it
arrived later, with ADR 0038. The gate state was read from `deployed_by` and
the provenance stamps instead.
