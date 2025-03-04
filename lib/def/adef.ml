(* $Id: adef.ml,v 5.6 2007-02-21 18:14:01 ddr Exp $ *)
(* Copyright (c) 1998-2007 INRIA *)

type fix = int

let float_of_fix x = float x /. 1000000.0
let fix_of_float x = truncate (x *. 1000000.0 +. 0.5)
external fix : int -> fix = "%identity"
external fix_repr : fix -> int = "%identity"

let no_consang = fix (-1)

type date =
    Dgreg of dmy * calendar
  | Dtext of string
and calendar = Dgregorian | Djulian | Dfrench | Dhebrew
and dmy =
  { day : int; month : int; year : int; prec : precision; delta : int }
and dmy2 = { day2 : int; month2 : int; year2 : int; delta2 : int }
and precision =
    Sure
  | About
  | Maybe
  | Before
  | After
  | OrYear of dmy2
  | YearInt of dmy2

type cdate =
    Cgregorian of int
  | Cjulian of int
  | Cfrench of int
  | Chebrew of int
  | Ctext of string
  | Cdate of date
  | Cnone

(* compress concrete date if it's possible *)
let compress d =
  let simple =
    match d.prec with
      Sure | About | Maybe | Before | After ->
        d.day >= 0 && d.month >= 0 && d.year > 0 && d.year < 2500 &&
        d.delta = 0
    | OrYear _ | YearInt _ -> false
  in
  if simple then
    let p =
      match d.prec with
        About -> 1
      | Maybe -> 2
      | Before -> 3
      | After -> 4
      | Sure | OrYear _ | YearInt _ -> 0
    in
    Some (((p * 32 + d.day) * 13 + d.month) * 2500 + d.year)
  else None

let cdate_of_date d =
  match d with
    Dgreg (g, cal) ->
      begin match compress g with
        Some i ->
          begin match cal with
            Dgregorian -> Cgregorian i
          | Djulian -> Cjulian i
          | Dfrench -> Cfrench i
          | Dhebrew -> Chebrew i
          end
      | None -> Cdate d
      end
  | Dtext t -> Ctext t

(* uncompress concrete date *)
let uncompress x =
  let (year, x) = x mod 2500, x / 2500 in
  let (month, x) = x mod 13, x / 13 in
  let (day, x) = x mod 32, x / 32 in
  let prec =
    match x with
      1 -> About
    | 2 -> Maybe
    | 3 -> Before
    | 4 -> After
    | _ -> Sure
  in
  {day = day; month = month; year = year; prec = prec; delta = 0}

let date_of_cdate =
  function
    Cgregorian i -> Dgreg (uncompress i, Dgregorian)
  | Cjulian i -> Dgreg (uncompress i, Djulian)
  | Cfrench i -> Dgreg (uncompress i, Dfrench)
  | Chebrew i -> Dgreg (uncompress i, Dhebrew)
  | Cdate d -> d
  | Ctext t -> Dtext t
  | Cnone -> failwith "date_of_cdate"

let cdate_of_od =
  function
    Some d -> cdate_of_date d
  | None -> Cnone

let od_of_cdate od =
  match od with
    Cnone -> None
  | _ -> Some (date_of_cdate od)

let cdate_None = cdate_of_od None

type 'person gen_couple = { father : 'person; mother : 'person }
and 'person gen_parents = { parent : 'person array }

let father cpl =
  if Obj.size (Obj.repr cpl) = 2 then cpl.father
  else (Obj.magic cpl).parent.(0)
let mother cpl =
  if Obj.size (Obj.repr cpl) = 2 then cpl.mother
  else (Obj.magic cpl).parent.(1)
let couple father mother = {father = father; mother = mother}
let parent parent = {father = parent.(0); mother = parent.(1)}
let parent_array cpl =
  if Obj.size (Obj.repr cpl) = 2 then [| cpl.father; cpl.mother |]
  else (Obj.magic cpl).parent

let multi_couple father mother : 'person gen_couple =
  Obj.magic {parent = [| father; mother |]}
let multi_parent parent : 'person gen_couple = Obj.magic {parent = parent}


type 'a astring = string

type safe_string = [`encoded|`escaped|`safe] astring

type escaped_string = [`encoded|`escaped] astring

type encoded_string = [`encoded] astring

let ( ^^^ ) : 'a astring -> 'a astring -> 'a astring =
  fun (a : 'a astring) (b : 'a astring) -> (a ^  b : 'a astring)

let ( ^>^ ) : 'a astring -> string -> 'a astring =
  fun (a : 'a astring) (b : string) -> ( ( a ^ b) : 'a astring)

let ( ^<^ ) : string -> 'a astring -> 'a astring =
  fun (a : string) (b : 'a astring) -> ( (a ^  b) : 'a astring)

let ( <^> ) : 'a astring -> 'a astring -> bool = ( <> )
                                     
external safe : string -> safe_string = "%identity"

external escaped : string -> escaped_string = "%identity"

external encoded : string -> encoded_string = "%identity"

external as_string : 'a astring -> string = "%identity"

let safe_fn = ( @@ )
