let location_errorf ~loc =
  Format.ksprintf (fun err ->
    raise (Ocaml_common.Location.Error (Ocaml_common.Location.error ~loc err))
  )

(* Same as [List.find_map] introduced in OCaml 4.10. *)
let rec find_map f = function
  | [] -> None
  | x :: l ->
     (match f x with
       | Some _ as result -> result
       | None -> find_map f l)

(* Return the list of paths we should try using, in order. *)
let get_candidate_paths ~loc path =
  let source_dir = loc.Ocaml_common.Location.loc_start.pos_fname |> Filename.dirname in
  if Filename.is_relative path then
    let absolute_path = Filename.concat source_dir path in
    (* Try the path relative to the source file first, then the one relative to the
       current working directory (typically, the build directory). *)
    [absolute_path; path]
  else
    (* The user passed an absolute path. Use as is. *)
    [path]

let read_file path =
  try
    let file = open_in_bin path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr file)
      (fun () ->
        Some (really_input_string file (in_channel_length file)))
  with _ ->
    None

let read_path path =
  match Sys.is_directory path with
  | true ->
    let l = Sys.readdir path
    |> Array.to_list
    |> List.filter_map (fun p -> match read_file @@ Filename.concat path p with None -> None | Some s -> Some (p,s))
    in Some (`Dir l)
  | false ->
  match read_file path with
  | None -> None
  | Some s -> Some (`File s)

let get_blob ~loc path =
  match find_map read_path (get_candidate_paths ~loc path) with
  | Some blob -> blob
  | None -> location_errorf ~loc "[%%blob] could not find or load path %s" path

let expand ~ctxt path =
  let open Ppxlib in
  let loc = Expansion_context.Extension.extension_point_loc ctxt in
  let open Ast_builder.Default in
  match get_blob ~loc path with
  | `File s -> estring ~loc s
  | `Dir l -> elist ~loc (l |> List.map (fun (p,s) -> pexp_tuple ~loc [estring ~loc p; estring ~loc s]))

let extension =
  let open Ppxlib in
  Extension.V3.declare "blob" Extension.Context.expression
    Ast_pattern.(single_expr_payload (estring __))
    expand

let rule = Ppxlib.Context_free.Rule.extension extension

let () =
  Ppxlib.Driver.register_transformation ~rules:[rule] "ppx_blob"
