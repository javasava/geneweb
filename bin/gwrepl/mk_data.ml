(* This file is used to generate the file 'data.cppo.ml', containing all
   the files (cmis, cmas, .so) that could be used at runtime by
   a geneweb interpreter.

   See 'data.mli' for the signature of the generated file. *)


let read_lines p =
  let rec loop () = match input_line p with
    | exception End_of_file -> close_in p ; []
    | line -> line :: loop ()
  in loop ()

let process cmd =
  let (stdout, _, stderr) as p =
    Unix.open_process_full cmd (Unix.environment ())
  in
  let out = read_lines stdout in
  let err = read_lines stderr in
  ignore @@ Unix.close_process_full p ;
  out, err

module Either = struct type ('a, 'b) t = Left of 'a | Right of 'b end

let partition_map p l =
  let rec part left right = function
  | [] -> (List.rev left, List.rev right)
  | x :: l ->
     begin match p x with
       | Some (Either.Left v) -> part (v :: left) right l
       | Some (Either.Right v) -> part left (v :: right) l
       | None -> part left right l
     end
  in
  part [] [] l

let (//) = Filename.concat

let if_sosa_zarith out fn =
  Printf.fprintf out "\n#ifdef SOSA_ZARITH\n" ;
  fn () ;
  Printf.fprintf out "\n#endif\n"

let () =
  let opam_swich_prefix = Sys.getenv "OPAM_SWITCH_PREFIX" in
  let opam_swich_prefix_lib = opam_swich_prefix // "lib" in

  let dune_root, root, ( directories0, files0 ) =

    let ic = open_in ".depend" in
    let lines = read_lines ic in
    close_in ic ;
    let dune_root, out = match lines with
      | [] -> assert false
      | dune_root :: out -> dune_root, out
    in
    let root = dune_root // "_build" // "default" // "lib" in
    let aux fn =
      let aux prefix =
        if String.length fn > String.length prefix
        && String.sub fn 0 (String.length prefix) = prefix
        then Some (String.sub fn (String.length prefix) (String.length fn - String.length prefix))
        else None
      in
      match aux opam_swich_prefix_lib with
      | Some x -> Some (`opam x)
      | None -> match aux root with
        | Some x -> Some (`root x)
        | None -> None
    in
    dune_root, root,
    partition_map begin fun s ->
      try Scanf.sscanf s {|#directory "%[^"]";;|} (fun s -> match aux s with Some s -> Some (Either.Left s) | _ -> None)
      with _ ->
      try Scanf.sscanf s {|#load "%[^"]";;|} (fun s -> match aux s with Some s -> Some (Either.Right s) | _ -> None)
      with _ -> failwith s
    end out

  in
  let directories =
    ("etc" // "lib" // "ocaml")
    :: ("etc" // "lib" // "ocaml" // "stublibs")
    :: List.map begin function
      | `opam d -> "etc" // "lib" // d
      | `root d -> "etc" // "lib" // "geneweb" // (d |> Filename.dirname |> Filename.dirname)
    end directories0
  in
  let files0 = `opam ("ocaml" // "stdlib.cma") :: files0 in
  let cmas, cmis =
    List.fold_right begin fun x (cmas, cmis) -> match x with
      | `opam fn ->
        let aux fn = opam_swich_prefix_lib // fn, "etc" // "lib" // fn in
        let cmas = aux fn :: cmas in
        let (src, _) as cmi = aux (Filename.remove_extension fn ^ ".cmi") in
        let cmis = if Sys.file_exists src then cmi :: cmis else cmis in
        (cmas, cmis)
      | `root fn ->
        let cma = root // fn, "etc" // "lib" // "geneweb" // fn in
        let cmas = cma :: cmas in
        let dir = dune_root // "_build" // "install" // "default" // "lib" // "geneweb" // Filename.(dirname fn |> basename) in
        let cmis =
          Array.fold_left begin fun cmis s ->
            if Filename.check_suffix (Filename.concat dir s) "cmi"
            then (Filename.concat dir s, "etc" // "lib" // "geneweb" // Filename.concat (Filename.basename dir) s) :: cmis
            else cmis
          end cmis (
            try
              Sys.readdir dir
            with exn ->
              Printf.eprintf "Error in Sys.readdir(%S)\n%!" dir;
              raise exn
          )
        in
        (cmas, cmis)
    end files0 ([], [])
  in
  let cmis =
    let select =
      let pref = opam_swich_prefix_lib // "ocaml" // "stdlib__" in
      let len = String.length pref in
      fun s -> String.length s > len && String.sub s 0 len = pref
    in
    Array.fold_left begin fun cmis s ->
      let fname = opam_swich_prefix_lib // "ocaml" // s in
      if Filename.check_suffix fname "cmi" && select fname
      then (fname, "etc" // "lib" // "ocaml" // s) :: cmis
      else cmis
    end cmis (Sys.readdir (opam_swich_prefix_lib // "ocaml"))
  in
  let data = "data.cppo.ml" in
  let out = open_out_bin data in
  begin
    let print_dir d = Printf.fprintf out {|"%s";|} d in
    Printf.fprintf out {|let directories=[||} ;
    List.iter print_dir directories ;
    if_sosa_zarith out (fun () -> print_dir ("etc" // "lib" // "stublibs")) ;
    Printf.fprintf out {||];;|}
  end ;
  begin
    let aux s list =
      Printf.fprintf out {|let %s=[||} s;
      List.iter begin fun (src, dst) ->
        Printf.fprintf out {blob|{|%s|},[%%blob {|%s|}];|blob} dst src
      end list ;
      Printf.fprintf out {||];;|}
    in
    aux "cmis" cmis ;
    aux "cmas" cmas
  end ;
  begin
    Printf.fprintf out {|let shared=[||} ;
    if Sys.unix then begin (* FIXME: what is the windows version? *)
      let aux s =
        Printf.fprintf out {blob|Filename.(concat "etc" (concat "lib" {|%s|})),[%%blob {|%s|}];|blob}
          s (opam_swich_prefix_lib // s)
      in
      List.iter aux [ "ocaml" // "stublibs" // "dllcamlstr.so"
                    ; "ocaml" // "stublibs" // "dllunix.so"
                    ] ;
      if_sosa_zarith out (fun () -> aux ("stublibs" // "dllzarith.so")) ;
    end ;
    Printf.fprintf out {||];;|}
  end ;
  begin
    let b = Buffer.create 1024 in
    let aux = List.iter (fun (src, _) -> Digest.file src |> Digest.to_hex |> Buffer.add_string b) in
    aux cmis ;
    aux cmas ;
    Printf.fprintf out {|let md5="%s";;|} (Buffer.contents b |> Digest.string |> Digest.to_hex)
  end
