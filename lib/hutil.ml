(* Copyright (c) 2007 INRIA *)

open Config
open Def

let link_to_referer conf =
  let referer = Util.get_referer conf in
  let back = Utf8.capitalize_fst (Util.transl conf "back") in
  if (referer :> string) <> "" then
    ({|<a href="|}
     ^<^ referer ^>^
     {|"><span class="fa fa-arrow-left fa-lg" title="|} ^ back ^ {|"></span></a>|}
     :> Adef.safe_string)
  else Adef.safe ""

let gen_print_link_to_welcome f conf right_aligned =
  if right_aligned then
    Output.printf conf "<div class=\"btn-group float-%s mt-2\">\n" conf.right
  else Output.print_sstring conf "<p>\n";
  f ();
  let str = link_to_referer conf in
  if (str :> string) <> "" then Output.print_string conf str;
  Output.print_sstring conf {|<a href="|};
  Output.print_string conf (Util.commd ~senv:false conf) ;
  Output.print_sstring conf {|"><span class="fa fa-home fa-lg ml-1 px-0" title="|};
  Output.print_sstring conf (Utf8.capitalize (Util.transl conf "home"));
  Output.print_sstring conf {|"></span></a>|} ;
  if right_aligned then Output.print_sstring conf "</div>"
  else Output.print_sstring conf "</p>"

let print_link_to_welcome = gen_print_link_to_welcome (fun () -> ())

(* S: use Util.include_template for "hed"? *)
let header_without_http conf title =
  Output.print_sstring conf "<!DOCTYPE html><head><title>";
  title true;
  Output.print_sstring conf
    "</title><meta name=\"robots\" content=\"none\">";
  Output.print_sstring conf "<meta charset=\"" ;
  Output.print_sstring conf conf.charset ;
  Output.print_sstring conf "\">" ;
  Output.print_sstring conf {|<link rel="shortcut icon" href="|};
  Output.print_string conf (Image.prefix conf);
  Output.print_sstring conf {|/favicon_gwd.png">|};
  Output.print_sstring conf {|<link rel="apple-touch-icon" href="|};
  Output.print_string conf (Image.prefix conf);
  Output.print_sstring conf {|/favicon_gwd.png">|};
  Output.print_sstring conf
    {|<meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">|};
  Util.include_template conf [] "css" (fun () -> ());
  begin match Util.open_etc_file conf "hed" with
    Some (ic, _) -> Templ.copy_from_templ conf [] ic
  | None -> ()
  end;
  Output.print_sstring conf "\n</head>\n";
  let s =
    try " dir=\"" ^ Hashtbl.find conf.lexicon "!dir" ^ "\"" with
      Not_found -> ""
  in
  let s = s ^ Util.body_prop conf in
  Output.printf conf "<body%s>\n" s; Util.message_to_wizard conf

let header_without_page_title conf title =
  Util.html conf;
  header_without_http conf title;
  (* balancing </div> in gen_trailer *)
  Output.printf conf "<div class=\"container\">"

let header_link_welcome conf title =
  header_without_page_title conf title;
  print_link_to_welcome conf true;
  Output.print_sstring conf "<h1>";
  title false;
  Output.print_sstring conf "</h1>\n"

let header_no_page_title conf title =
  header_without_page_title conf title;
  match Util.p_getenv conf.env "title" with
    None | Some "" -> ()
  | Some x -> Output.printf conf "<h1>%s</h1>\n" x

let header conf title =
  header_without_page_title conf title;
  Output.print_sstring conf "\n<h1>";
  title false;
  Output.print_sstring conf "</h1>\n"

let header_fluid conf title =
  header_without_http conf title;
  (* balancing </div> in gen_trailer *)
  Output.print_sstring conf "<div class=\"container-fluid\">";
  Output.print_sstring conf "\n<h1>";
  title false;
  Output.print_sstring conf "</h1>\n"

let rheader conf title =
  header_without_page_title conf title;
  Output.print_sstring conf "<h1 class=\"error\">";
  title false;
  Output.print_sstring conf "</h1>\n"

let trailer conf =
  let conf = {conf with is_printed_by_template = false} in
  begin match Util.open_etc_file conf "trl" with
    Some (ic, _) -> Templ.copy_from_templ conf [] ic
  | None -> ()
  end;
  Templ.print_copyright conf;
  Util.include_template conf [] "js" (fun () -> ());
  Output.print_sstring conf "</body>\n</html>\n"

let () = GWPARAM.wrap_output := begin fun conf title content ->
    header conf (fun _ -> Output.print_string conf title) ;
    content () ;
    trailer conf ;
  end

let incorrect_request conf =
  !GWPARAM.output_error conf Def.Bad_Request

let error_cannot_access conf fname =
  !GWPARAM.output_error conf Def.Not_Found
    ~content:("Cannot access file \""
              ^<^ (Util.escape_html fname : Adef.escaped_string :> Adef.safe_string)
              ^>^ ".txt\".")

let gen_interp header conf fname ifun env ep =
  Templ_parser.wrap fname begin fun () ->
    match Templ.input_templ conf fname with
    | Some astl ->
      if header then Util.html conf;
      let full_name = Util.etc_file_name conf fname in
      Templ.interp_ast conf ifun env ep [ Ainclude (full_name, astl) ]
    | None -> error_cannot_access conf fname
  end

let interp_no_header conf fname ifun env ep =
  gen_interp false conf fname ifun env ep

let interp conf fname ifun env ep = gen_interp true conf fname ifun env ep

(* Calendar request *)

let eval_julian_day conf =
  let open Adef in
  let getint v =
    match Util.p_getint conf.env v with
      Some x -> x
    | _ -> 0
  in
  List.fold_left
    (fun d (var, cal, conv, max_month) ->
       let yy =
         match Util.p_getenv conf.env ("y" ^ var) with
           Some v ->
             begin try
               let len = String.length v in
               if cal = Djulian && len > 2 && v.[len-2] = '/' then
                 int_of_string (String.sub v 0 (len - 2)) + 1
               else int_of_string v
             with Failure _ -> 0
             end
         | None -> 0
       in
       let mm = getint ("m" ^ var) in
       let dd = getint ("d" ^ var) in
       let dt = {day = dd; month = mm; year = yy; prec = Sure; delta = 0} in
       match Util.p_getenv conf.env ("t" ^ var) with
         Some _ -> conv dt
       | None ->
           match
             Util.p_getenv conf.env ("y" ^ var ^ "1"),
             Util.p_getenv conf.env ("y" ^ var ^ "2"),
             Util.p_getenv conf.env ("m" ^ var ^ "1"),
             Util.p_getenv conf.env ("m" ^ var ^ "2"),
             Util.p_getenv conf.env ("d" ^ var ^ "1"),
             Util.p_getenv conf.env ("d" ^ var ^ "2")
           with
             Some _, _, _, _, _, _ -> conv {dt with year = yy - 1}
           | _, Some _, _, _, _, _ -> conv {dt with year = yy + 1}
           | _, _, Some _, _, _, _ ->
               let (yy, mm) =
                 if mm = 1 then yy - 1, max_month else yy, mm - 1
               in
               conv {dt with year = yy; month = mm}
           | _, _, _, Some _, _, _ ->
               let (yy, mm) =
                 if mm = max_month then yy + 1, 1 else yy, mm + 1
               in
               let r = conv {dt with year = yy; month = mm} in
               if r = conv dt then
                 let (yy, mm) =
                   if mm = max_month then yy + 1, 1 else yy, mm + 1
                 in
                 conv {dt with year = yy; month = mm}
               else r
           | _, _, _, _, Some _, _ -> conv {dt with day = dd - 1}
           | _, _, _, _, _, Some _ -> conv {dt with day = dd + 1}
           | _ -> d)
    (Calendar.sdn_of_gregorian conf.today)
    ["g", Dgregorian, Calendar.sdn_of_gregorian, 12;
     "j", Djulian, Calendar.sdn_of_julian, 12;
     "f", Dfrench, Calendar.sdn_of_french, 13;
     "h", Dhebrew, Calendar.sdn_of_hebrew, 13]

(* *)

type 'a env =
    Vint of int
  | Vother of 'a
  | Vnone

let get_env v env = try List.assoc v env with Not_found -> Vnone
let get_vother =
  function
    Vother x -> Some x
  | _ -> None
let set_vother x = Vother x

let eval_var conf env jd _loc =
  let open TemplAst in
  function
  | ["integer"] ->
      begin match get_env "integer" env with
        Vint i -> VVstring (string_of_int i)
      | _ -> raise Not_found
      end
  | "date" :: sl -> TemplDate.eval_date_var conf jd sl
  | "today" :: sl ->
      TemplDate.eval_date_var conf (Calendar.sdn_of_gregorian conf.today) sl
  | _ -> raise Not_found

let print_foreach print_ast eval_expr =
  let eval_int_expr env jd e =
    let s = eval_expr env jd e in
    try int_of_string s with Failure _ -> raise Not_found
  in
  let rec print_foreach env jd _loc s sl el al =
    match s, sl with
      "integer_range", [] -> print_integer_range env jd el al
    | _ -> raise Not_found
  and print_integer_range env jd el al =
    let (i1, i2) =
      match el with
        [[e1]; [e2]] -> eval_int_expr env jd e1, eval_int_expr env jd e2
      | _ -> raise Not_found
    in
    for i = i1 to i2 do
      let env = ("integer", Vint i) :: env in List.iter (print_ast env jd) al
    done
  in
  print_foreach

let print_calendar conf =
  interp conf "calendar"
    { Templ.eval_var = eval_var conf
    ; Templ.eval_transl = (fun _ -> Templ.eval_transl conf)
    ; Templ.eval_predefined_apply = (fun _ -> raise Not_found)
    ; Templ.get_vother = get_vother
    ; Templ.set_vother = set_vother
    ; Templ.print_foreach = print_foreach
    }
    [] (eval_julian_day conf)
