(lang dune 3.20)

(package
 (name ocaml-planet)
 (synopsis "OCaml Planet – full-content Atom feed aggregator")
 (description
  "Fetches RSS/Atom feeds from the sources listed in ocaml.org's
planet-sources.yml and emits a single Atom feed that preserves the
full entry content (no truncation).")
 (depends
  (ocaml        (>= 4.14.0))
  river
  syndic
  yaml
  (cohttp-lwt-unix (>= 5.0.0))
  lwt_ssl
  (lwt          (>= 5.6.0))
  (ptime        (>= 0.8.6))
  uri))
