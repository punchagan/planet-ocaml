(* ocaml-planet – full-content Atom feed aggregator
   =====================================================================
   Reads the list of blog feeds from ocaml.org's planet-sources.yml,
   fetches every feed concurrently via River, and writes a single Atom
   feed using Syndic.Atom.

   Build  : dune build
   Run    : ./_build/default/bin/main.exe [OPTIONS]
*)

(* ───────────────────────────────────────────────────────────────────
   Defaults
   ─────────────────────────────────────────────────────────────────── *)

let default_sources_url =
  "https://raw.githubusercontent.com/ocaml/ocaml.org/main/data/planet-sources.yml"

(* ───────────────────────────────────────────────────────────────────
   Source record (parsed from planet-sources.yml)
   ─────────────────────────────────────────────────────────────────── *)

type source = {
  name : string;
  feed : string;   (* RSS or Atom feed URL *)
}

let parse_sources content =
  match Yaml.of_string content with
  | Error (`Msg m) -> failwith ("YAML parse error: " ^ m)
  | Ok (`A items) ->
    List.filter_map (function
      | `O fields ->
        let get k =
          match List.assoc_opt k fields with
          | Some (`String s) -> Some s
          | _                -> None
        in
        let disabled =
          match List.assoc_opt "disabled" fields with
          | Some (`Bool true) -> true
          | _ -> false
        in
        (match get "name", get "url" with
         | Some name, Some feed when not disabled -> Some { name; feed }
         | _ -> None)
      | _ -> None
    ) items
  | Ok _ -> failwith "planet-sources.yml: expected a top-level YAML list"

(* ───────────────────────────────────────────────────────────────────
   HTTP fetch of the sources YAML
   (River.fetch handles feed HTTP internally; we only need cohttp here
   to download the planet-sources.yml file itself.)
   ─────────────────────────────────────────────────────────────────── *)

let fetch_url_sync url =
  Lwt_main.run (
    let open Lwt.Syntax in
    let* _resp, body =
      Cohttp_lwt_unix.Client.get (Uri.of_string url)
    in
    Cohttp_lwt.Body.to_string body
  )

(* ───────────────────────────────────────────────────────────────────
   Feed fetching
   River.fetch calls Lwt_main.run internally; since Lwt has a single
   global scheduler, concurrent calls from multiple threads are not
   allowed.  We fetch sequentially — fine for a nightly batch job.
   ─────────────────────────────────────────────────────────────────── *)

let fetch_one src =
  let river_src = { River.name = src.name; url = src.feed } in
  match River.fetch river_src with
  | feed ->
    Printf.printf "[OK]   %s\n%!" src.name;
    Some feed
  | exception exn ->
    Printf.eprintf "[SKIP] %s: %s\n%!" src.name (Printexc.to_string exn);
    None

(* ───────────────────────────────────────────────────────────────────
   Entry point
   ─────────────────────────────────────────────────────────────────── *)

let () =
  let output       = ref "feed.xml" in
  let sources_url  = ref default_sources_url in
  let sources_file = ref "" in
  let feed_title   = ref "OCaml Planet" in
  let feed_id      = ref "https://planet.ocaml.org/feed.xml" in
  Arg.parse
    [ "--output",        Arg.Set_string output,
        " Output file (default: feed.xml)"
    ; "--sources-url",   Arg.Set_string sources_url,
        " URL of planet-sources.yml (default: ocaml.org GitHub raw)"
    ; "--sources-file",  Arg.Set_string sources_file,
        " Local planet-sources.yml (overrides --sources-url)"
    ; "--title",         Arg.Set_string feed_title,
        " Atom feed <title> (default: \"OCaml Planet\")"
    ; "--id",            Arg.Set_string feed_id,
        " Atom feed <id> / self URL"
    ]
    (fun _ -> ())
    "ocaml-planet [OPTIONS]\n\
     Aggregate RSS/Atom feeds into a single full-content Atom feed.\n";

  (* 1. Load planet-sources.yml ---------------------------------------- *)
  let yaml_str =
    if !sources_file <> "" then
      In_channel.with_open_text !sources_file In_channel.input_all
    else
      fetch_url_sync !sources_url
  in
  let sources = parse_sources yaml_str in
  Printf.printf "Loaded %d sources\n%!" (List.length sources);

  (* 2. Fetch all feeds ------------------------------------------------- *)
  let feeds = List.filter_map fetch_one sources in
  Printf.printf "Fetched %d feeds successfully\n%!" (List.length feeds);

  (* 3. Collect and deduplicate posts via River -------------------------- *)
  let posts = River.posts feeds in
  Printf.printf "Total posts (deduplicated): %d\n%!" (List.length posts);

  (* 4. Convert to Syndic Atom entries, sort newest-first --------------- *)
  let entries =
    River.create_atom_entries posts
    |> List.sort Syndic.Atom.descending
  in

  (* 5. Build the Atom feed --------------------------------------------- *)
  let now      = Ptime_clock.now () in
  let self_uri = Uri.of_string !feed_id in
  let atom_feed =
    Syndic.Atom.feed
      ~id:self_uri
      ~title:(Syndic.Atom.Text !feed_title)
      ~updated:now
      ~links:[ Syndic.Atom.link ~rel:Syndic.Atom.Self self_uri ]
      entries
  in

  (* 6. Write output ---------------------------------------------------- *)
  Syndic.Atom.write atom_feed !output;
  Printf.printf "Written → %s\n%!" !output
