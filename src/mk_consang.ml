(* camlp4r ./pa_lock.cmo *)
(* $Id: mk_consang.ml,v 3.5 2000-06-26 09:25:38 ddr Exp $ *)
(* Copyright (c) 2000 INRIA *)

value fname = ref "";
value indexes = ref False;
value scratch = ref False;
value quiet = ref False;

value errmsg = "usage: " ^ Sys.argv.(0) ^ " [options] <file_name>";
value speclist =
  [("-q", Arg.Set quiet, ": quiet mode");
   ("-i", Arg.Set indexes, ": build the indexes again");
   ("-scratch", Arg.Set scratch, ": from scratch");
   ("-mem", Arg.Set Iobase.save_mem,
    ": Save memory, but slower when rewritting data base");
   ("-nolock", Arg.Set Lock.no_lock_flag, ": do not lock data base.")]
;
value anonfun s =
  if fname.val = "" then fname.val := s
  else raise (Arg.Bad "Cannot treat several data bases")
;

value simple_output bname base =
  let no_patches =
    let bname =
      if Filename.check_suffix bname ".gwb" then bname
      else bname ^ ".gwb"
    in
    not (Sys.file_exists (Filename.concat bname "patches"))
  in
  Iobase.gen_output (no_patches && not indexes.val) bname base
;

value main () =
  do ifdef MAC then
       do Printf.eprintf "args? "; flush stderr;
          let line = input_line stdin in
          let list = Gutil.arg_list_of_string line in
          Argl.parse_list speclist anonfun errmsg list;
       return ()
     else ();
     Argl.parse speclist anonfun errmsg;
     if fname.val = "" then
       do Printf.eprintf "Missing file name\n";
          Printf.eprintf "Use option -help for usage\n";
          flush stderr;
       return ()
     else ();
  return
  let f () =
    let base = Iobase.input fname.val in
    try
      do Sys.catch_break True;
         try ConsangAll.compute base scratch.val quiet.val with
         [ Sys.Break -> do Printf.eprintf "\n"; flush stderr; return () ];
         simple_output fname.val base;
      return ()
    with
    [ Consang.TopologicalSortError ->
        do Printf.printf "
Error: probable loop in database (persons being their own ancestors).\n";
           flush stdout;
        return exit 2 ]
  in
  lock (Iobase.lock_file fname.val) with
  [ Accept -> f ()
  | Refuse ->
      do Printf.eprintf "Base is locked. Waiting... ";
         flush stderr;
      return
      lock_wait (Iobase.lock_file fname.val) with
      [ Accept ->
          do Printf.eprintf "Ok\n";
             flush stderr;
          return f ()
      | Refuse ->
          do Printf.printf "\nSorry. Impossible to lock base.\n";
             flush stdout;
          return exit 2 ] ]
;

Printexc.catch main ();
