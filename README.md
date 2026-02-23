# planet-ocaml

A personal Atom feed aggregator for OCaml blogs.

[ocaml.org/planet.xml](https://ocaml.org/planet.xml) aggregates the OCaml community's
blogs, but its feed only includes summaries — not full post content. This makes
it awkward to use with feed readers, especially offline ones.

This project fetches the same sources and produces a single Atom feed with full
entry content, published nightly to GitHub Pages:

**https://punchagan.github.io/planet-ocaml/feed.xml**

It is particularly useful with feed readers like
[elfeed](https://github.com/skeeto/elfeed/) and
[elfeed-offline](https://github.com/punchagan/elfeed-offline)

## How it works

- Source list is pulled from
  [ocaml.org's planet-sources.yml](https://github.com/ocaml/ocaml.org/blob/main/data/planet-sources.yml)
- Feeds are fetched using [River](https://github.com/tarides/river) and
  aggregated with [Syndic](https://github.com/Cumulus/Syndic)
- A GitHub Actions workflow runs nightly, generates `feed.xml`, and publishes
  it via GitHub Pages

## Building locally

```
dune build
dune exec -- bin/main.exe
```

Requires [dune](https://dune.build) — dependencies are managed via
`dune pkg` and pinned in `dune.lock`.

## License

WTFPL

---

*This project was built with [Claude](https://claude.ai).*
