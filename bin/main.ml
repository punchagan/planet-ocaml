(* ocaml-planet – full-content Atom feed aggregator
   =====================================================================
   Reads the list of blog feeds from ocaml.org's planet-sources.yml,
   fetches every feed via River, and writes a single Atom feed.

   Build  : dune build
   Run    : ./_build/default/bin/main.exe [OPTIONS]
*)

let default_sources_url =
  "https://raw.githubusercontent.com/ocaml/ocaml.org/main/data/planet-sources.yml"

(* ── Parse planet-sources.yml into River.source list ──────────────── *)

let parse_sources content : River.source list =
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
         | Some name, Some url when not disabled ->
           Some { River.name; url }
         | _ -> None)
      | _ -> None
    ) items
  | Ok _ -> failwith "planet-sources.yml: expected a top-level YAML list"

(* ── Fetch the sources YAML over HTTP ─────────────────────────────── *)

let fetch_url_sync url =
  Lwt_main.run (
    let open Lwt.Syntax in
    let* _resp, body =
      Cohttp_lwt_unix.Client.get (Uri.of_string url)
    in
    Cohttp_lwt.Body.to_string body
  )

(* ── Entry point ───────────────────────────────────────────────────── *)

let () =
  let output      = ref "feed.xml" in
  let sources_url = ref default_sources_url in
  let sources_file = ref "" in
  let feed_title  = ref "OCaml Planet" in
  let feed_id     = ref "https://planet.ocaml.org/feed.xml" in
  Arg.parse
    [ "--output",       Arg.Set_string output,
        " Output file (default: feed.xml)"
    ; "--sources-url",  Arg.Set_string sources_url,
        " URL of planet-sources.yml"
    ; "--sources-file", Arg.Set_string sources_file,
        " Local planet-sources.yml (overrides --sources-url)"
    ; "--title",        Arg.Set_string feed_title,
        " Atom feed <title>"
    ; "--id",           Arg.Set_string feed_id,
        " Atom feed <id> / self URL"
    ]
    (fun _ -> ())
    "ocaml-planet [OPTIONS]";

  let yaml_str =
    if !sources_file <> "" then
      In_channel.with_open_text !sources_file In_channel.input_all
    else
      fetch_url_sync !sources_url
  in
  let sources = parse_sources yaml_str in
  Printf.printf "Loaded %d sources\n%!" (List.length sources);

  let feeds = List.filter_map (fun (src : River.source) ->
    match River.fetch src with
    | feed -> Some feed
    | exception exn ->
      Printf.eprintf "[SKIP] %s: %s\n%!" src.name (Printexc.to_string exn);
      None
  ) sources in
  let posts = River.posts feeds in
  Printf.printf "Total posts: %d\n%!" (List.length posts);

  let entries =
    River.create_atom_entries posts
    |> List.sort Syndic.Atom.descending
  in

  let id = Uri.of_string !feed_id in
  let feed =
    Syndic.Atom.feed
      ~id
      ~title:(Syndic.Atom.Text !feed_title)
      ~updated:(Ptime_clock.now ())
      ~links:[ Syndic.Atom.link ~rel:Syndic.Atom.Self id ]
      entries
  in

  let oc = open_out !output in
  Syndic.Atom.output feed (`Channel oc);
  close_out oc;
  Printf.printf "Written → %s\n%!" !output
