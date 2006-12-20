(* $Id: gwdb.ml,v 5.162 2006-12-20 19:21:31 ddr Exp $ *)
(* Copyright (c) 1998-2006 INRIA *)

open Adef;
open Config;
open Dbdisk;
open Def;
open Futil;
open Mutil;
open Printf;

value magic_patch = "GwPt0001";

type patches =
  { nb_per : mutable int;
    nb_fam : mutable int;
    nb_per_ini : int;
    nb_fam_ini : int;
    h_person : Hashtbl.t iper (gen_person iper string);
    h_ascend : Hashtbl.t iper (gen_ascend ifam);
    h_union : Hashtbl.t iper (gen_union ifam);
    h_family : Hashtbl.t ifam (gen_family iper string);
    h_couple : Hashtbl.t ifam (gen_couple iper);
    h_descend : Hashtbl.t ifam (gen_descend iper);
    h_key : Hashtbl.t (string * string * int) iper;
    h_name : Hashtbl.t string (list iper) }
;

type db2 =
  { phony : unit -> unit; (* to prevent usage of "=" in the program *)
    bdir : string;
    cache_chan : Hashtbl.t (string * string * string) in_channel;
    patches : patches;
    parents_array : mutable option (array (option ifam));
    consang_array : mutable option (array Adef.fix);
    family_array : mutable option (array (array ifam));
    father_array : mutable option (array iper);
    mother_array : mutable option (array iper);
    children_array : mutable option (array (array iper)) }
;

type istr =
  [ Istr of dsk_istr
  | Istr2 of db2 and (string * string) and int
  | Istr2New of db2 and string ]
;

type person =
  [ Person of dsk_person
  | Person2 of db2 and int
  | Person2Gen of db2 and gen_person iper string ]
;
type ascend =
  [ Ascend of dsk_ascend
  | Ascend2 of db2 and int
  | Ascend2Gen of db2 and gen_ascend ifam ]
;
type union =
  [ Union of dsk_union
  | Union2 of db2 and int
  | Union2Gen of db2 and gen_union ifam ]
;

type family =
  [ Family of dsk_family
  | Family2 of db2 and int
  | Family2Gen of db2 and gen_family iper string ]
;
type couple =
  [ Couple of dsk_couple
  | Couple2 of db2 and int
  | Couple2Gen of db2 and gen_couple iper ]
;
type descend =
  [ Descend of dsk_descend
  | Descend2 of db2 and int
  | Descend2Gen of db2 and gen_descend iper ]
;

type relation = Def.gen_relation iper istr;
type title = Def.gen_title istr;

type gen_string_person_index 'istr = Dbdisk.string_person_index 'istr ==
  { find : 'istr -> list iper;
    cursor : string -> 'istr;
    next : 'istr -> 'istr }
;

type string_person_index2 =
  { is_first_name : bool;
    index_of_first_char : list (string * int);
    ini : mutable string;
    curr : mutable int }
;

type string_person_index =
  [ Spi of gen_string_person_index dsk_istr
  | Spi2 of db2 and string_person_index2 ]
;

type base_t =
  [ Base of Dbdisk.dsk_base
  | Base2 of db2 ]
;

value fast_open_in_bin_and_seek db2 f1 f2 f pos = do {
  let ic =
    try Hashtbl.find db2.cache_chan (f1, f2, f) with
    [ Not_found -> do {
        let ic =
          open_in_bin
            (List.fold_left Filename.concat db2.bdir [f1; f2; f])
        in
        Hashtbl.add db2.cache_chan (f1, f2, f) ic;
        ic
      } ]
  in
  seek_in ic pos;
  ic
};

value get_field_acc db2 i (f1, f2) =
  let ic = fast_open_in_bin_and_seek db2 f1 f2 "access" (4 * i) in
  input_binary_int ic
;

value get_field_data db2 pos (f1, f2) data =
  let ic = fast_open_in_bin_and_seek db2 f1 f2 data pos in
  Iovalue.input ic
;

value get_field_2_data db2 pos (f1, f2) data =
  let ic = fast_open_in_bin_and_seek db2 f1 f2 data pos in
  let r = Iovalue.input ic in
  let s = Iovalue.input ic in
  (r, s)
;

value get_field db2 i path =
  let pos = get_field_acc db2 i path in
  get_field_data db2 pos path "data"
;

value string_of_istr2 db2 f pos =
  if pos = -1 || pos = Db2.empty_string_pos then ""
  else get_field_data db2 pos f "data"
;

value eq_istr i1 i2 =
  match (i1, i2) with
  [ (Istr i1, Istr i2) -> Adef.int_of_istr i1 = Adef.int_of_istr i2
  | (Istr2 _ (f11, f12) i1, Istr2 _ (f21, f22) i2) ->
      i1 = i2 && f11 = f21 && f12 = f22
  | (Istr2New _ s1, Istr2New _ s2) -> s1 = s2
  | (Istr2 db2 f pos, Istr2New _ s2) -> False (*string_of_istr2 db2 f pos = s2*)
  | (Istr2New _ s1, Istr2 db2 f pos) -> False (*s1 = string_of_istr2 db2 f pos*)
  | _ -> failwith "eq_istr" ]
;

value make_istr2 db2 path i = Istr2 db2 path (get_field_acc db2 i path);

value is_empty_string =
  fun
  [ Istr istr -> Adef.int_of_istr istr = 0
  | Istr2 db2 path pos -> pos = Db2.empty_string_pos
  | Istr2New db2 s -> s = "" ]
;
value is_quest_string =
  fun
  [ Istr istr -> Adef.int_of_istr istr = 1
  | Istr2 db2 path pos -> failwith "not impl is_quest_string"
  | Istr2New db2 s -> s = "?" ]
;

value get_access =
  fun
  [ Person p -> p.Def.access
  | Person2 db2 i -> get_field db2 i ("person", "access")
  | Person2Gen db2 p -> p.Def.access ]
;
value get_aliases =
  fun
  [ Person p -> List.map (fun i -> Istr i) p.Def.aliases
  | Person2 db2 i ->
      let pos = get_field_acc db2 i ("person", "aliases") in
      if pos = -1 then []
      else
        let list = get_field_data db2 pos ("person", "aliases") "data2.ext" in
        List.map (fun pos -> Istr2 db2 ("person", "aliases") pos) list
  | Person2Gen db2 p -> List.map (fun s -> Istr2New db2 s) p.Def.aliases ]
;
value get_baptism =
  fun
  [ Person p -> p.Def.baptism
  | Person2 db2 i -> get_field db2 i ("person", "baptism")
  | Person2Gen db2 p -> p.Def.baptism ]
;
value get_baptism_place =
  fun
  [ Person p -> Istr p.Def.baptism_place
  | Person2 db2 i -> make_istr2 db2 ("person", "baptism_place") i
  | Person2Gen db2 p -> Istr2New db2 p.Def.baptism_place ]
;
value get_baptism_src =
  fun
  [ Person p -> Istr p.Def.baptism_src
  | Person2 db2 i -> make_istr2 db2 ("person", "baptism_src") i
  | Person2Gen db2 p -> Istr2New db2 p.Def.baptism_src ]
;
value get_birth =
  fun
  [ Person p -> p.Def.birth
  | Person2 db2 i -> get_field db2 i ("person", "birth")
  | Person2Gen db2 p -> p.Def.birth ]
;
value get_birth_place =
  fun
  [ Person p -> Istr p.Def.birth_place
  | Person2 db2 i -> make_istr2 db2 ("person", "birth_place") i
  | Person2Gen db2 p -> Istr2New db2 p.Def.birth_place ]
;
value get_birth_src =
  fun
  [ Person p -> Istr p.Def.birth_src
  | Person2 db2 i -> make_istr2 db2 ("person", "birth_src") i
  | Person2Gen db2 p -> Istr2New db2 p.Def.birth_src ]
;
value get_burial =
  fun
  [ Person p -> p.Def.burial
  | Person2 db2 i -> get_field db2 i ("person", "burial")
  | Person2Gen db2 p -> p.Def.burial ]
;
value get_burial_place =
  fun
  [ Person p -> Istr p.Def.burial_place
  | Person2 db2 i -> make_istr2 db2 ("person", "burial_place") i
  | Person2Gen db2 p -> Istr2New db2 p.Def.burial_place ]
;
value get_burial_src =
  fun
  [ Person p -> Istr p.Def.burial_src
  | Person2 db2 i -> make_istr2 db2 ("person", "burial_src") i
  | Person2Gen db2 p -> Istr2New db2 p.Def.burial_src ]
;
value get_death =
  fun
  [ Person p -> p.Def.death
  | Person2 db2 i -> get_field db2 i ("person", "death")
  | Person2Gen db2 p -> p.Def.death ]
;
value get_death_place =
  fun
  [ Person p -> Istr p.Def.death_place
  | Person2 db2 i -> make_istr2 db2 ("person", "death_place") i
  | Person2Gen db2 p -> Istr2New db2 p.Def.death_place ]
;
value get_death_src =
  fun
  [ Person p -> Istr p.Def.death_src
  | Person2 db2 i -> make_istr2 db2 ("person", "death_src") i
  | Person2Gen db2 p -> Istr2New db2 p.Def.death_src ]
;
value get_first_name =
  fun
  [ Person p -> Istr p.Def.first_name
  | Person2 db2 i -> make_istr2 db2 ("person", "first_name") i
  | Person2Gen db2 p -> Istr2New db2 p.Def.first_name ]
;
value get_first_names_aliases =
  fun
  [ Person p -> List.map (fun i -> Istr i) p.Def.first_names_aliases
  | Person2 db2 i ->
      let pos = get_field_acc db2 i ("person", "first_names_aliases") in
      if pos = -1 then []
      else
        let list =
          get_field_data db2 pos ("person", "first_names_aliases") "data2.ext"
        in
        List.map (fun pos -> Istr2 db2 ("person", "first_names_aliases") pos)
          list
  | Person2Gen db2 p ->
      List.map (fun s -> Istr2New db2 s) p.Def.first_names_aliases ]
;
value get_image =
  fun
  [ Person p -> Istr p.Def.image
  | Person2 db2 i -> make_istr2 db2 ("person", "image") i
  | Person2Gen db2 p -> Istr2New db2 p.Def.image ]
;
value get_key_index =
  fun
  [ Person p -> p.Def.key_index
  | Person2 _ i -> Adef.iper_of_int i
  | Person2Gen db2 p -> p.Def.key_index ]
;
value get_notes =
  fun
  [ Person p -> Istr p.Def.notes
  | Person2 db2 i -> make_istr2 db2 ("person", "notes") i
  | Person2Gen db2 p -> Istr2New db2 p.Def.notes ]
;
value get_occ =
  fun
  [ Person p -> p.Def.occ
  | Person2 db2 i -> get_field db2 i ("person", "occ")
  | Person2Gen db2 p -> p.Def.occ ]
;
value get_occupation =
  fun
  [ Person p -> Istr p.Def.occupation
  | Person2 db2 i -> make_istr2 db2 ("person", "occupation") i
  | Person2Gen db2 p -> Istr2New db2 p.Def.occupation ]
;
value get_psources =
  fun
  [ Person p -> Istr p.Def.psources
  | Person2 db2 i -> make_istr2 db2 ("person", "psources") i
  | Person2Gen db2 p -> Istr2New db2 p.Def.psources ]
;
value get_public_name =
  fun
  [ Person p -> Istr p.Def.public_name
  | Person2 db2 i -> make_istr2 db2 ("person", "public_name") i
  | Person2Gen db2 p -> Istr2New db2 p.Def.public_name ]
;
value get_qualifiers =
  fun
  [ Person p -> List.map (fun i -> Istr i) p.Def.qualifiers
  | Person2 db2 i ->
      let pos = get_field_acc db2 i ("person", "qualifiers") in
      if pos = -1 then []
      else
        let list =
          get_field_data db2 pos ("person", "qualifiers") "data2.ext"
        in
        List.map (fun pos -> Istr2 db2 ("person", "qualifiers") pos) list
  | Person2Gen db2 p -> List.map (fun s -> Istr2New db2 s) p.Def.qualifiers ]
;
value get_related =
  fun
  [ Person p -> p.Def.related
  | Person2 db2 i ->
      let pos = get_field_acc db2 i ("person", "related") in
      loop [] pos where rec loop list pos =
        if pos = -1 then List.rev list
        else
          let (ip, pos) =
            get_field_2_data db2 pos ("person", "related") "data"
          in
          loop [ip :: list] pos
  | Person2Gen db2 p -> p.Def.related ]
;
value get_rparents =
  fun
  [ Person p ->
      List.map (map_relation_ps (fun x -> x) (fun i -> Istr i)) p.Def.rparents
  | Person2 db2 i ->
      let pos = get_field_acc db2 i ("person", "rparents") in
      if pos = -1 then []
      else
        let rl = get_field_data db2 pos ("person", "rparents") "data" in
        List.map (* field "r_sources" is actually unused *)
          (map_relation_ps (fun x -> x) (fun _ -> Istr2 db2 ("", "") (-1)))
          rl
  | Person2Gen db2 p ->
      List.map (map_relation_ps (fun x -> x) (fun s -> Istr2New db2 s))
        p.Def.rparents ]
;
value get_sex =
  fun
  [ Person p -> p.Def.sex
  | Person2 db2 i -> get_field db2 i ("person", "sex")
  | Person2Gen db2 p -> p.Def.sex ]
;
value get_surname =
  fun
  [ Person p -> Istr p.Def.surname
  | Person2 db2 i -> make_istr2 db2 ("person", "surname") i
  | Person2Gen db2 p -> Istr2New db2 p.Def.surname ]
;
value get_surnames_aliases =
  fun
  [ Person p -> List.map (fun i -> Istr i) p.Def.surnames_aliases
  | Person2 db2 i ->
      let pos = get_field_acc db2 i ("person", "surnames_aliases") in
      if pos = -1 then []
      else
        let list =
          get_field_data db2 pos ("person", "surnames_aliases") "data2.ext"
        in
        List.map
          (fun pos -> Istr2 db2 ("person", "surnames_aliases") pos) list
  | Person2Gen db2 p ->
      List.map (fun s -> Istr2New db2 s) p.Def.surnames_aliases ]
;
value get_titles =
  fun
  [ Person p ->
      List.map (fun t -> map_title_strings (fun i -> Istr i) t)
        p.Def.titles
  | Person2 db2 i ->
      let pos = get_field_acc db2 i ("person", "titles") in
      if pos = -1 then []
      else
        let list =
          get_field_data db2 pos ("person", "titles") "data2.ext"
        in
        List.map
          (map_title_strings (fun pos -> Istr2 db2 ("person", "titles") pos))
          list
  | Person2Gen db2 p ->
      List.map (fun t -> map_title_strings (fun s -> Istr2New db2 s) t)
        p.Def.titles ]
;

value person_with_related p r =
  match p with
  [ Person p -> Person {(p) with related = r}
  | Person2 _ _ -> failwith "not impl person_with_related"
  | Person2Gen _ _ -> failwith "not impl person_with_related (gen)" ]
;

value un_istr =
  fun
  [ Istr i -> i
  | Istr2 _ _ i -> failwith "un_istr"
  | Istr2New _ _ -> failwith "un_istr" ]
;

value un_istr2 =
  fun
  [ Istr _ -> failwith "un_istr2 1"
  | Istr2 _ _ _ -> failwith "un_istr2 2"
  | Istr2New _ s -> s ]
;

value person_with_rparents p r =
  match p with
  [ Person p ->
      let r = List.map (map_relation_ps (fun p -> p) un_istr) r in
      Person {(p) with rparents = r}
  | Person2 _ _ -> failwith "not impl person_with_rparents"
  | Person2Gen _ _ -> failwith "not impl person_with_rparents (gen)" ]
;
value person_with_sex p s =
  match p with
  [ Person p -> Person {(p) with sex = s}
  | Person2 _ _ -> failwith "not impl person_with_sex"
  | Person2Gen db2 p -> Person2Gen db2 {(p) with sex = s} ]
;

(*
value person_of_gen_person base p =
  match base with
  [ Base _ -> Person (map_person_ps (fun p -> p) un_istr p)
  | Base2 db2 -> Person2Gen db2 (map_person_ps (fun p -> p) un_istr2 p) ]
;
*)

value gen_person_of_person =
  fun
  [ Person p -> map_person_ps (fun p -> p) (fun s -> Istr s) p
  | Person2 _ _ as p ->
      {first_name = get_first_name p; surname = get_surname p;
       occ = get_occ p; image = get_image p; public_name = get_public_name p;
       qualifiers = get_qualifiers p; aliases = get_aliases p;
       first_names_aliases = get_first_names_aliases p;
       surnames_aliases = get_surnames_aliases p; titles = get_titles p;
       rparents = get_rparents p; related = get_related p;
       occupation = get_occupation p; sex = get_sex p; access = get_access p;
       birth = get_birth p; birth_place = get_birth_place p;
       birth_src = get_birth_src p; baptism = get_baptism p;
       baptism_place = get_baptism_place p; baptism_src = get_baptism_src p;
       death = get_death p; death_place = get_death_place p;
       death_src = get_death_src p; burial = get_burial p;
       burial_place = get_burial_place p; burial_src = get_burial_src p;
       notes = get_notes p; psources = get_psources p;
       key_index = get_key_index p}
  | Person2Gen db2 p ->
      map_person_ps (fun p -> p) (fun s -> Istr2New db2 s) p ]
;

value no_consang = Adef.fix (-1);

value get_consang =
  fun
  [ Ascend a -> a.Def.consang
  | Ascend2 db2 i ->
      match db2.consang_array with
      [ Some tab -> tab.(i)
      | None ->
          try get_field db2 i ("person", "consang") with
          [ Sys_error _ -> no_consang ] ]
  | Ascend2Gen _ a -> a.Def.consang ]
;

value get_parents =
  fun
  [ Ascend a -> a.Def.parents
  | Ascend2 db2 i ->
      match db2.parents_array with
      [ Some tab -> tab.(i)
      | None ->
          let pos = get_field_acc db2 i ("person", "parents") in
          if pos = -1 then None
          else Some (get_field_data db2 pos ("person", "parents") "data") ]
  | Ascend2Gen _ a -> a.Def.parents ]
;

(*
value ascend_of_gen_ascend base a =
  match base with
  [ Base _ -> Ascend a
  | Base2 db2 -> Ascend2Gen db2 a ]
;
*)

value empty_person ip =
  let empty_string = Adef.istr_of_int 0 in
  let p =
    {first_name = empty_string; surname = empty_string; occ = 0;
     image = empty_string; first_names_aliases = []; surnames_aliases = [];
     public_name = empty_string; qualifiers = []; titles = []; rparents = [];
     related = []; aliases = []; occupation = empty_string; sex = Neuter;
     access = Private; birth = Adef.codate_None; birth_place = empty_string;
     birth_src = empty_string; baptism = Adef.codate_None;
     baptism_place = empty_string; baptism_src = empty_string;
     death = DontKnowIfDead; death_place = empty_string;
     death_src = empty_string; burial = UnknownBurial;
     burial_place = empty_string; burial_src = empty_string;
     notes = empty_string; psources = empty_string; key_index = ip}
  in
  Person p
;

value get_family =
  fun
  [ Union u -> u.Def.family
  | Union2 db2 i ->
      match db2.family_array with
      [ Some tab -> tab.(i)
      | None -> get_field db2 i ("person", "family") ]
  | Union2Gen db2 u -> u.Def.family ]
;

(*
value union_of_gen_union base u =
  match base with
  [ Base _ -> Union u
  | Base2 db2 -> Union2Gen db2 u ]
;
*)

value gen_union_of_union =
  fun
  [ Union u -> u
  | Union2 _ _ as u -> {family = get_family u}
  | Union2Gen db2 u -> u ]
;

value get_comment =
  fun
  [ Family f -> Istr f.Def.comment
  | Family2 db2 i -> make_istr2 db2 ("family", "comment") i
  | Family2Gen db2 f -> Istr2New db2 f.Def.comment ]
;
value get_divorce =
  fun
  [ Family f -> f.Def.divorce
  | Family2 db2 i -> get_field db2 i ("family", "divorce")
  | Family2Gen db2 f -> f.Def.divorce ]
;

value get_fsources =
  fun
  [ Family f -> Istr f.Def.fsources
  | Family2 db2 i -> make_istr2 db2 ("family", "fsources") i
  | Family2Gen db2 f -> Istr2New db2 f.Def.fsources ]
;
value get_marriage =
  fun
  [ Family f -> f.Def.marriage
  | Family2 db2 i -> get_field db2 i ("family", "marriage")
  | Family2Gen db2 f -> f.Def.marriage ]
;
value get_marriage_place =
  fun
  [ Family f -> Istr f.Def.marriage_place
  | Family2 db2 i -> make_istr2 db2 ("family", "marriage_place") i
  | Family2Gen db2 f -> Istr2New db2 f.Def.marriage_place ]
;
value get_marriage_src =
  fun
  [ Family f -> Istr f.Def.marriage_src
  | Family2 db2 i -> make_istr2 db2 ("family", "marriage_src") i
  | Family2Gen db2 f -> Istr2New db2 f.Def.marriage_src ]
;
value get_origin_file =
  fun
  [ Family f -> Istr f.Def.origin_file
  | Family2 db2 i -> make_istr2 db2 ("family", "origin_file") i
  | Family2Gen db2 f -> Istr2New db2 f.Def.origin_file ]
;
value get_relation =
  fun
  [ Family f -> f.Def.relation
  | Family2 db2 i -> get_field db2 i ("family", "relation")
  | Family2Gen db2 f -> f.Def.relation ]
;
value get_witnesses =
  fun
  [ Family f -> f.Def.witnesses
  | Family2 db2 i -> get_field db2 i ("family", "witnesses")
  | Family2Gen db2 f -> f.Def.witnesses ]
;

value family_with_origin_file f orf fi =
  match (f, orf) with
  [ (Family f, Istr orf) ->
      Family {(f) with origin_file = orf; fam_index = fi}
  | (Family2Gen db2 f, Istr2 _ path pos) ->
      let orf =
        if pos = -1 || pos = Db2.empty_string_pos then ""
        else get_field_data db2 pos path "data"
      in
      Family2Gen db2 {(f) with origin_file = orf; fam_index = fi}
  | (Family2Gen db2 f, Istr2New _ orf) ->
      Family2Gen db2 {(f) with origin_file = orf; fam_index = fi}
  | _ -> assert False ]
;

(*
value family_of_gen_family base f =
  match base with
  [ Base _ -> Family (map_family_ps (fun p -> p) un_istr f)
  | Base2 db2 -> Family2Gen db2 (map_family_ps (fun p -> p) un_istr2 f) ]
;
*)

value gen_family_of_family =
  fun
  [ Family f -> map_family_ps (fun p -> p) (fun s -> Istr s) f
  | Family2 _ i as f ->
      {marriage = get_marriage f; marriage_place = get_marriage_place f;
       marriage_src = get_marriage_src f; witnesses = get_witnesses f;
       relation = get_relation f; divorce = get_divorce f;
       comment = get_comment f; origin_file = get_origin_file f;
       fsources = get_fsources f; fam_index = Adef.ifam_of_int i}
  | Family2Gen db2 f ->
      map_family_ps (fun p -> p) (fun s -> Istr2New db2 s) f ]
;

value get_father =
  fun
  [ Couple c -> Adef.father c
  | Couple2 db2 i ->
      match db2.father_array with
      [ Some tab -> tab.(i)
      | None -> get_field db2 i ("family", "father") ]
  | Couple2Gen db2 c -> Adef.father c ]
;

value get_mother =
  fun
  [ Couple c -> Adef.mother c
  | Couple2 db2 i ->
      match db2.mother_array with
      [ Some tab -> tab.(i)
      | None -> get_field db2 i ("family", "mother") ]
  | Couple2Gen db2 c -> Adef.mother c ]
;

value get_parent_array =
  fun
  [ Couple c -> Adef.parent_array c
  | Couple2 db2 i ->
      let p1 = get_field db2 i ("family", "father") in
      let p2 = get_field db2 i ("family", "mother") in
      [| p1; p2 |]
  | Couple2Gen db2 c -> Adef.parent_array c ]
;

(*
value couple_of_gen_couple base c =
  match base with
  [ Base _ -> Couple c
  | Base2 db2 -> Couple2Gen db2 c ]
;
*)

value gen_couple_of_couple =
  fun
  [ Couple c -> c
  | Couple2 _ _ as c -> couple (get_father c) (get_mother c)
  | Couple2Gen db2 c -> c ]
;

value get_children =
  fun
  [ Descend d -> d.Def.children
  | Descend2 db2 i ->
      match db2.children_array with
      [ Some tab -> tab.(i)
      | None -> get_field db2 i ("family", "children") ]
  | Descend2Gen db2 d -> d.Def.children ]
;

(*
value descend_of_gen_descend base d =
  match base with
  [ Base _ -> Descend d
  | Base2 db2 -> Descend2Gen db2 d ]
;
*)

value gen_descend_of_descend =
  fun
  [ Descend d -> d
  | Descend2 _ _ as d -> {children = get_children d}
  | Descend2Gen db2 d -> d ]
;

(*
value poi base i =
  match base with
  [ Base base -> Person (base.data.persons.get (Adef.int_of_iper i))
  | Base2 db2 ->
      try Person2Gen db2 (Hashtbl.find db2.patches.h_person i) with
      [ Not_found -> Person2 db2 (Adef.int_of_iper i) ] ]
;

value aoi base i =
  match base with
  [ Base base -> Ascend (base.data.ascends.get (Adef.int_of_iper i))
  | Base2 db2 ->
      try Ascend2Gen db2 (Hashtbl.find db2.patches.h_ascend i) with
      [ Not_found -> Ascend2 db2 (Adef.int_of_iper i) ] ]
;

value uoi base i =
  match base with
  [ Base base -> Union (base.data.unions.get (Adef.int_of_iper i))
  | Base2 db2 ->
      try Union2Gen db2 (Hashtbl.find db2.patches.h_union i) with
      [ Not_found -> Union2 db2 (Adef.int_of_iper i) ] ]
;

value foi base i =
  match base with
  [ Base base -> Family (base.data.families.get (Adef.int_of_ifam i))
  | Base2 db2 ->
      try Family2Gen db2 (Hashtbl.find db2.patches.h_family i) with
      [ Not_found -> Family2 db2 (Adef.int_of_ifam i) ] ]
;

value coi base i =
  match base with
  [ Base base -> Couple (base.data.couples.get (Adef.int_of_ifam i))
  | Base2 db2 ->
      try Couple2Gen db2 (Hashtbl.find db2.patches.h_couple i) with
      [ Not_found -> Couple2 db2 (Adef.int_of_ifam i) ] ]
;

value doi base i =
  match base with
  [ Base base -> Descend (base.data.descends.get (Adef.int_of_ifam i))
  | Base2 db2 ->
      try Descend2Gen db2 (Hashtbl.find db2.patches.h_descend i) with
      [ Not_found -> Descend2 db2 (Adef.int_of_ifam i) ] ]
;
*)

value sou base i =
  match (base, i) with
  [ (Base base, Istr i) -> base.data.strings.get (Adef.int_of_istr i)
  | (Base2 _, Istr2 db2 f pos) -> string_of_istr2 db2 f pos
  | (Base2 _, Istr2New db2 s) -> s
  | _ -> assert False ]
;

value person_with_key p fn sn oc =
  match (p, fn, sn) with
  [ (Person p, Istr fn, Istr sn) ->
      Person {(p) with first_name = fn; surname = sn; occ = oc}
  | (Person2 db2 i, Istr2 _ (f1, f2) ifn, Istr2 _ (f3, f4) isn) ->
      failwith "not impl person_with_key 1"
  | (Person2Gen db2 p, Istr2New _ fn, Istr2New _ sn) ->
      Person2Gen db2 {(p) with first_name = fn; surname = sn; occ = oc}
  | (Person2 db2 i,  Istr2New _ fn, Istr2New _ sn) ->
      let p = gen_person_of_person (Person2 db2 i) in
      let p = map_person_ps (fun ip -> ip) (sou (Base2 db2)) p in
      Person2Gen db2 {(p) with first_name = fn; surname = sn; occ = oc}
  | _ -> failwith "not impl person_with_key 2" ]
;

(*
value nb_of_persons base =
  match base with
  [ Base base -> base.data.persons.len
  | Base2 db2 -> db2.patches.nb_per ]
;

value nb_of_families base =
  match base with
  [ Base base -> base.data.families.len
  | Base2 db2 -> db2.patches.nb_fam ]
;

value patch_person base ip p =
  match (base, p) with
  [ (Base base, Person p) -> base.func.patch_person ip p
  | (Base2 _, Person2Gen db2 p) -> do {
      Hashtbl.replace db2.patches.h_person ip p;
      db2.patches.nb_per := max (Adef.int_of_iper ip + 1) db2.patches.nb_per;
    }
  | _ -> assert False ]
;

value patch_ascend base ip a =
  match (base, a) with
  [ (Base base, Ascend a) -> base.func.patch_ascend ip a
  | (Base2 _, Ascend2Gen db2 a) -> do {
      Hashtbl.replace db2.patches.h_ascend ip a;
      db2.patches.nb_per := max (Adef.int_of_iper ip + 1) db2.patches.nb_per;
    }
  | _ -> assert False ]
;

value patch_union base ip u =
  match (base, u) with
  [ (Base base, Union u) -> base.func.patch_union ip u
  | (Base2 _, Union2Gen db2 u) -> do {
      Hashtbl.replace db2.patches.h_union ip u;
      db2.patches.nb_per := max (Adef.int_of_iper ip + 1) db2.patches.nb_per;
    }
  | _ -> failwith "not impl patch_union" ]
;

value patch_family base ifam f =
  match (base, f) with
  [ (Base base, Family f) -> base.func.patch_family ifam f
  | (Base2 _, Family2Gen db2 f) -> do {
      Hashtbl.replace db2.patches.h_family ifam f;
      db2.patches.nb_fam :=
        max (Adef.int_of_ifam ifam + 1) db2.patches.nb_fam;
    }
  | _ -> failwith "not impl patch_family" ]
;

value patch_descend base ifam d =
  match (base, d) with
  [ (Base base, Descend d) -> base.func.patch_descend ifam d
  | (Base2 _, Descend2Gen db2 d) -> do {
      Hashtbl.replace db2.patches.h_descend ifam d;
      db2.patches.nb_fam :=
        max (Adef.int_of_ifam ifam + 1) db2.patches.nb_fam;
    }
  | _ -> failwith "not impl patch_descend" ]
;

value patch_couple base ifam c =
  match (base, c) with
  [ (Base base, Couple c) -> base.func.patch_couple ifam c
  | (Base2 _, Couple2Gen db2 c) -> do {
      Hashtbl.replace db2.patches.h_couple ifam c;
      db2.patches.nb_fam :=
        max (Adef.int_of_ifam ifam + 1) db2.patches.nb_fam;
    }
  | _ -> failwith "not impl patch_couple" ]
;

value patch_name base s ip =
  match base with
  [ Base base -> base.func.patch_name s ip
  | Base2 db2 ->
      let s = Name.crush_lower s in
      let ht = db2.patches.h_name in
      try
        let ipl = Hashtbl.find ht s in
        if List.mem ip ipl then () else Hashtbl.replace ht s [ip :: ipl]
      with
      [ Not_found -> Hashtbl.add ht s [ip] ] ]

;

value patch_key base ip fn sn occ =
  match base with
  [ Base _ -> ()
  | Base2 db2 -> do {
      Hashtbl.iter
        (fun key ip1 ->
           if ip = ip1 then Hashtbl.remove db2.patches.h_key key else ())
        db2.patches.h_key;
      let fn = Name.lower (nominative fn) in
      let sn = Name.lower (nominative sn) in
      Hashtbl.replace db2.patches.h_key (fn, sn, occ) ip
    }]
;

value insert_string base s =
  match base with
  [ Base base -> Istr (base.func.insert_string s)
  | Base2 db2 -> Istr2New db2 s ]
;

value delete_family base ifam = do {
  let cpl =
    couple_of_gen_couple base
      (couple (Adef.iper_of_int (-1)) (Adef.iper_of_int (-1)))
  in
  let fam =
    let empty = insert_string base "" in
    family_of_gen_family base
      {marriage = codate_None; marriage_place = empty; marriage_src = empty;
       relation = Married; divorce = NotDivorced; witnesses = [| |];
       comment = empty; origin_file = empty; fsources = empty;
       fam_index = Adef.ifam_of_int (-1)}
  in
  let des = descend_of_gen_descend base {children = [| |]} in
  patch_family base ifam fam;
  patch_couple base ifam cpl;
  patch_descend base ifam des
};
*)

value is_deleted_family =
  fun
  [ Family f -> f.Def.fam_index = Adef.ifam_of_int (-1)
  | Family2 _ i -> False (* not yet implemented *)
  | Family2Gen db2 f -> f.Def.fam_index = Adef.ifam_of_int (-1) ]
;

(*
value commit_patches base =
  match base with
  [ Base base -> base.func.commit_patches ()
  | Base2 db2 -> do {
      let fname = Filename.concat db2.bdir "patches" in
      let oc = open_out_bin (fname ^ "1") in
      output_string oc magic_patch;
      output_value oc db2.patches;
      close_out oc;
      remove_file (fname ^ "~");
      try Sys.rename fname (fname ^ "~") with [ Sys_error _ -> () ];
      Sys.rename (fname ^ "1") fname
    } ]
;

value commit_notes base =
  match base with
  [ Base base -> base.func.commit_notes
  | Base2 _ -> failwith "not impl commit_notes" ]
;
*)

value ok_I_know = ref False;
(*
value is_patched_person base ip =
  match base with
  [ Base base -> base.func.is_patched_person ip
  | Base2 _ ->
      let _ =
        if ok_I_know.val then ()
        else do {
          ok_I_know.val := True;
          eprintf "not impl is_patched_person\n";
          flush stderr;
        }
      in
      False ]
;

value patched_ascends base =
  match base with
  [ Base base -> base.func.patched_ascends ()
  | Base2 _ ->
      let _ = do { eprintf "not impl patched_ascends\n"; flush stderr; } in
      [] ]
;
*)

type key =
  [ Key of Adef.istr and Adef.istr and int
  | Key0 of Adef.istr and Adef.istr (* to save memory space *) ]
;

type bucketlist 'a 'b =
  [ Empty
  | Cons of 'a and 'b and bucketlist 'a 'b ]
;

value rec hashtbl_find_rec key =
  fun
  [ Empty -> raise Not_found
  | Cons k d rest ->
      if compare key k = 0 then d else hashtbl_find_rec key rest ]
;

value hashtbl_find dir file key = do {
  let ic_ht = open_in_bin (Filename.concat dir file) in
  let ic_hta = open_in_bin (Filename.concat dir (file ^ "a")) in
  let alen = input_binary_int ic_hta in
  let pos = int_size + (Hashtbl.hash key) mod alen * int_size in
  seek_in ic_hta pos;
  let pos = input_binary_int ic_hta in
  close_in ic_hta;
  seek_in ic_ht pos;
  let bl : bucketlist _ _ = Iovalue.input ic_ht in
  close_in ic_ht;
  hashtbl_find_rec key bl
};

value hashtbl_find_all dir file key = do {
  let rec find_in_bucket =
    fun
    [ Empty -> []
    | Cons k d rest ->
        if compare k key = 0 then [d :: find_in_bucket rest]
        else find_in_bucket rest ]
  in
  let ic_ht = open_in_bin (Filename.concat dir file) in
  let ic_hta = open_in_bin (Filename.concat dir (file ^ "a")) in
  let alen = input_binary_int ic_hta in
  let pos = int_size + (Hashtbl.hash key) mod alen * int_size in
  seek_in ic_hta pos;
  let pos = input_binary_int ic_hta in
  close_in ic_hta;
  seek_in ic_ht pos;
  let bl : bucketlist _ _ = Iovalue.input ic_ht in
  close_in ic_ht;
  find_in_bucket bl
};

value key_hashtbl_find dir file (fn, sn, oc) =
  let key = if oc = 0 then Key0 fn sn else Key fn sn oc in
  hashtbl_find dir file key
;

value person2_of_key db2 fn sn oc =
  let fn = Name.lower (nominative fn) in
  let sn = Name.lower (nominative sn) in
  try Some (Hashtbl.find db2.patches.h_key (fn, sn, oc)) with
  [ Not_found ->
      let person_of_key_d = Filename.concat db2.bdir "person_of_key" in
      try do {
        let ifn = hashtbl_find person_of_key_d "istr_of_string.ht" fn in
        let isn = hashtbl_find person_of_key_d "istr_of_string.ht" sn in
        let key = (ifn, isn, oc) in
        Some (key_hashtbl_find person_of_key_d "iper_of_key.ht" key : iper)
      }
      with
      [ Not_found -> None ] ]
;

value strings2_of_fsname db2 f s =
  let k = Name.crush_lower s in
  let dir = List.fold_left Filename.concat db2.bdir ["person"; f] in
  hashtbl_find_all dir "string_of_crush.ht" k
;

value persons2_of_name db2 s =
  let s = Name.crush_lower s in
  let dir = Filename.concat db2.bdir "person_of_name" in
  List.rev_append
    (try Hashtbl.find db2.patches.h_name s with [ Not_found -> [] ])
    (hashtbl_find_all dir "person_of_name.ht" s)
;

(*
value person_of_key base =
  match base with
  [ Base base -> base.func.person_of_key
  | Base2 db2 -> person2_of_key db2 ]
;
value persons_of_name base =
  match base with
  [ Base base -> base.func.persons_of_name
  | Base2 db2 -> persons2_of_name db2 ]
;

value base_particles base =
  match base with
  [ Base base -> base.data.particles
  | Base2 db2 ->
      Mutil.input_particles (Filename.concat db2.bdir "particles.txt") ]
;
*)

value start_with s p =
  String.length p < String.length s &&
  String.sub s 0 (String.length p) = p
;

value persons_of_first_name_or_surname2 db2 is_first_name = do {
  let f1 = "person" in
  let f2 = if is_first_name then "first_name" else "surname" in
  let fdir = List.fold_left Filename.concat db2.bdir [f1; f2] in
  let index_ini_fname = Filename.concat fdir "index.ini" in
  let ic = open_in_bin index_ini_fname in
  let iofc : list (string * int) = input_value ic in
  close_in ic;
  Spi2 db2
    {is_first_name = is_first_name; index_of_first_char = iofc; ini = "";
     curr = 0}
};

(*
value persons_of_first_name base =
  match base with
  [ Base base -> Spi base.func.persons_of_first_name
  | Base2 db2 -> persons_of_first_name_or_surname2 db2 True ]
;

value persons_of_surname base =
  match base with
  [ Base base -> Spi base.func.persons_of_surname
  | Base2 db2 -> persons_of_first_name_or_surname2 db2 False ]
;
*)

value spi_first spi s =
  match spi with
  [ Spi spi -> Istr (spi.cursor s)
  | Spi2 db2 spi -> do {
      let i =
        (* to be faster, go directly to the first string starting with
           the same char *)
        if s = "" then 0
        else
          let nbc = Name.nbc s.[0] in
          loop spi.index_of_first_char where rec loop =
            fun
            [ [(s1, i1) :: list] ->
                if s1 = "" then loop list
                else
                  let nbc1 = Name.nbc s1.[0] in
                  if nbc = nbc1 && nbc > 0 && nbc <= String.length s &&
                     nbc <= String.length s1 &&
                     String.sub s 0 nbc = String.sub s1 0 nbc
                  then i1
                  else loop list
            | [] -> raise Not_found ]
      in
      let f1 = "person" in
      let f2 = if spi.is_first_name then "first_name" else "surname" in
      let ic = fast_open_in_bin_and_seek db2 f1 f2 "index.acc" (4 * i) in
      let pos = input_binary_int ic in
      let ic = fast_open_in_bin_and_seek db2 f1 f2 "index.dat" pos in
      let (pos, i) =
        try
          loop i where rec loop i =
            let (s1, pos) : (string * int) = Iovalue.input ic in
            if start_with s1 s then (pos, i) else loop (i + 1)
        with
        [ End_of_file -> raise Not_found ]
      in
      spi.ini := s;
      spi.curr := i;
      Istr2 db2 (f1, f2) pos
    } ]
;

value spi_next spi istr need_whole_list =
  match (spi, istr) with
  [ (Spi spi, Istr s) -> (Istr (spi.next s), 1)
  | (Spi2 db2 spi, Istr2 _ (f1, f2) _) ->
      let i =
        if spi.ini = "" && not need_whole_list then
          loop spi.index_of_first_char where rec loop =
            fun
            [ [(_, i1) :: ([(_, i2) :: _] as list)] ->
                if spi.curr = i1 then i2 else loop list
            | [] | [_] -> raise Not_found ]
        else spi.curr + 1
      in
      try do {
        let ic =
          if i = spi.curr + 1 then
            Hashtbl.find db2.cache_chan (f1, f2, "index.dat")
          else
            let ic =
              fast_open_in_bin_and_seek db2 f1 f2 "index.acc" (i * 4)
            in
            let pos = input_binary_int ic in
            fast_open_in_bin_and_seek db2 f1 f2 "index.dat" pos
        in
        let (s, pos) : (string * int) = Iovalue.input ic in
        let dlen = i - spi.curr in
        spi.curr := i;
        (Istr2 db2 (f1, f2) pos, dlen)
      }
      with
      [ End_of_file -> raise Not_found ]
  | _ -> failwith "not impl spi_next" ]
;

value spi_find spi s =
  match (spi, s) with
  [ (Spi spi, Istr s) -> spi.find s
  | (Spi2 _ _, Istr2 db2 (f1, f2) pos) -> do {
      let dir = List.fold_left Filename.concat db2.bdir [f1; f2] in
      hashtbl_find_all dir "person_of_string.ht" pos
    }
  | (Spi2 _ spi, Istr2New db2 s) ->
      let proj =
        if spi.is_first_name then fun p -> p.first_name
        else fun p -> p.surname
      in
      Hashtbl.fold
        (fun _ iper iperl ->
           try
             let p = Hashtbl.find db2.patches.h_person iper in
             if proj p = s then [iper :: iperl] else iperl
           with
           [ Not_found -> iperl ])
        db2.patches.h_key []
  | _ -> failwith "not impl spi_find" ]
;

(*
value base_visible_get base f =
  match base with
  [ Base base -> base.data.visible.v_get (fun p -> f (Person p))
  | Base2 _ -> failwith "not impl visible_get" ]
;
value base_visible_write base =
  match base with
  [ Base base -> base.data.visible.v_write ()
  | Base2 _ -> failwith "not impl visible_write" ]
;
*)

value base_strings_of_first_name_or_surname base field proj s =
  match base with
  [ Base base -> List.map (fun s -> Istr s) (base.func.strings_of_fsname s)
  | Base2 db2 ->
      let posl = strings2_of_fsname db2 field s in
      let istrl =
        List.map (fun pos -> Istr2 db2 ("person", field) pos) posl
      in
      let s = Name.crush_lower s in
      Hashtbl.fold
        (fun _ iper istrl ->
           try
             let p = Hashtbl.find db2.patches.h_person iper in
             if Name.crush_lower (proj p) = s then
               [Istr2New db2 (proj p) :: istrl]
             else istrl
           with
           [ Not_found -> istrl ])
        db2.patches.h_key istrl ]
;

(*
value base_strings_of_first_name base s =
  base_strings_of_first_name_or_surname base "first_name"
    (fun p -> p.first_name) s
;

value base_strings_of_surname base s =
  base_strings_of_first_name_or_surname base "surname"
    (fun p -> p.surname) s
;
*)

value load_array2 bdir nb_ini nb f1 f2 get =
  if nb = 0 then [| |]
  else do {
    let ic_acc =
      open_in_bin (List.fold_left Filename.concat bdir [f1; f2; "access"])
    in
    let ic_dat =
      open_in_bin (List.fold_left Filename.concat bdir [f1; f2; "data"])
    in
    let tab = Array.create nb (get ic_dat (input_binary_int ic_acc)) in
    for i = 1 to nb_ini - 1 do {
      tab.(i) := get ic_dat (input_binary_int ic_acc);
    };
    close_in ic_dat;
    close_in ic_acc;
    tab
  }
;

value parents_array2 db2 nb_ini nb = do {
  let arr =
    load_array2 db2.bdir nb_ini nb "person" "parents"
      (fun ic_dat pos ->
         if pos = -1 then None
         else do {
           seek_in ic_dat pos;
           Some (Iovalue.input ic_dat : ifam)
         })
  in
  Hashtbl.iter (fun i a -> arr.(Adef.int_of_iper i) := a.parents)
    db2.patches.h_ascend;
  arr
};

value consang_array2 db2 nb =
  let cg_fname =
    List.fold_left Filename.concat db2.bdir ["person"; "consang"; "data"]
  in
  match try Some (open_in_bin cg_fname) with [ Sys_error _ -> None ] with
  [ Some ic -> do {
      let tab = input_value ic in
      close_in ic;
      tab
    }
  | None -> Array.make nb no_consang ]
;

value family_array2 db2 = do {
  let fname =
    List.fold_left Filename.concat db2.bdir ["person"; "family"; "data"]
  in
  let ic = open_in_bin fname in
  let tab = input_value ic in
  close_in ic;
  tab
};

(*
value load_ascends_array base =
  match base with
  [ Base base -> base.data.ascends.load_array ()
  | Base2 db2 -> do {
      eprintf "*** loading ascends array\n"; flush stderr;
      let nb = db2.patches.nb_per in
      let nb_ini = db2.patches.nb_per_ini in
      match db2.parents_array with
      [ Some _ -> ()
      | None -> db2.parents_array := Some (parents_array2 db2 nb_ini nb) ];
      match db2.consang_array with
      [ Some _ -> ()
      | None -> db2.consang_array := Some (consang_array2 db2 nb) ];
    } ]
;

value load_unions_array base =
  match base with
  [ Base base -> base.data.unions.load_array ()
  | Base2 db2 ->
      match db2.family_array with
      [ Some _ -> ()
      | None -> do {
          eprintf "*** loading unions array\n"; flush stderr;
          db2.family_array := Some (family_array2 db2)
        } ] ]
;

value load_couples_array base =
  match base with
  [ Base base -> base.data.couples.load_array ()
  | Base2 db2 -> do {
      eprintf "*** loading couples array\n"; flush stderr;
      let nb = db2.patches.nb_fam in
      match db2.father_array with
      [ Some _ -> ()
      | None -> do {
          let tab =
            load_array2 db2.bdir db2.patches.nb_fam_ini nb "family" "father"
              (fun ic_dat pos -> do {
                 seek_in ic_dat pos;
                 Iovalue.input ic_dat
               })
          in
          Hashtbl.iter (fun i c -> tab.(Adef.int_of_ifam i) := father c)
            db2.patches.h_couple;
          db2.father_array := Some tab
        } ];
      match db2.mother_array with
      [ Some _ -> ()
      | None -> do {
          let tab =
            load_array2 db2.bdir db2.patches.nb_fam_ini nb "family" "mother"
              (fun ic_dat pos -> do {
                 seek_in ic_dat pos;
                 Iovalue.input ic_dat
               })
          in
          Hashtbl.iter (fun i c -> tab.(Adef.int_of_ifam i) := mother c)
            db2.patches.h_couple;
          db2.mother_array := Some tab
        } ]
    } ]
;
*)

value children_array2 db2 = do {
  let fname =
    List.fold_left Filename.concat db2.bdir ["family"; "children"; "data"]
  in
  let ic = open_in_bin fname in
  let tab = input_value ic in
  close_in ic;
  tab
};

(*
value load_descends_array base =
  match base with
  [ Base base -> base.data.descends.load_array ()
  | Base2 db2 ->
      match db2.children_array with
      [ Some _ -> ()
      | None -> do {
          eprintf "*** loading descends array\n"; flush stderr;
          db2.children_array := Some (children_array2 db2)
        } ] ]
;

value load_strings_array base =
  match base with
  [ Base base -> base.data.strings.load_array ()
  | Base2 _ -> () ]
;

value persons_array base =
  match base with
  [ Base base ->
      let get i = Person (base.data.persons.get i) in
      let set i =
        fun
        [ Person p -> base.data.persons.set i p
        | Person2 _ _ -> assert False
        | Person2Gen _ _ -> assert False ]
      in
      (get, set)
  | Base2 _ -> failwith "not impl persons_array" ]
;

value ascends_array base =
  match base with
  [ Base base ->
      let fget i = (base.data.ascends.get i).parents in
      let cget i = (base.data.ascends.get i).consang in
      let cset i v =
        base.data.ascends.set i
          {(base.data.ascends.get i) with consang = v}
      in
      (fget, cget, cset, None)
  | Base2 db2 ->
      let nb = nb_of_persons base in
      let cg_tab =
        match db2.consang_array with
        [ Some tab -> tab
        | None -> consang_array2 db2 nb ]
      in
      let fget i = get_parents (Ascend2 db2 i) in
      let cget i = cg_tab.(i) in
      let cset i v = cg_tab.(i) := v in
      (fget, cget, cset, Some cg_tab) ]
;

value output_consang_tab base tab =
  match base with
  [ Base _ -> do { eprintf "error Gwdb.output_consang_tab\n"; flush stdout }
  | Base2 db2 -> do {
      let dir =
        List.fold_left Filename.concat db2.bdir ["person"; "consang"]
      in
      Mutil.mkdir_p dir;
      let oc = open_out_bin (Filename.concat dir "data") in
      output_value oc tab;
      close_out oc;
      let oc = open_out_bin (Filename.concat dir "access") in
      let _ : int =
        Iovalue.output_array_access oc (Array.get tab) (Array.length tab) 0
      in
      close_out oc;
    } ]
;
*)

value read_notes bname fnotes rn_mode =
  let fname =
    if fnotes = "" then "notes.txt"
    else Filename.concat "notes_d" (fnotes ^ ".txt")
  in
  let fname = Filename.concat "base_d" fname in
  match
    try Some (Secure.open_in (Filename.concat bname fname)) with
    [ Sys_error _ -> None ]
  with
  [ Some ic -> do {
      let str =
        match rn_mode with
        [ RnDeg -> if in_channel_length ic = 0 then "" else " "
        | Rn1Ln -> try input_line ic with [ End_of_file -> "" ]
        | RnAll ->
            loop 0 where rec loop len =
              match try Some (input_char ic) with [ End_of_file -> None ] with
              [ Some c -> loop (Buff.store len c)
              | _ -> Buff.get len ] ]
      in
      close_in ic;
      str
    }
  | None -> "" ]
;
(*
value base_notes_read base fnotes =
  match base with
  [ Base base -> base.data.bnotes.nread fnotes RnAll
  | Base2 {bdir = bn} -> read_notes (Filename.dirname bn) fnotes RnAll ]
;
value base_notes_read_first_line base fnotes =
  match base with
  [ Base base -> base.data.bnotes.nread fnotes Rn1Ln
  | Base2 {bdir = bn} -> read_notes (Filename.dirname bn) fnotes Rn1Ln ]
;
value base_notes_are_empty base fnotes =
  match base with
  [ Base base -> base.data.bnotes.nread fnotes RnDeg = ""
  | Base2 {bdir = bn} -> read_notes (Filename.dirname bn) fnotes RnDeg = "" ]
;

value base_notes_origin_file base =
  match base with
  [ Base base -> base.data.bnotes.norigin_file
  | Base2 db2 ->
      let fname = Filename.concat db2.bdir "notes_of.txt" in
      match try Some (Secure.open_in fname) with [ Sys_error _ -> None ] with
      [ Some ic -> do {
          let r = input_line ic in
          close_in ic;
          r
        }
      | None -> "" ] ]
;

value base_notes_dir base =
  match base with
  [ Base _ -> "notes_d"
  | Base2 _ -> Filename.concat "base_d" "notes_d" ]
;

value base_wiznotes_dir base =
  match base with
  [ Base _ -> "wiznotes"
  | Base2 _ -> Filename.concat "base_d" "wiznotes_d" ]
;

value p_first_name base p = nominative (sou base (get_first_name p));
value p_surname base p = nominative (sou base (get_surname p));

value nobtit conf base p =
  let list = get_titles p in
  match Lazy.force conf.allowed_titles with
  [ [] -> list
  | allowed_titles ->
      let list =
        List.fold_right
          (fun t l ->
             let id = Name.lower (sou base t.t_ident) in
             let pl = Name.lower (sou base t.t_place) in
             if pl = "" then
               if List.mem id allowed_titles then [t :: l] else l
             else if
               List.mem (id ^ "/" ^ pl) allowed_titles ||
               List.mem (id ^ "/*") allowed_titles
             then
               [t :: l]
             else l)
          list []
      in
      match Lazy.force conf.denied_titles with
      [ [] -> list
      | denied_titles ->
          List.filter
            (fun t ->
               let id = Name.lower (sou base t.t_ident) in
               let pl = Name.lower (sou base t.t_place) in
               if List.mem (id ^ "/" ^ pl) denied_titles ||
                  List.mem ("*/" ^ pl) denied_titles
               then False
               else True)
            list ] ]
;

value husbands base p =
  let u = uoi base (get_key_index p) in
  List.map
    (fun ifam ->
       let cpl = coi base ifam in
       let husband = poi base (get_father cpl) in
       let husband_surname = p_surname base husband in
       let husband_surnames_aliases =
         List.map (sou base) (get_surnames_aliases husband)
       in
       (husband_surname, husband_surnames_aliases))
    (Array.to_list (get_family u))
;

value father_titles_places base p nobtit =
  match get_parents (aoi base (get_key_index p)) with
  [ Some ifam ->
      let cpl = coi base ifam in
      let fath = poi base (get_father cpl) in
      List.map (fun t -> sou base t.t_place) (nobtit fath)
  | None -> [] ]
;

value person_misc_names base p tit =
  let sou = sou base in
  Futil.gen_person_misc_names (sou (get_first_name p))
    (sou (get_surname p)) (sou (get_public_name p))
    (List.map sou (get_qualifiers p)) (List.map sou (get_aliases p))
    (List.map sou (get_first_names_aliases p))
    (List.map sou (get_surnames_aliases p))
    (List.map (Futil.map_title_strings sou) (tit p))
    (if get_sex p = Female then husbands base p else [])
    (father_titles_places base p tit)
;
*)

value base_of_dsk_base base = Base base;
value apply_as_dsk_base f base =
  match base with
  [ Base base -> f base
  | Base2 _ -> failwith "not impl apply_as_dsk_base" ]
;

value dsk_person_of_person =
  fun
  [ Person p -> p
  | Person2 _ _ -> failwith "not impl dsk_person_of_person"
  | Person2Gen _ _ -> failwith "not impl dsk_person_of_person (gen)" ]
;

(*
value date_of_last_change bname base =
  let bdir =
    if Filename.check_suffix bname ".gwb" then bname else bname ^ ".gwb"
  in
  let s =
    match base with
    [ Base _ ->
        try Unix.stat (Filename.concat bdir "patches") with
        [ Unix.Unix_error _ _ _ -> Unix.stat (Filename.concat bdir "base") ]
    | Base2 db2 ->
        let bdir = Filename.concat bdir "base_d" in
        try Unix.stat (Filename.concat bdir "patches") with
        [ Unix.Unix_error _ _ _ -> Unix.stat bdir ] ]
  in
  s.Unix.st_mtime
;
*)

value check_magic ic magic id = do {
  let b = String.create (String.length magic) in
  really_input ic b 0 (String.length b);
  if b <> magic then failwith (sprintf "bad %s magic number" id)
  else ();
};

value base_of_base2 bname =
  let bname =
    if Filename.check_suffix bname ".gwb" then bname else bname ^ ".gwb"
  in
  let bdir = Filename.concat bname "base_d" in
  let patches =
    let patch_fname = Filename.concat bdir "patches" in
    match try Some (open_in_bin patch_fname) with [ Sys_error _ -> None ] with
    [ Some ic -> do {
        check_magic ic magic_patch "patch";
        let p = input_value ic in
        close_in ic;
        flush stderr;
        p
      }
    | None ->
        let nb_per =
          let fname =
            List.fold_left Filename.concat bdir
              ["person"; "sex"; "access"]
          in
          let st = Unix.lstat fname in
          st.Unix.st_size / 4
        in
        let nb_fam =
          let fname =
            List.fold_left Filename.concat bdir
              ["family"; "marriage"; "access"]
          in
          let st = Unix.lstat fname in
          st.Unix.st_size / 4
        in
        let empty_ht () = Hashtbl.create 1 in
        {nb_per = nb_per; nb_fam = nb_fam;
         nb_per_ini = nb_per; nb_fam_ini = nb_fam;
         h_person = empty_ht (); h_ascend = empty_ht ();
         h_union = empty_ht (); h_family = empty_ht ();
         h_couple = empty_ht (); h_descend = empty_ht ();
         h_key = empty_ht (); h_name = empty_ht ()} ]
  in
  Base2
    {bdir = bdir; cache_chan = Hashtbl.create 1; patches = patches;
     parents_array = None; consang_array = None; family_array = None;
     father_array = None; mother_array = None; children_array = None;
     phony () = ()}
;

value open_base bname =
  let bname =
    if Filename.check_suffix bname ".gwb" then bname else bname ^ ".gwb"
  in
  if Sys.file_exists (Filename.concat bname "base_d") then do {
    Printf.eprintf "*** database new implementation\n";
    flush stderr; 
    base_of_base2 bname
  }
  else base_of_dsk_base (Database.opendb bname)
;

(*
value close_base base =
  match base with
  [ Base base -> base.func.cleanup ()
  | Base2 db2 ->
      Hashtbl.iter (fun (f1, f2, f) ic -> close_in ic) db2.cache_chan ]
;
*)

(* Implementation by emulated objects *)

(*

(* This code works only with camlp4s *)

#load "pa_pragma.cmo";
#load "pa_extend.cmo";
#load "q_MLast.cmo";

#pragma
  EXTEND
    GLOBAL: expr str_item;
    expr: LEVEL "."
      [ [ e1 = SELF; ".."; e2 = SELF -> <:expr< $e1$ . $e2$ () >> ] ]
    ;
    expr: LEVEL "apply"
      [ [ "nouvel_objet"; e = SELF -> <:expr< $e$ () >> ] ]
    ;
    str_item:
      [ [ "classe"; "virtuelle"; n = LIDENT;
          (so, ldel) = fonction_objet_virtuel ->
            let td =
              let ldl =
                List.fold_right
                  (fun (loc, n, t_o, _) ldl ->
                     if t_o = None then ldl
                     else [(loc, n, False, match_with_some t_o) :: ldl])
                  ldel []
              in
              <:str_item< type $n$ = { $list:ldl$ } >>
            in
            let lel =
              List.fold_right
                (fun (loc, n, _, eo) lel ->
                   if eo = None then lel
                   else [(loc, n, match_with_some eo) :: lel])
                ldel []
            in
            if lel = [] then td
            else
              let stl =
                List.map
                  (fun (loc, lab, (e, teo)) ->
                     if teo = None then
                       <:str_item< value $lid:lab$ = $e$ >>
                     else
                       let e =
                         if so = None then e
                         else
                           let s = match_with_some so in
                           <:expr< fun $lid:s$ -> $e$ >>
                       in
                       <:str_item< value $lid:lab$ = fun () -> $e$ >>)
                  lel
              in
              let sgl =
                List.fold_right
                  (fun (loc, lab, (e, teo)) sgl ->
                     if teo = None then sgl
                     else
                       let sg =
                         let te = match_with_some teo in
                         let t =
                          if so = None then te else <:ctyp< $lid:n$ -> $te$ >>
                         in
                         <:sig_item< value $lid:lab$ : unit -> $t$ >>
                       in
                       [sg :: sgl])
                  lel []
              in
              let md =
                <:str_item<
                  module $uid:"C_" ^ n$ : sig $list:sgl$ end =
                    struct $list:stl$ end >>
              in
              <:str_item< declare $td$; $md$; end >>
        | "classe"; n = LIDENT; e = fonction_objet ->
            <:str_item< value $lid:n$ () = $e$ >> ] ]
    ;
    fonction_objet_virtuel:
      [ [ "="; "objet"; "("; soi = LIDENT; ")";
          ldel = LIST0 champ_d_objet_virtuel; "fin" ->
            (Some soi, ldel)
        | "="; "objet"; ldel = LIST0 champ_d_objet_virtuel; "fin" ->
            (None, ldel) ] ]
    ;
    fonction_objet:
      [ [ p = LIDENT; e = fonction_objet -> <:expr< fun $lid:p$ -> $e$ >>
        | "="; "objet"; "("; soi = LIDENT; ")"; lel = LIST0 champ_d_objet;
          "fin" ->
            <:expr< let rec $lid:soi$ = { $list:lel$ } in $lid:soi$ >>
        | "="; "objet"; lel = LIST0 champ_d_objet; "fin" ->
            <:expr< { $list:lel$ } >> ] ]
    ;
    champ_d_objet_virtuel:
      [ [ "valeur"; n = LIDENT; ":"; t = ctyp; ";" ->
            (loc, n, Some t, None)
        | "valeur"; "privee"; n = LIDENT; e = fonction_methode; ";" ->
            (loc, n, None, Some (e, None))
        | "methode"; n = LIDENT; pl = LIST0 LIDENT; ":"; t = ctyp;
          eo = OPT fonction_methode_virtuelle; ";" ->
            let eto =
              if eo = None then None
              else
                let e =
                  List.fold_right (fun p e -> <:expr< fun $lid:p$ -> $e$ >>)
                    pl (match_with_some eo)
                in
                Some (e, Some t)
            in
            (loc, n, Some <:ctyp< unit -> $t$ >>, eto) ] ]
    ;
    fonction_methode_virtuelle:
      [ [ "="; e = expr -> e ] ]
    ;
    champ_d_objet:
      [ [ "valeur"; n = LIDENT; "="; e = expr; ";" ->
            (<:patt< $lid:n$ >>, e)
        | "methode"; n = LIDENT; e = fonction_methode; ";" ->
            (<:patt< $lid:n$ >>, <:expr< fun () -> $e$ >>)
        | "heriter"; c = LIDENT; ".."; n = LIDENT; el = LIST0 expr; ";" ->
            let f = <:expr< $uid:"C_" ^ c$ . $lid:n$ () >> in
            let e = List.fold_left (fun f e -> <:expr< $f$ $e$ >>) f el in
            (<:patt< $lid:n$ >>, <:expr< fun () -> $e$ >>) ] ]
    ;
    fonction_methode:
      [ [ p = LIDENT; e = fonction_methode -> <:expr< fun $lid:p$ -> $e$ >>
        | "="; e = expr -> e ] ]
    ;
  END;

classe virtuelle base =
  objet (self)
    valeur privee husbands self p =
      let u = self..uoi (get_key_index p) in
      List.map
        (fun ifam ->
           let cpl = self..coi ifam in
           let husband = self..poi (get_father cpl) in
           let husband_surname = self..p_surname husband in
           let husband_surnames_aliases =
             List.map self..sou (get_surnames_aliases husband)
           in
           (husband_surname, husband_surnames_aliases))
        (Array.to_list (get_family u))
    ;
    valeur privee father_titles_places self p nobtit =
      match get_parents (self..aoi (get_key_index p)) with
      [ Some ifam ->
          let cpl = self..coi ifam in
          let fath = self..poi (get_father cpl) in
          List.map (fun t -> self..sou t.t_place) (nobtit fath)
      | None -> [] ]
    ;
    valeur base_t : base_t;
    methode close_base : unit;
    methode person_of_gen_person : Def.gen_person iper istr -> person;
    methode ascend_of_gen_ascend : Def.gen_ascend ifam -> ascend;
    methode union_of_gen_union : Def.gen_union ifam -> union;
    methode family_of_gen_family : Def.gen_family iper istr -> family;
    methode couple_of_gen_couple : Def.gen_couple iper -> couple;
    methode descend_of_gen_descend : Def.gen_descend iper -> descend;
    methode poi : iper -> person;
    methode aoi : iper -> ascend;
    methode uoi : iper -> union;
    methode foi : ifam -> family;
    methode coi : ifam -> couple;
    methode doi : ifam -> descend;
    methode sou : istr -> string;
    methode nb_of_persons : int;
    methode nb_of_families : int;
    methode patch_person : iper -> person -> unit;
    methode patch_ascend : iper -> ascend -> unit;
    methode patch_union : iper -> union -> unit;
    methode patch_family : ifam -> family -> unit;
    methode patch_descend : ifam -> descend -> unit;
    methode patch_couple : ifam -> couple -> unit;
    methode patch_key : iper -> string -> string -> int -> unit;
    methode patch_name : string -> iper -> unit;
    methode insert_string : string -> istr;
    methode commit_patches : unit;
    methode commit_notes : string -> string -> unit;
    methode is_patched_person : iper -> bool;
    methode patched_ascends : list iper;
    methode output_consang_tab : array Adef.fix -> unit;
    methode delete_family ifam : ifam -> unit = do {
      let cpl =
        self..couple_of_gen_couple
          (couple (Adef.iper_of_int (-1)) (Adef.iper_of_int (-1)))
      in
      let fam =
        let empty = self..insert_string "" in
        self..family_of_gen_family
          {marriage = codate_None; marriage_place = empty; marriage_src = empty;
           relation = Married; divorce = NotDivorced; witnesses = [| |];
           comment = empty; origin_file = empty; fsources = empty;
           fam_index = Adef.ifam_of_int (-1)}
      in
      let des = self..descend_of_gen_descend {children = [| |]} in
      self..patch_family ifam fam;
      self..patch_couple ifam cpl;
      self..patch_descend ifam des
    };
    methode person_of_key : string -> string -> int -> option iper;
    methode persons_of_name : string -> list iper;
    methode persons_of_first_name : string_person_index;
    methode persons_of_surname : string_person_index;
    methode base_visible_get : (person -> bool) -> int -> bool;
    methode base_visible_write : unit;
    methode base_particles : list string;
    methode base_strings_of_first_name s : string -> list istr =
      base_strings_of_first_name_or_surname self.base_t "first_name"
        (fun p -> p.first_name) s
    ;
    methode base_strings_of_surname s : string -> list istr =
      base_strings_of_first_name_or_surname self.base_t "surname"
        (fun p -> p.surname) s
    ;
    methode load_ascends_array : unit;
    methode load_unions_array : unit;
    methode load_couples_array : unit;
    methode load_descends_array : unit;
    methode load_strings_array : unit;
    methode persons_array : (int -> person * int -> person -> unit);
    methode ascends_array :
      (int -> option ifam *
       int -> Adef.fix *
       int -> Adef.fix -> unit *
       option (array Adef.fix));
    methode base_notes_read : string -> string;
    methode base_notes_read_first_line : string -> string;
    methode base_notes_are_empty : string -> bool;
    methode base_notes_origin_file : string;
    methode base_notes_dir : string;
    methode base_wiznotes_dir : string;
    methode person_misc_names p tit :
      person -> (person -> list title) -> list string
    =
      let sou = self..sou in
      Futil.gen_person_misc_names (sou (get_first_name p))
        (sou (get_surname p)) (sou (get_public_name p))
        (List.map sou (get_qualifiers p)) (List.map sou (get_aliases p))
        (List.map sou (get_first_names_aliases p))
        (List.map sou (get_surnames_aliases p))
        (List.map (Futil.map_title_strings sou) (tit p))
        (if get_sex p = Female then husbands self p else [])
        (father_titles_places self p tit)
    ;
    methode nobtit conf p : config -> person -> list title =
      let list = get_titles p in
      match Lazy.force conf.allowed_titles with
      [ [] -> list
      | allowed_titles ->
          let list =
            List.fold_right
              (fun t l ->
                 let id = Name.lower (self..sou t.t_ident) in
                 let pl = Name.lower (self..sou t.t_place) in
                 if pl = "" then
                   if List.mem id allowed_titles then [t :: l] else l
                 else if
                   List.mem (id ^ "/" ^ pl) allowed_titles ||
                   List.mem (id ^ "/*") allowed_titles
                 then
                   [t :: l]
                 else l)
              list []
          in
          match Lazy.force conf.denied_titles with
          [ [] -> list
          | denied_titles ->
              List.filter
                (fun t ->
                   let id = Name.lower (self..sou t.t_ident) in
                   let pl = Name.lower (self..sou t.t_place) in
                   if List.mem (id ^ "/" ^ pl) denied_titles ||
                      List.mem ("*/" ^ pl) denied_titles
                   then False
                   else True)
                list ] ]
    ;
    methode p_first_name p : person -> string =
      nominative (self..sou (get_first_name p));
    methode p_surname p : person -> string =
      nominative (self..sou (get_surname p));
    methode date_of_last_change : string -> float;
  fin
;

classe base1 b base =
  objet (self)
    valeur base_t = b;
    methode close_base = base.func.cleanup ();
    methode person_of_gen_person p =
      Person (map_person_ps (fun p -> p) un_istr p);
    methode ascend_of_gen_ascend a = Ascend a;
    methode union_of_gen_union u = Union u;
    methode family_of_gen_family f =
      Family (map_family_ps (fun p -> p) un_istr f);
    methode couple_of_gen_couple c = Couple c;
    methode descend_of_gen_descend d = Descend d;
    methode poi i = Person (base.data.persons.get (Adef.int_of_iper i));
    methode aoi i = Ascend (base.data.ascends.get (Adef.int_of_iper i));
    methode uoi i = Union (base.data.unions.get (Adef.int_of_iper i));
    methode foi i = Family (base.data.families.get (Adef.int_of_ifam i));
    methode coi i = Couple (base.data.couples.get (Adef.int_of_ifam i));
    methode doi i = Descend (base.data.descends.get (Adef.int_of_ifam i));
    methode sou = sou b;
    methode nb_of_persons = base.data.persons.len;
    methode nb_of_families = base.data.families.len;
    methode patch_person ip p =
      match p with
      [ Person p -> base.func.Dbdisk.patch_person ip p
      | _ -> assert False ]
    ;
    methode patch_ascend ip a =
      match a with
      [ Ascend a -> base.func.Dbdisk.patch_ascend ip a
      | _ -> assert False ]
    ;
    methode patch_union ip u =
      match u with
      [ Union u -> base.func.Dbdisk.patch_union ip u
      | _ -> failwith "not impl patch_union" ]
    ;
    methode patch_family ifam f =
      match f with
      [ Family f -> base.func.Dbdisk.patch_family ifam f
      | _ -> failwith "not impl patch_family" ]
    ;
    methode patch_descend ifam d =
      match d with
      [ Descend d -> base.func.Dbdisk.patch_descend ifam d
      | _ -> failwith "not impl patch_descend" ]
    ;
    methode patch_couple ifam c =
      match c with
      [ Couple c -> base.func.Dbdisk.patch_couple ifam c
      | _ -> failwith "not impl patch_couple" ]
    ;
    methode patch_key ip fn sn occ = ();
    methode patch_name s ip = base.func.Dbdisk.patch_name s ip;
    methode insert_string s = Istr (base.func.Dbdisk.insert_string s);
    methode commit_patches = base.func.Dbdisk.commit_patches ();
    methode commit_notes = base.func.Dbdisk.commit_notes;
    methode is_patched_person ip = base.func.Dbdisk.is_patched_person ip;
    methode patched_ascends = base.func.Dbdisk.patched_ascends ();
    methode output_consang_tab tab = do {
      eprintf "error Gwdb.output_consang_tab\n";
      flush stdout
    };
    heriter base..delete_family self;
    methode person_of_key = base.func.Dbdisk.person_of_key;
    methode persons_of_name = base.func.Dbdisk.persons_of_name;
    methode persons_of_first_name =
      Spi base.func.Dbdisk.persons_of_first_name;
    methode persons_of_surname =
      Spi base.func.Dbdisk.persons_of_surname;
    methode base_visible_get f =
      base.data.visible.v_get (fun p -> f (Person p));
    methode base_visible_write = base.data.visible.v_write ();
    methode base_particles = base.data.particles;
    heriter base..base_strings_of_first_name self;
    heriter base..base_strings_of_surname self;
    methode load_ascends_array = base.data.ascends.load_array ();
    methode load_unions_array = base.data.unions.load_array ();
    methode load_couples_array = base.data.couples.load_array ();
    methode load_descends_array = base.data.descends.load_array ();
    methode load_strings_array = base.data.strings.load_array ();
    methode persons_array =
      let get i = Person (base.data.persons.get i) in
      let set i =
        fun
        [ Person p -> base.data.persons.set i p
        | Person2 _ _ -> assert False
        | Person2Gen _ _ -> assert False ]
      in
      (get, set)
    ;
    methode ascends_array =
      let fget i = (base.data.ascends.get i).parents in
      let cget i = (base.data.ascends.get i).consang in
      let cset i v =
        base.data.ascends.set i
          {(base.data.ascends.get i) with consang = v}
      in
      (fget, cget, cset, None)
    ;
    methode base_notes_read fnotes = base.data.bnotes.nread fnotes RnAll;
    methode base_notes_read_first_line fnotes =
      base.data.bnotes.nread fnotes Rn1Ln;
    methode base_notes_are_empty fnotes =
      base.data.bnotes.nread fnotes RnDeg = "";
    methode base_notes_origin_file = base.data.bnotes.norigin_file;
    methode base_notes_dir = "notes_d";
    methode base_wiznotes_dir = "wiznotes";
    heriter base..person_misc_names self;
    heriter base..nobtit self;
    heriter base..p_first_name self;
    heriter base..p_surname self;
    methode date_of_last_change bname =
      let bdir =
        if Filename.check_suffix bname ".gwb" then bname else bname ^ ".gwb"
      in
      let s =
        try Unix.stat (Filename.concat bdir "patches") with
        [ Unix.Unix_error _ _ _ -> Unix.stat (Filename.concat bdir "base") ]
      in
      s.Unix.st_mtime
    ;
  fin
;

classe base2 b db2 =
  objet (self)
    valeur base_t = b;
    methode close_base =
      Hashtbl.iter (fun (f1, f2, f) ic -> close_in ic) db2.cache_chan;
    methode person_of_gen_person p =
      Person2Gen db2 (map_person_ps (fun p -> p) un_istr2 p);
    methode ascend_of_gen_ascend a = Ascend2Gen db2 a;
    methode union_of_gen_union u = Union2Gen db2 u;
    methode family_of_gen_family f =
      Family2Gen db2 (map_family_ps (fun p -> p) un_istr2 f);
    methode couple_of_gen_couple c = Couple2Gen db2 c;
    methode descend_of_gen_descend d = Descend2Gen db2 d;
    methode poi i =
      try Person2Gen db2 (Hashtbl.find db2.patches.h_person i) with
      [ Not_found -> Person2 db2 (Adef.int_of_iper i) ]
    ;
    methode aoi i =
      try Ascend2Gen db2 (Hashtbl.find db2.patches.h_ascend i) with
      [ Not_found -> Ascend2 db2 (Adef.int_of_iper i) ]
    ;
    methode uoi i =
      try Union2Gen db2 (Hashtbl.find db2.patches.h_union i) with
      [ Not_found -> Union2 db2 (Adef.int_of_iper i) ]
    ;
    methode foi i =
      try Family2Gen db2 (Hashtbl.find db2.patches.h_family i) with
      [ Not_found -> Family2 db2 (Adef.int_of_ifam i) ]
    ;
    methode coi i =
      try Couple2Gen db2 (Hashtbl.find db2.patches.h_couple i) with
      [ Not_found -> Couple2 db2 (Adef.int_of_ifam i) ]
    ;
    methode doi i =
      try Descend2Gen db2 (Hashtbl.find db2.patches.h_descend i) with
      [ Not_found -> Descend2 db2 (Adef.int_of_ifam i) ]
    ;
    methode sou = sou b;
    methode nb_of_persons = db2.patches.nb_per;
    methode nb_of_families = db2.patches.nb_fam;
    methode patch_person ip p =
      match p with
      [ Person2Gen _ p -> do {
          Hashtbl.replace db2.patches.h_person ip p;
          db2.patches.nb_per :=
            max (Adef.int_of_iper ip + 1) db2.patches.nb_per;
        }
      | _ -> assert False ]
    ;
    methode patch_ascend ip a =
      match a with
      [ Ascend2Gen _ a -> do {
          Hashtbl.replace db2.patches.h_ascend ip a;
          db2.patches.nb_per :=
            max (Adef.int_of_iper ip + 1) db2.patches.nb_per;
        }
      | _ -> assert False ]
    ;
    methode patch_union ip u =
      match u with
      [ Union2Gen _ u -> do {
          Hashtbl.replace db2.patches.h_union ip u;
          db2.patches.nb_per :=
            max (Adef.int_of_iper ip + 1) db2.patches.nb_per;
        }
      | _ -> failwith "not impl patch_union" ]
    ;
    methode patch_family ifam f =
      match f with
      [ Family2Gen _ f -> do {
          Hashtbl.replace db2.patches.h_family ifam f;
          db2.patches.nb_fam :=
            max (Adef.int_of_ifam ifam + 1) db2.patches.nb_fam;
        }
      | _ -> failwith "not impl patch_family" ]
    ;
    methode patch_descend ifam d =
      match d with
      [ Descend2Gen _ d -> do {
          Hashtbl.replace db2.patches.h_descend ifam d;
          db2.patches.nb_fam :=
            max (Adef.int_of_ifam ifam + 1) db2.patches.nb_fam;
        }
      | _ -> failwith "not impl patch_descend" ]
    ;
    methode patch_couple ifam c =
      match c with
      [ Couple2Gen _ c -> do {
          Hashtbl.replace db2.patches.h_couple ifam c;
          db2.patches.nb_fam :=
            max (Adef.int_of_ifam ifam + 1) db2.patches.nb_fam;
        }
      | _ -> failwith "not impl patch_couple" ]
    ;
    methode patch_key ip fn sn occ = do {
      Hashtbl.iter
        (fun key ip1 ->
           if ip = ip1 then Hashtbl.remove db2.patches.h_key key else ())
        db2.patches.h_key;
      let fn = Name.lower (nominative fn) in
      let sn = Name.lower (nominative sn) in
      Hashtbl.replace db2.patches.h_key (fn, sn, occ) ip
    };
    methode patch_name s ip =
      let s = Name.crush_lower s in
      let ht = db2.patches.h_name in
      try
        let ipl = Hashtbl.find ht s in
        if List.mem ip ipl then () else Hashtbl.replace ht s [ip :: ipl]
      with
      [ Not_found -> Hashtbl.add ht s [ip] ]
    ;
    methode insert_string s = Istr2New db2 s;
    methode commit_patches = do {
      let fname = Filename.concat db2.bdir "patches" in
      let oc = open_out_bin (fname ^ "1") in
      output_string oc magic_patch;
      output_value oc db2.patches;
      close_out oc;
      remove_file (fname ^ "~");
      try Sys.rename fname (fname ^ "~") with [ Sys_error _ -> () ];
      Sys.rename (fname ^ "1") fname
    };
    methode commit_notes = failwith "not impl commit_notes";
    methode is_patched_person ip =
      let _ =
        if ok_I_know.val then ()
        else do {
          ok_I_know.val := True;
          eprintf "not impl is_patched_person\n";
          flush stderr;
        }
      in
      False
    ;
    methode patched_ascends =
      let _ = do { eprintf "not impl patched_ascends\n"; flush stderr; } in
      []
    ;
    methode output_consang_tab tab = do {
      let dir =
        List.fold_left Filename.concat db2.bdir ["person"; "consang"]
      in
      Mutil.mkdir_p dir;
      let oc = open_out_bin (Filename.concat dir "data") in
      output_value oc tab;
      close_out oc;
      let oc = open_out_bin (Filename.concat dir "access") in
      let _ : int =
        Iovalue.output_array_access oc (Array.get tab) (Array.length tab) 0
      in
      close_out oc;
    };
    heriter base..delete_family self;
    methode person_of_key = person2_of_key db2;
    methode persons_of_name = persons2_of_name db2;
    methode persons_of_first_name =
      persons_of_first_name_or_surname2 db2 True;
    methode persons_of_surname =
      persons_of_first_name_or_surname2 db2 False;
    methode base_visible_get = failwith "not impl visible_get";
    methode base_visible_write = failwith "not impl visible_write";
    methode base_particles =
      Mutil.input_particles (Filename.concat db2.bdir "particles.txt");
    heriter base..base_strings_of_first_name self;
    heriter base..base_strings_of_surname self;
    methode load_ascends_array = do {
      eprintf "*** loading ascends array\n"; flush stderr;
      let nb = db2.patches.nb_per in
      let nb_ini = db2.patches.nb_per_ini in
      match db2.parents_array with
      [ Some _ -> ()
      | None -> db2.parents_array := Some (parents_array2 db2 nb_ini nb) ];
      match db2.consang_array with
      [ Some _ -> ()
      | None -> db2.consang_array := Some (consang_array2 db2 nb) ];
    };
    methode load_unions_array =
      match db2.family_array with
      [ Some _ -> ()
      | None -> do {
          eprintf "*** loading unions array\n"; flush stderr;
          db2.family_array := Some (family_array2 db2)
        } ]
    ;
    methode load_couples_array = do {
      eprintf "*** loading couples array\n"; flush stderr;
      let nb = db2.patches.nb_fam in
      match db2.father_array with
      [ Some _ -> ()
      | None -> do {
          let tab =
            load_array2 db2.bdir db2.patches.nb_fam_ini nb "family" "father"
              (fun ic_dat pos -> do {
                 seek_in ic_dat pos;
                 Iovalue.input ic_dat
               })
          in
          Hashtbl.iter (fun i c -> tab.(Adef.int_of_ifam i) := father c)
            db2.patches.h_couple;
          db2.father_array := Some tab
        } ];
      match db2.mother_array with
      [ Some _ -> ()
      | None -> do {
          let tab =
            load_array2 db2.bdir db2.patches.nb_fam_ini nb "family" "mother"
              (fun ic_dat pos -> do {
                 seek_in ic_dat pos;
                 Iovalue.input ic_dat
               })
          in
          Hashtbl.iter (fun i c -> tab.(Adef.int_of_ifam i) := mother c)
            db2.patches.h_couple;
          db2.mother_array := Some tab
        } ]
    };
    methode load_descends_array =
      match db2.children_array with
      [ Some _ -> ()
      | None -> do {
          eprintf "*** loading descends array\n"; flush stderr;
          db2.children_array := Some (children_array2 db2)
        } ]
    ;
    methode load_strings_array = ();
    methode persons_array = failwith "not impl persons_array";
    methode ascends_array =
      let nb = self..nb_of_persons in
      let cg_tab =
        match db2.consang_array with
        [ Some tab -> tab
        | None -> consang_array2 db2 nb ]
      in
      let fget i = get_parents (Ascend2 db2 i) in
      let cget i = cg_tab.(i) in
      let cset i v = cg_tab.(i) := v in
      (fget, cget, cset, Some cg_tab)
    ;
    methode base_notes_read fnotes =
      read_notes (Filename.dirname db2.bdir) fnotes RnAll;
    methode base_notes_read_first_line fnotes =
      read_notes (Filename.dirname db2.bdir) fnotes Rn1Ln;
    methode base_notes_are_empty fnotes =
      read_notes (Filename.dirname db2.bdir) fnotes RnDeg = "";
    methode base_notes_origin_file =
      let fname = Filename.concat db2.bdir "notes_of.txt" in
      match try Some (Secure.open_in fname) with [ Sys_error _ -> None ] with
      [ Some ic -> do {
          let r = input_line ic in
          close_in ic;
          r
        }
      | None -> "" ]
    ;
    methode base_notes_dir = Filename.concat "base_d" "notes_d";
    methode base_wiznotes_dir = Filename.concat "base_d" "wiznotes_d";
    heriter base..person_misc_names self;
    heriter base..nobtit self;
    heriter base..p_first_name self;
    heriter base..p_surname self;
    methode date_of_last_change bname =
      let bdir =
        if Filename.check_suffix bname ".gwb" then bname else bname ^ ".gwb"
      in
      let s =
        let bdir = Filename.concat bdir "base_d" in
        try Unix.stat (Filename.concat bdir "patches") with
        [ Unix.Unix_error _ _ _ -> Unix.stat bdir ]
      in
      s.Unix.st_mtime
    ;
  fin
;

value open_base bname =
  let b = open_base bname in
  match b with
  [ Base base -> nouvel_objet base1 b base
  | Base2 db2 -> nouvel_objet base2 b db2 ]
;

value close_base b = b..close_base;
value person_of_gen_person b = b..person_of_gen_person;
value ascend_of_gen_ascend b = b..ascend_of_gen_ascend;
value union_of_gen_union b = b..union_of_gen_union;
value family_of_gen_family b = b..family_of_gen_family;
value couple_of_gen_couple b = b..couple_of_gen_couple;
value descend_of_gen_descend b = b..descend_of_gen_descend;
value poi b = b..poi;
value aoi b = b..aoi;
value uoi b = b..uoi;
value foi b = b..foi;
value coi b = b..coi;
value doi b = b..doi;
value sou b = b..sou;
value nb_of_persons b = b..nb_of_persons;
value nb_of_families b = b..nb_of_families;
value patch_person b = b..patch_person;
value patch_ascend b = b..patch_ascend;
value patch_union b = b..patch_union;
value patch_family b = b..patch_family;
value patch_descend b = b..patch_descend;
value patch_couple b = b..patch_couple;
value patch_key b = b..patch_key;
value patch_name b = b..patch_name;
value insert_string b = b..insert_string;
value commit_patches b = b..commit_patches;
value commit_notes b = b..commit_notes;
value is_patched_person b = b..is_patched_person;
value patched_ascends b = b..patched_ascends;
value output_consang_tab b = b..output_consang_tab;
value delete_family b = b..delete_family;
value person_of_key b = b..person_of_key;
value persons_of_name b = b..persons_of_name;
value persons_of_first_name b = b..persons_of_first_name;
value persons_of_surname b = b..persons_of_surname;
value base_visible_get b = b..base_visible_get;
value base_visible_write b = b..base_visible_write;
value base_particles b = b..base_particles;
value base_strings_of_first_name b = b..base_strings_of_first_name;
value base_strings_of_surname b = b..base_strings_of_surname;
value load_ascends_array b = b..load_ascends_array;
value load_unions_array b = b..load_unions_array;
value load_couples_array b = b..load_couples_array;
value load_descends_array b = b..load_descends_array;
value load_strings_array b = b..load_strings_array;
value persons_array b = b..persons_array;
value ascends_array b = b..ascends_array;
value base_notes_read b = b..base_notes_read;
value base_notes_read_first_line b = b..base_notes_read_first_line;
value base_notes_are_empty b = b..base_notes_are_empty;
value base_notes_origin_file b = b..base_notes_origin_file;
value base_notes_dir b = b..base_notes_dir;
value base_wiznotes_dir b = b..base_wiznotes_dir;
value person_misc_names b = b..person_misc_names;
value nobtit conf b = b..nobtit conf;
value p_first_name b = b..p_first_name;
value p_surname b = b..p_surname;
value date_of_last_change s b = b..date_of_last_change s;

value base_of_dsk_base base = nouvel_objet base1 (Base base) base;
value apply_as_dsk_base f base = apply_as_dsk_base f base.base_t;

*)

(* This code is a pretty print of the code above from '#load "pragma.cmo"' *)

declare
  type base =
    { base_t : base_t;
      close_base : unit -> unit;
      person_of_gen_person : unit -> Def.gen_person iper istr -> person;
      ascend_of_gen_ascend : unit -> Def.gen_ascend ifam -> ascend;
      union_of_gen_union : unit -> Def.gen_union ifam -> union;
      family_of_gen_family : unit -> Def.gen_family iper istr -> family;
      couple_of_gen_couple : unit -> Def.gen_couple iper -> couple;
      descend_of_gen_descend : unit -> Def.gen_descend iper -> descend;
      poi : unit -> iper -> person;
      aoi : unit -> iper -> ascend;
      uoi : unit -> iper -> union;
      foi : unit -> ifam -> family;
      coi : unit -> ifam -> couple;
      doi : unit -> ifam -> descend;
      sou : unit -> istr -> string;
      nb_of_persons : unit -> int;
      nb_of_families : unit -> int;
      patch_person : unit -> iper -> person -> unit;
      patch_ascend : unit -> iper -> ascend -> unit;
      patch_union : unit -> iper -> union -> unit;
      patch_family : unit -> ifam -> family -> unit;
      patch_descend : unit -> ifam -> descend -> unit;
      patch_couple : unit -> ifam -> couple -> unit;
      patch_key : unit -> iper -> string -> string -> int -> unit;
      patch_name : unit -> string -> iper -> unit;
      insert_string : unit -> string -> istr;
      commit_patches : unit -> unit;
      commit_notes : unit -> string -> string -> unit;
      is_patched_person : unit -> iper -> bool;
      patched_ascends : unit -> list iper;
      output_consang_tab : unit -> array Adef.fix -> unit;
      delete_family : unit -> ifam -> unit;
      person_of_key : unit -> string -> string -> int -> option iper;
      persons_of_name : unit -> string -> list iper;
      persons_of_first_name : unit -> string_person_index;
      persons_of_surname : unit -> string_person_index;
      base_visible_get : unit -> (person -> bool) -> int -> bool;
      base_visible_write : unit -> unit;
      base_particles : unit -> list string;
      base_strings_of_first_name : unit -> string -> list istr;
      base_strings_of_surname : unit -> string -> list istr;
      load_ascends_array : unit -> unit;
      load_unions_array : unit -> unit;
      load_couples_array : unit -> unit;
      load_descends_array : unit -> unit;
      load_strings_array : unit -> unit;
      persons_array : unit -> (int -> person * int -> person -> unit);
      ascends_array :
        unit ->
          (int -> option ifam * int -> Adef.fix * int -> Adef.fix -> unit *
           option (array Adef.fix));
      base_notes_read : unit -> string -> string;
      base_notes_read_first_line : unit -> string -> string;
      base_notes_are_empty : unit -> string -> bool;
      base_notes_origin_file : unit -> string;
      base_notes_dir : unit -> string;
      base_wiznotes_dir : unit -> string;
      person_misc_names :
        unit -> person -> (person -> list title) -> list string;
      nobtit : unit -> config -> person -> list title;
      p_first_name : unit -> person -> string;
      p_surname : unit -> person -> string;
      date_of_last_change : unit -> string -> float }
  ;
  module C_base :
    sig
      value delete_family : unit -> base -> ifam -> unit;
      value base_strings_of_first_name : unit -> base -> string -> list istr;
      value base_strings_of_surname : unit -> base -> string -> list istr;
      value person_misc_names :
        unit -> base -> person -> (person -> list title) -> list string;
      value nobtit : unit -> base -> config -> person -> list title;
      value p_first_name : unit -> base -> person -> string;
      value p_surname : unit -> base -> person -> string;
    end =
    struct
      value husbands self p =
        let u = self.uoi () (get_key_index p) in
        List.map
          (fun ifam ->
             let cpl = self.coi () ifam in
             let husband = self.poi () (get_father cpl) in
             let husband_surname = self.p_surname () husband in
             let husband_surnames_aliases =
               List.map (self.sou ()) (get_surnames_aliases husband)
             in
             (husband_surname, husband_surnames_aliases))
          (Array.to_list (get_family u))
      ;
      value father_titles_places self p nobtit =
        match get_parents (self.aoi () (get_key_index p)) with
        [ Some ifam ->
            let cpl = self.coi () ifam in
            let fath = self.poi () (get_father cpl) in
            List.map (fun t -> self.sou () t.t_place) (nobtit fath)
        | None -> [] ]
      ;
      value delete_family () self ifam =
        let cpl =
          self.couple_of_gen_couple ()
            (couple (Adef.iper_of_int (-1)) (Adef.iper_of_int (-1)))
        in
        let fam =
          let empty = self.insert_string () "" in
          self.family_of_gen_family ()
            {marriage = codate_None; marriage_place = empty;
             marriage_src = empty; relation = Married; divorce = NotDivorced;
             witnesses = [| |]; comment = empty; origin_file = empty;
             fsources = empty; fam_index = Adef.ifam_of_int (-1)}
        in
        let des = self.descend_of_gen_descend () {children = [| |]} in
        do {
          self.patch_family () ifam fam;
          self.patch_couple () ifam cpl;
          self.patch_descend () ifam des
        }
      ;
      value base_strings_of_first_name () self s =
        base_strings_of_first_name_or_surname self.base_t "first_name"
          (fun p -> p.first_name) s
      ;
      value base_strings_of_surname () self s =
        base_strings_of_first_name_or_surname self.base_t "surname"
          (fun p -> p.surname) s
      ;
      value person_misc_names () self p tit =
        let sou = self.sou () in
        Futil.gen_person_misc_names (sou (get_first_name p))
          (sou (get_surname p)) (sou (get_public_name p))
          (List.map sou (get_qualifiers p)) (List.map sou (get_aliases p))
          (List.map sou (get_first_names_aliases p))
          (List.map sou (get_surnames_aliases p))
          (List.map (Futil.map_title_strings sou) (tit p))
          (if get_sex p = Female then husbands self p else [])
          (father_titles_places self p tit)
      ;
      value nobtit () self conf p =
        let list = get_titles p in
        match Lazy.force conf.allowed_titles with
        [ [] -> list
        | allowed_titles ->
            let list =
              List.fold_right
                (fun t l ->
                   let id = Name.lower (self.sou () t.t_ident) in
                   let pl = Name.lower (self.sou () t.t_place) in
                   if pl = "" then
                     if List.mem id allowed_titles then [t :: l] else l
                   else if
                     List.mem (id ^ "/" ^ pl) allowed_titles ||
                     List.mem (id ^ "/*") allowed_titles
                   then
                     [t :: l]
                   else l)
                list []
            in
            match Lazy.force conf.denied_titles with
            [ [] -> list
            | denied_titles ->
                List.filter
                  (fun t ->
                     let id = Name.lower (self.sou () t.t_ident) in
                     let pl = Name.lower (self.sou () t.t_place) in
                     if List.mem (id ^ "/" ^ pl) denied_titles ||
                        List.mem ("*/" ^ pl) denied_titles
                     then
                       False
                     else True)
                  list ] ]
      ;
      value p_first_name () self p =
        nominative (self.sou () (get_first_name p))
      ;
      value p_surname () self p = nominative (self.sou () (get_surname p));
    end
  ;
end;

value base1 () b base =
  let rec self =
    {base_t = b; close_base () = base.func.cleanup ();
     person_of_gen_person () p =
       Person (map_person_ps (fun p -> p) un_istr p);
     ascend_of_gen_ascend () a = Ascend a; union_of_gen_union () u = Union u;
     family_of_gen_family () f =
       Family (map_family_ps (fun p -> p) un_istr f);
     couple_of_gen_couple () c = Couple c;
     descend_of_gen_descend () d = Descend d;
     poi () i = Person (base.data.persons.get (Adef.int_of_iper i));
     aoi () i = Ascend (base.data.ascends.get (Adef.int_of_iper i));
     uoi () i = Union (base.data.unions.get (Adef.int_of_iper i));
     foi () i = Family (base.data.families.get (Adef.int_of_ifam i));
     coi () i = Couple (base.data.couples.get (Adef.int_of_ifam i));
     doi () i = Descend (base.data.descends.get (Adef.int_of_ifam i));
     sou () = sou b; nb_of_persons () = base.data.persons.len;
     nb_of_families () = base.data.families.len;
     patch_person () ip p =
       match p with
       [ Person p -> base.func.Dbdisk.patch_person ip p
       | _ -> assert False ];
     patch_ascend () ip a =
       match a with
       [ Ascend a -> base.func.Dbdisk.patch_ascend ip a
       | _ -> assert False ];
     patch_union () ip u =
       match u with
       [ Union u -> base.func.Dbdisk.patch_union ip u
       | _ -> failwith "not impl patch_union" ];
     patch_family () ifam f =
       match f with
       [ Family f -> base.func.Dbdisk.patch_family ifam f
       | _ -> failwith "not impl patch_family" ];
     patch_descend () ifam d =
       match d with
       [ Descend d -> base.func.Dbdisk.patch_descend ifam d
       | _ -> failwith "not impl patch_descend" ];
     patch_couple () ifam c =
       match c with
       [ Couple c -> base.func.Dbdisk.patch_couple ifam c
       | _ -> failwith "not impl patch_couple" ];
     patch_key () ip fn sn occ = ();
     patch_name () s ip = base.func.Dbdisk.patch_name s ip;
     insert_string () s = Istr (base.func.Dbdisk.insert_string s);
     commit_patches () = base.func.Dbdisk.commit_patches ();
     commit_notes () = base.func.Dbdisk.commit_notes;
     is_patched_person () ip = base.func.Dbdisk.is_patched_person ip;
     patched_ascends () = base.func.Dbdisk.patched_ascends ();
     output_consang_tab () tab =
       do { eprintf "error Gwdb.output_consang_tab\n"; flush stdout };
     delete_family () = C_base.delete_family () self;
     person_of_key () = base.func.Dbdisk.person_of_key;
     persons_of_name () = base.func.Dbdisk.persons_of_name;
     persons_of_first_name () = Spi base.func.Dbdisk.persons_of_first_name;
     persons_of_surname () = Spi base.func.Dbdisk.persons_of_surname;
     base_visible_get () f = base.data.visible.v_get (fun p -> f (Person p));
     base_visible_write () = base.data.visible.v_write ();
     base_particles () = base.data.particles;
     base_strings_of_first_name () =
       C_base.base_strings_of_first_name () self;
     base_strings_of_surname () = C_base.base_strings_of_surname () self;
     load_ascends_array () = base.data.ascends.load_array ();
     load_unions_array () = base.data.unions.load_array ();
     load_couples_array () = base.data.couples.load_array ();
     load_descends_array () = base.data.descends.load_array ();
     load_strings_array () = base.data.strings.load_array ();
     persons_array () =
       let get i = Person (base.data.persons.get i) in
       let set i =
         fun
         [ Person p -> base.data.persons.set i p
         | Person2 _ _ -> assert False
         | Person2Gen _ _ -> assert False ]
       in
       (get, set);
     ascends_array () =
       let fget i = (base.data.ascends.get i).parents in
       let cget i = (base.data.ascends.get i).consang in
       let cset i v =
         base.data.ascends.set i {(base.data.ascends.get i) with consang = v}
       in
       (fget, cget, cset, None);
     base_notes_read () fnotes = base.data.bnotes.nread fnotes RnAll;
     base_notes_read_first_line () fnotes =
       base.data.bnotes.nread fnotes Rn1Ln;
     base_notes_are_empty () fnotes =
       base.data.bnotes.nread fnotes RnDeg = "";
     base_notes_origin_file () = base.data.bnotes.norigin_file;
     base_notes_dir () = "notes_d"; base_wiznotes_dir () = "wiznotes";
     person_misc_names () = C_base.person_misc_names () self;
     nobtit () = C_base.nobtit () self;
     p_first_name () = C_base.p_first_name () self;
     p_surname () = C_base.p_surname () self;
     date_of_last_change () bname =
       let bdir =
         if Filename.check_suffix bname ".gwb" then bname else bname ^ ".gwb"
       in
       let s =
         try Unix.stat (Filename.concat bdir "patches") with
         [ Unix.Unix_error _ _ _ -> Unix.stat (Filename.concat bdir "base") ]
       in
       s.Unix.st_mtime}
  in
  self
;

value base2 () b db2 =
  let rec self =
    {base_t = b;
     close_base () =
       Hashtbl.iter (fun (f1, f2, f) ic -> close_in ic) db2.cache_chan;
     person_of_gen_person () p =
       Person2Gen db2 (map_person_ps (fun p -> p) un_istr2 p);
     ascend_of_gen_ascend () a = Ascend2Gen db2 a;
     union_of_gen_union () u = Union2Gen db2 u;
     family_of_gen_family () f =
       Family2Gen db2 (map_family_ps (fun p -> p) un_istr2 f);
     couple_of_gen_couple () c = Couple2Gen db2 c;
     descend_of_gen_descend () d = Descend2Gen db2 d;
     poi () i =
       try Person2Gen db2 (Hashtbl.find db2.patches.h_person i) with
       [ Not_found -> Person2 db2 (Adef.int_of_iper i) ];
     aoi () i =
       try Ascend2Gen db2 (Hashtbl.find db2.patches.h_ascend i) with
       [ Not_found -> Ascend2 db2 (Adef.int_of_iper i) ];
     uoi () i =
       try Union2Gen db2 (Hashtbl.find db2.patches.h_union i) with
       [ Not_found -> Union2 db2 (Adef.int_of_iper i) ];
     foi () i =
       try Family2Gen db2 (Hashtbl.find db2.patches.h_family i) with
       [ Not_found -> Family2 db2 (Adef.int_of_ifam i) ];
     coi () i =
       try Couple2Gen db2 (Hashtbl.find db2.patches.h_couple i) with
       [ Not_found -> Couple2 db2 (Adef.int_of_ifam i) ];
     doi () i =
       try Descend2Gen db2 (Hashtbl.find db2.patches.h_descend i) with
       [ Not_found -> Descend2 db2 (Adef.int_of_ifam i) ];
     sou () = sou b; nb_of_persons () = db2.patches.nb_per;
     nb_of_families () = db2.patches.nb_fam;
     patch_person () ip p =
       match p with
       [ Person2Gen _ p ->
           do {
             Hashtbl.replace db2.patches.h_person ip p;
             db2.patches.nb_per :=
               max (Adef.int_of_iper ip + 1) db2.patches.nb_per
           }
       | _ -> assert False ];
     patch_ascend () ip a =
       match a with
       [ Ascend2Gen _ a ->
           do {
             Hashtbl.replace db2.patches.h_ascend ip a;
             db2.patches.nb_per :=
               max (Adef.int_of_iper ip + 1) db2.patches.nb_per
           }
       | _ -> assert False ];
     patch_union () ip u =
       match u with
       [ Union2Gen _ u ->
           do {
             Hashtbl.replace db2.patches.h_union ip u;
             db2.patches.nb_per :=
               max (Adef.int_of_iper ip + 1) db2.patches.nb_per
           }
       | _ -> failwith "not impl patch_union" ];
     patch_family () ifam f =
       match f with
       [ Family2Gen _ f ->
           do {
             Hashtbl.replace db2.patches.h_family ifam f;
             db2.patches.nb_fam :=
               max (Adef.int_of_ifam ifam + 1) db2.patches.nb_fam
           }
       | _ -> failwith "not impl patch_family" ];
     patch_descend () ifam d =
       match d with
       [ Descend2Gen _ d ->
           do {
             Hashtbl.replace db2.patches.h_descend ifam d;
             db2.patches.nb_fam :=
               max (Adef.int_of_ifam ifam + 1) db2.patches.nb_fam
           }
       | _ -> failwith "not impl patch_descend" ];
     patch_couple () ifam c =
       match c with
       [ Couple2Gen _ c ->
           do {
             Hashtbl.replace db2.patches.h_couple ifam c;
             db2.patches.nb_fam :=
               max (Adef.int_of_ifam ifam + 1) db2.patches.nb_fam
           }
       | _ -> failwith "not impl patch_couple" ];
     patch_key () ip fn sn occ =
       do {
         Hashtbl.iter
           (fun key ip1 ->
              if ip = ip1 then Hashtbl.remove db2.patches.h_key key else ())
           db2.patches.h_key;
         let fn = Name.lower (nominative fn) in
         let sn = Name.lower (nominative sn) in
         Hashtbl.replace db2.patches.h_key (fn, sn, occ) ip
       };
     patch_name () s ip =
       let s = Name.crush_lower s in
       let ht = db2.patches.h_name in
       try
         let ipl = Hashtbl.find ht s in
         if List.mem ip ipl then () else Hashtbl.replace ht s [ip :: ipl]
       with
       [ Not_found -> Hashtbl.add ht s [ip] ];
     insert_string () s = Istr2New db2 s;
     commit_patches () =
       let fname = Filename.concat db2.bdir "patches" in
       let oc = open_out_bin (fname ^ "1") in
       do {
         output_string oc magic_patch;
         output_value oc db2.patches;
         close_out oc;
         remove_file (fname ^ "~");
         try Sys.rename fname (fname ^ "~") with [ Sys_error _ -> () ];
         Sys.rename (fname ^ "1") fname
       };
     commit_notes () = failwith "not impl commit_notes";
     is_patched_person () ip =
       let _ =
         if ok_I_know.val then ()
         else do {
           ok_I_know.val := True;
           eprintf "not impl is_patched_person\n";
           flush stderr
         }
       in
       False;
     patched_ascends () =
       let _ = do { eprintf "not impl patched_ascends\n"; flush stderr } in
       [];
     output_consang_tab () tab =
       let dir =
         List.fold_left Filename.concat db2.bdir ["person"; "consang"]
       in
       do {
         Mutil.mkdir_p dir;
         let oc = open_out_bin (Filename.concat dir "data") in
         output_value oc tab;
         close_out oc;
         let oc = open_out_bin (Filename.concat dir "access") in
         let _ : int =
           Iovalue.output_array_access oc (Array.get tab) (Array.length tab) 0
         in
         close_out oc
       };
     delete_family () = C_base.delete_family () self;
     person_of_key () = person2_of_key db2;
     persons_of_name () = persons2_of_name db2;
     persons_of_first_name () = persons_of_first_name_or_surname2 db2 True;
     persons_of_surname () = persons_of_first_name_or_surname2 db2 False;
     base_visible_get () = failwith "not impl visible_get";
     base_visible_write () = failwith "not impl visible_write";
     base_particles () =
       Mutil.input_particles (Filename.concat db2.bdir "particles.txt");
     base_strings_of_first_name () =
       C_base.base_strings_of_first_name () self;
     base_strings_of_surname () = C_base.base_strings_of_surname () self;
     load_ascends_array () =
       do {
         eprintf "*** loading ascends array\n";
         flush stderr;
         let nb = db2.patches.nb_per in
         let nb_ini = db2.patches.nb_per_ini in
         match db2.parents_array with
         [ Some _ -> ()
         | None -> db2.parents_array := Some (parents_array2 db2 nb_ini nb) ];
         match db2.consang_array with
         [ Some _ -> ()
         | None -> db2.consang_array := Some (consang_array2 db2 nb) ]
       };
     load_unions_array () =
       match db2.family_array with
       [ Some _ -> ()
       | None ->
           do {
             eprintf "*** loading unions array\n";
             flush stderr;
             db2.family_array := Some (family_array2 db2)
           } ];
     load_couples_array () =
       do {
         eprintf "*** loading couples array\n";
         flush stderr;
         let nb = db2.patches.nb_fam in
         match db2.father_array with
         [ Some _ -> ()
         | None ->
             let tab =
               load_array2 db2.bdir db2.patches.nb_fam_ini nb "family"
                 "father"
                 (fun ic_dat pos ->
                    do { seek_in ic_dat pos; Iovalue.input ic_dat })
             in
             do {
               Hashtbl.iter (fun i c -> tab.(Adef.int_of_ifam i) := father c)
                 db2.patches.h_couple;
               db2.father_array := Some tab
             } ];
         match db2.mother_array with
         [ Some _ -> ()
         | None ->
             let tab =
               load_array2 db2.bdir db2.patches.nb_fam_ini nb "family"
                 "mother"
                 (fun ic_dat pos ->
                    do { seek_in ic_dat pos; Iovalue.input ic_dat })
             in
             do {
               Hashtbl.iter (fun i c -> tab.(Adef.int_of_ifam i) := mother c)
                 db2.patches.h_couple;
               db2.mother_array := Some tab
             } ]
       };
     load_descends_array () =
       match db2.children_array with
       [ Some _ -> ()
       | None ->
           do {
             eprintf "*** loading descends array\n";
             flush stderr;
             db2.children_array := Some (children_array2 db2)
           } ];
     load_strings_array () = ();
     persons_array () = failwith "not impl persons_array";
     ascends_array () =
       let nb = self.nb_of_persons () in
       let cg_tab =
         match db2.consang_array with
         [ Some tab -> tab
         | None -> consang_array2 db2 nb ]
       in
       let fget i = get_parents (Ascend2 db2 i) in
       let cget i = cg_tab.(i) in
       let cset i v = cg_tab.(i) := v in
       (fget, cget, cset, Some cg_tab);
     base_notes_read () fnotes =
       read_notes (Filename.dirname db2.bdir) fnotes RnAll;
     base_notes_read_first_line () fnotes =
       read_notes (Filename.dirname db2.bdir) fnotes Rn1Ln;
     base_notes_are_empty () fnotes =
       read_notes (Filename.dirname db2.bdir) fnotes RnDeg = "";
     base_notes_origin_file () =
       let fname = Filename.concat db2.bdir "notes_of.txt" in
       match try Some (Secure.open_in fname) with [ Sys_error _ -> None ] with
       [ Some ic ->
           let r = input_line ic in
           do { close_in ic; r }
       | None -> "" ];
     base_notes_dir () = Filename.concat "base_d" "notes_d";
     base_wiznotes_dir () = Filename.concat "base_d" "wiznotes_d";
     person_misc_names () = C_base.person_misc_names () self;
     nobtit () = C_base.nobtit () self;
     p_first_name () = C_base.p_first_name () self;
     p_surname () = C_base.p_surname () self;
     date_of_last_change () bname =
       let bdir =
         if Filename.check_suffix bname ".gwb" then bname else bname ^ ".gwb"
       in
       let s =
         let bdir = Filename.concat bdir "base_d" in
         try Unix.stat (Filename.concat bdir "patches") with
         [ Unix.Unix_error _ _ _ -> Unix.stat bdir ]
       in
       s.Unix.st_mtime}
  in
  self
;

value open_base bname =
  let b = open_base bname in
  match b with
  [ Base base -> base1 () b base
  | Base2 db2 -> base2 () b db2 ]
;

value close_base b = b.close_base ();
value person_of_gen_person b = b.person_of_gen_person ();
value ascend_of_gen_ascend b = b.ascend_of_gen_ascend ();
value union_of_gen_union b = b.union_of_gen_union ();
value family_of_gen_family b = b.family_of_gen_family ();
value couple_of_gen_couple b = b.couple_of_gen_couple ();
value descend_of_gen_descend b = b.descend_of_gen_descend ();
value poi b = b.poi ();
value aoi b = b.aoi ();
value uoi b = b.uoi ();
value foi b = b.foi ();
value coi b = b.coi ();
value doi b = b.doi ();
value sou b = b.sou ();
value nb_of_persons b = b.nb_of_persons ();
value nb_of_families b = b.nb_of_families ();
value patch_person b = b.patch_person ();
value patch_ascend b = b.patch_ascend ();
value patch_union b = b.patch_union ();
value patch_family b = b.patch_family ();
value patch_descend b = b.patch_descend ();
value patch_couple b = b.patch_couple ();
value patch_key b = b.patch_key ();
value patch_name b = b.patch_name ();
value insert_string b = b.insert_string ();
value commit_patches b = b.commit_patches ();
value commit_notes b = b.commit_notes ();
value is_patched_person b = b.is_patched_person ();
value patched_ascends b = b.patched_ascends ();
value output_consang_tab b = b.output_consang_tab ();
value delete_family b = b.delete_family ();
value person_of_key b = b.person_of_key ();
value persons_of_name b = b.persons_of_name ();
value persons_of_first_name b = b.persons_of_first_name ();
value persons_of_surname b = b.persons_of_surname ();
value base_visible_get b = b.base_visible_get ();
value base_visible_write b = b.base_visible_write ();
value base_particles b = b.base_particles ();
value base_strings_of_first_name b = b.base_strings_of_first_name ();
value base_strings_of_surname b = b.base_strings_of_surname ();
value load_ascends_array b = b.load_ascends_array ();
value load_unions_array b = b.load_unions_array ();
value load_couples_array b = b.load_couples_array ();
value load_descends_array b = b.load_descends_array ();
value load_strings_array b = b.load_strings_array ();
value persons_array b = b.persons_array ();
value ascends_array b = b.ascends_array ();
value base_notes_read b = b.base_notes_read ();
value base_notes_read_first_line b = b.base_notes_read_first_line ();
value base_notes_are_empty b = b.base_notes_are_empty ();
value base_notes_origin_file b = b.base_notes_origin_file ();
value base_notes_dir b = b.base_notes_dir ();
value base_wiznotes_dir b = b.base_wiznotes_dir ();
value person_misc_names b = b.person_misc_names ();
value nobtit conf b = b.nobtit () conf;
value p_first_name b = b.p_first_name ();
value p_surname b = b.p_surname ();
value date_of_last_change s b = b.date_of_last_change () s;

value base_of_dsk_base base = base1 () (Base base) base;
value apply_as_dsk_base f base = apply_as_dsk_base f base.base_t;

(* end of pretty printed code *)

(**)

(* Traces of changes; this is not correct because it supposes that calls
   to poi, aoi, etc concerns the modified persons. However the code is
   just commented, not deleted because it can be reused later to display
   changes in persons and in families. *)

(* but... two functions kept to preserve interface: *)

value record_changes_in_file v = ();
value commit_patches _ base = commit_patches base;

(*
value trace_patches_file = ref "";
value record_changes_in_file v = trace_patches_file.val := v;

value ini_per = Hashtbl.create 1;
value ini_uni = Hashtbl.create 1;
value ini_fam = Hashtbl.create 1;
value ini_cpl = Hashtbl.create 1;
value ini_des = Hashtbl.create 1;

value res_per = Hashtbl.create 1;
value res_uni = Hashtbl.create 1;
value res_fam = Hashtbl.create 1;
value res_cpl = Hashtbl.create 1;
value res_des = Hashtbl.create 1;

value string_escaped s =
  let n = ref 0 in
  do {
    for i = 0 to String.length s - 1 do {
      n.val :=
        n.val +
          (match String.unsafe_get s i with
           [ '\\' | '\n' | '\t' -> 2
           | c -> 1 ])
    };
    if n.val = String.length s then s
    else do {
      let s' = String.create n.val in
      n.val := 0;
      for i = 0 to String.length s - 1 do {
        match String.unsafe_get s i with
        [ '\\' as c -> do {
            String.unsafe_set s' n.val '\\';
            incr n;
            String.unsafe_set s' n.val c
          }
        | '\n' -> do {
            String.unsafe_set s' n.val '\\';
            incr n;
            String.unsafe_set s' n.val 'n'
          }
        | '\t' -> do {
            String.unsafe_set s' n.val '\\';
            incr n;
            String.unsafe_set s' n.val 't'
          }
        | c ->
            String.unsafe_set s' n.val c ];
        incr n
      };
      s'
    }
  }
;

value code_dmy d =
  if d.day = 0 then
    if d.month = 0 then sprintf "%4d" d.year
    else sprintf "%4d-%02d" d.year d.month
  else sprintf "%4d-%02d-%02d" d.year d.month d.day
;

value string_of_prec_dmy s d =
  match d.prec with
  [ Sure -> s
  | About -> "~" ^ s
  | Before -> "<" ^ s
  | After -> ">" ^ s
  | Maybe -> "?" ^ s
  | OrYear z -> s ^ " " ^ "or" ^ " " ^ string_of_int z
  | YearInt z -> "bet " ^ s ^ " and " ^ string_of_int z ]
;

value string_of_dmy d = string_of_prec_dmy (code_dmy d) d;

value string_of_date =
  fun
  [ Dgreg d _ -> string_of_dmy d
  | Dtext t -> "(" ^ t ^ ")" ]
;

value string_of_codate if_d if_nd v =
  match Adef.od_of_codate v with
  [ Some d -> if_d ^ string_of_date d
  | None -> if_nd ]
;

value string_of_per (fn, sn, occ, ip) =
  if Adef.int_of_iper ip < 0 then "(nobody)"
  else
    sprintf "%s.%d %s" (if fn = "" then "?" else fn)
      (if fn = "" || sn = "" then Adef.int_of_iper ip else occ)
      (if sn = "" then "?" else sn)
;

value string_of_fam (fam, cpl, des) ifam =
  if Adef.int_of_ifam ifam < 0 then "(deleted)"
  else
    let fath = Adef.father cpl in
    let moth = Adef.mother cpl in
    sprintf "%s + %s" (string_of_per fath) (string_of_per moth)
;

value fill_n = 21;

value fill s =
  let slen = String.length s in
  let f = if slen < fill_n then String.make (fill_n - slen) '.' else "." in
  s ^ f
;

value print_string_field oc tab name get ref v =
  let ref = get ref in
  let v = get v in
  if v <> ref then fprintf oc "    %s%s%s\n" tab (fill name)
    (string_escaped v)
  else ()
;

value print_codate_field oc tab name get ref v =
  let ref = get ref in
  let v = get v in
  if v <> ref then
    fprintf oc "    %s%s%s\n" tab (fill name) (string_of_codate "" "" v)
  else ()
;

value print_iper_field oc tab name get v = do {
  let (fn, sn, occ, v) = get v in
  fprintf oc "    %s%s" tab (fill name);
  if Adef.int_of_iper v < 0 then fprintf oc ""
  else fprintf oc "%s" (string_of_per (fn, sn, occ, v));
  fprintf oc "\n";
};

type diff_kind = [ New | Bef | Aft ];

value print_list_field print_item oc tab name1 name get ref v dk =
  let ref = get ref in
  let v = get v in
  if v <> ref then
    if v = [] then fprintf oc "    %s%s\n" tab (fill name1)
    else
      let name = if List.length v = 1 then name1 else name in
      let a1 = Array.of_list ref in
      let a2 = Array.of_list v in
      let d2 =
        match dk with
        [ New -> [| |]
        | Bef -> snd (Diff.f a1 a2)
        | Aft -> fst (Diff.f a2 a1) ]
      in
      for i = 0 to Array.length a2 - 1 do {
        fprintf oc "    %s%s" tab (fill (if i = 0 then name else ""));
        print_item oc a2.(i);
        match dk with
        [ New -> ()
        | Bef -> if d2.(i) then fprintf oc " -" else ()
        | Aft -> if d2.(i) then fprintf oc " +" else () ];
        fprintf oc "\n";
      }
  else ()
;

value print_string_list_field =
  print_list_field (fun oc s -> fprintf oc "%s" (string_escaped s))
;

value print_iper_list_field =
  print_list_field
    (fun oc (fn, sn, occ, ip) ->
       if Adef.int_of_iper ip < 0 then fprintf oc ""
       else fprintf oc "%s" (string_of_per (fn, sn, occ, ip)))
;

value print_diff_per oc tab refpu pu dk = do {
  let (ref, refu) = refpu in
  let (p, u) = pu in
  print_string_field oc tab "first_name" (fun p -> p.first_name) ref p;
  print_string_field oc tab "surname" (fun p -> p.surname) ref p;
  if p.occ <> ref.occ then fprintf oc "    %s%s%d\n" tab (fill "occ") p.occ
  else ();
  print_string_field oc tab "image" (fun p -> p.image) ref p;
  print_string_field oc tab "public_name" (fun p -> p.public_name) ref p;
  print_string_list_field oc tab "qualifier" "qualifiers"
    (fun p -> p.qualifiers) ref p dk;
  print_string_list_field oc tab "alias" "aliases" (fun p -> p.aliases) ref p
    dk;
  print_string_list_field oc tab "first_name_alias" "first_names_aliases"
    (fun p -> p.first_names_aliases) ref p dk;
  print_string_list_field oc tab "surname_alias" "surnames_aliases"
    (fun p -> p.surnames_aliases) ref p dk;
  print_list_field
    (fun oc tit ->
       fprintf oc "%s/%s/%s/%s/%s/%s"
         tit.t_ident tit.t_place
         (string_of_codate "" "" tit.t_date_start)
         (string_of_codate "" "" tit.t_date_end)
         (if tit.t_nth = 0 then "" else string_of_int tit.t_nth)
         (match tit.t_name with
          [ Tmain -> "*" | Tname n -> n | Tnone -> "" ]))
    oc tab "title" "titles" (fun p -> p.titles) ref p dk;
  print_list_field
    (fun oc r ->
       fprintf oc "%s/%s/%s/%s"
         (match r.r_type with
          [ Adoption -> "adop"
          | Recognition -> "reco"
          | CandidateParent -> "candp"
          | GodParent -> "godp"
          | FosterParent -> "fostp" ])
         (match r.r_fath with
          [ Some p -> string_of_per p
          | None -> "" ])
         (match r.r_moth with
          [ Some p -> string_of_per p
          | None -> "" ])
         r.r_sources)
    oc tab "relation" "relations" (fun p -> p.rparents) ref p dk;
  print_string_field oc tab "occupation" (fun p -> p.occupation) ref p;
  if p.sex <> ref.sex then
    fprintf oc "    %s%s%s\n" tab (fill "sex")
      (match p.sex with [ Male -> "M" | Female -> "F" | Neuter -> "?" ])
  else ();
  if p.access <> ref.access then
    fprintf oc "    %s%s%s\n" tab (fill "access")
      (match p.access with
       [ IfTitles -> "if-titles" | Public -> "public" | Private -> "private" ])
  else ();
  print_codate_field oc tab "birth_date" (fun p -> p.birth) ref p;
  print_string_field oc tab "birth_place" (fun p -> p.birth_place) ref p;
  print_string_field oc tab "birth_src" (fun p -> p.birth_src) ref p;
  print_codate_field oc tab "baptism_date" (fun p -> p.baptism) ref p;
  print_string_field oc tab "baptism_place" (fun p -> p.baptism_place) ref p;
  print_string_field oc tab "baptism_src" (fun p -> p.baptism_src) ref p;
  if p.death <> ref.death then
    fprintf oc "    %s%s%s\n" tab (fill "death")
      (match p.death with
       [ NotDead -> "not dead"
       | Death dr cd ->
           let drs =
             match dr with
             [ Killed -> " (killed)"
             | Murdered -> " (murdered)"
             | Executed -> " (executed)"
             | Disappeared -> " (disappeared)"
             | Unspecified -> "" ] 
           in
           string_of_date (Adef.date_of_cdate cd) ^ drs
       | DeadYoung -> "dead young"
       | DeadDontKnowWhen -> "dead"
       | DontKnowIfDead -> "" ])
  else ();
  print_string_field oc tab "death_place" (fun p -> p.death_place) ref p;
  print_string_field oc tab "death_src" (fun p -> p.death_src) ref p;
  if p.burial <> ref.burial then
    fprintf oc "    %s%s\n" tab
      (match p.burial with
       [ UnknownBurial -> fill "burial"
       | Buried cd -> fill "buried" ^ string_of_codate " " "" cd
       | Cremated cd -> fill "cremated" ^ string_of_codate " " "" cd ])
  else ();
  print_string_field oc tab "burial_place" (fun p -> p.burial_place) ref p;
  print_string_field oc tab "burial_src" (fun p -> p.burial_src) ref p;
  print_string_field oc tab "notes" (fun p -> p.notes) ref p;
  print_string_field oc tab "sources" (fun p -> p.psources) ref p;
  print_list_field (fun oc spouse -> fprintf oc "%s" (string_of_per spouse))
    oc tab "union" "unions" (fun (_, u) -> Array.to_list u.family)
    refpu pu dk;
};

value print_diff_fam oc tab parents_already_printed ref fam dk = do {
  if parents_already_printed then ()
  else do {
    print_iper_field oc tab "father" (fun (_, c, _) -> Adef.father c) fam;
    print_iper_field oc tab "mother" (fun (_, c, _) -> Adef.mother c) fam;
  };
  print_iper_list_field oc tab "child" "children"
    (fun (_, _, d) -> Array.to_list d.children) ref fam dk;
  print_codate_field oc tab "marriage_date" (fun (f, _, _) -> f.marriage)
    ref fam;
  print_string_field oc tab "marriage_place"
    (fun (f, _, _) -> f.marriage_place) ref fam;
  print_string_field oc tab "marriage_src"
    (fun (f, _, _) -> f.marriage_src) ref fam;
  let (f, _, _) = fam in
  let (rf, _, _) = ref in
  print_iper_list_field oc tab "witness" "witnesses"
    (fun (f, _, _) -> Array.to_list f.witnesses) ref fam dk;
  if f.relation <> rf.relation then
    fprintf oc "    %s%s\n" tab
      (match f.relation with
       [ Married -> "married"
       | NotMarried -> "not married"
       | Engaged -> "engaged"
       | NoSexesCheckNotMarried -> "not married (no sexes check)"
       | NoMention -> "-"
       | NoSexesCheckMarried -> "married (no sexes check)" ])
  else ();
  if f.divorce <> rf.divorce then
    fprintf oc "    %s... (divorce)\n" tab
  else ();
  print_string_field oc tab "comment" (fun (f, _, _) -> f.comment) ref fam;
  print_string_field oc tab "origin_file" (fun (f, _, _) -> f.origin_file)
    ref fam;
  print_string_field oc tab "sources" (fun (f, _, _) -> f.fsources) ref fam;
};

module IpSet = Set.Make (struct type t = iper; value compare = compare; end);
module IfSet = Set.Make (struct type t = ifam; value compare = compare; end);

value default_per =
  {first_name = ""; surname = ""; occ = 0; image = "";
   first_names_aliases = []; surnames_aliases = []; public_name = "";
   qualifiers = []; aliases = []; titles = []; rparents = []; related = [];
   occupation = ""; sex = Neuter; access = IfTitles;
   birth = Adef.codate_None; birth_place = ""; birth_src = "";
   baptism = Adef.codate_None; baptism_place = ""; baptism_src = "";
   death = DontKnowIfDead; death_place = ""; death_src = "";
   burial = UnknownBurial; burial_place = ""; burial_src = ""; notes = "";
   psources = ""; key_index = Adef.iper_of_int 0}
;
value default_uni = {family = [| |]};
value default_pu = (default_per, default_uni);

value default_fam =
  {marriage = Adef.codate_None; marriage_place = ""; marriage_src = "";
   witnesses = [| |]; relation = Married; divorce = NotDivorced;
   comment = ""; origin_file = ""; fsources = "";
   fam_index = Adef.ifam_of_int 0}
;
value default_cpl =
  couple (("", "", 0, Adef.iper_of_int (-1)))
    (("", "", 0, Adef.iper_of_int (-1)))
;
value default_des = {children = [| |]};
value default_fcd = (default_fam, default_cpl, default_des);

value person_key base ht_per ip =
  if Adef.int_of_iper ip < 0 then ("", "", 0, ip)
  else
    let p =
      match try Some (Hashtbl.find ht_per ip) with [ Not_found -> None ] with
      [ Some p -> p
      | None -> poi base ip ]
    in
    (Name.lower (nominative (sou base (get_first_name p))),
     Name.lower (nominative (sou base (get_surname p))),
     get_occ p, ip)
;

value commit_patches confo base = do {
  if trace_patches_file.val <> "" then do {
    let oc =
      open_out_gen [Open_wronly; Open_append; Open_creat] 0o666
        trace_patches_file.val
    in
    match confo with
    [ Some conf ->
        let (hh, mm, ss) = conf.time in
        fprintf oc "\ncommit %4d-%02d-%02d %02d:%02d:%02d \"%s\"%s\n"
          conf.today.year conf.today.month conf.today.day hh mm ss conf.user
          (try " " ^ List.assoc "m" conf.env with [ Not_found -> "" ])
    | None -> () ];
    let per_set =
      let set = IpSet.empty in
      let set = Hashtbl.fold (fun ip _ -> IpSet.add ip) res_per set in
      let set = Hashtbl.fold (fun ip _ -> IpSet.add ip) res_uni set in
      set
    in
    let fam_set =
      let set = IfSet.empty in
      let set = Hashtbl.fold (fun ip _ -> IfSet.add ip) res_fam set in
      let set = Hashtbl.fold (fun ip _ -> IfSet.add ip) res_cpl set in
      let set = Hashtbl.fold (fun ip _ -> IfSet.add ip) res_des set in
      set
    in
    IfSet.iter
      (fun ifam -> do {
         let is_new =
           not
             (Hashtbl.mem ini_fam ifam || Hashtbl.mem ini_cpl ifam ||
              Hashtbl.mem ini_des ifam)
         in
         let fcd_from_ht (ht_fam, ht_cpl, ht_des) =
           (try
              map_family_ps (person_key base ini_per) (sou base)
                (gen_family_of_family (Hashtbl.find ht_fam ifam))
            with
            [ Not_found -> default_fam ],
            try
              map_couple_p False (person_key base ini_per)
                (gen_couple_of_couple (Hashtbl.find ht_cpl ifam))
            with
            [ Not_found -> default_cpl ],
            try
              map_descend_p (person_key base ini_per)
                (gen_descend_of_descend (Hashtbl.find ht_des ifam))
            with
            [ Not_found -> default_des ])
         in
         let fcd2 = fcd_from_ht (res_fam, res_cpl, res_des) in
         if is_new then do {
           fprintf oc "\n  family = %s (new)\n" (string_of_fam fcd2 ifam);
           print_diff_fam oc "" True default_fcd fcd2 New;
         }
         else do {
           let fcd1 = fcd_from_ht (ini_fam, ini_cpl, ini_des) in
           let s1 = string_of_fam fcd1 ifam in
           let s2 = string_of_fam fcd2 ifam in
           fprintf oc "\n  family%s\n" (if s1 = s2 then " = " ^ s1 else "");
           fprintf oc "    before\n";
           print_diff_fam oc "  " (s1 = s2) fcd2 fcd1 Bef;
           fprintf oc "    after\n";
           print_diff_fam oc "  " (s1 = s2) fcd1 fcd2 Aft;
         }
       })
      fam_set;
    IpSet.iter
      (fun ip -> do {
         let is_new =
           not (Hashtbl.mem ini_per ip || Hashtbl.mem ini_uni ip)
         in
         let (fn, sn, occ, _) =
           person_key base (if is_new then res_per else ini_per) ip
         in
         fprintf oc "\n  person = %s%s\n" (string_of_per (fn, sn, occ, ip))
           (if is_new then " (new)" else "");
         let spouse ip cpl =
           let s = get_father cpl in
           if ip = s then get_mother cpl else s
         in
         let pu_from_ht (ht_per, ht_uni) =
           (try
              map_person_ps (person_key base ini_per) (sou base)
                (gen_person_of_person
                   (try Hashtbl.find ht_per ip with
                    [ Not_found ->
                        if is_new then raise Not_found else poi base ip ]))
            with
            [ Not_found -> default_per ],
            try
              map_union_f
                (fun ifam ->
                   person_key base ini_per (spouse ip (coi base ifam)))
                (gen_union_of_union
                   (try Hashtbl.find ht_uni ip with
                    [ Not_found ->
                        if is_new then raise Not_found else uoi base ip ]))
            with
            [ Not_found -> default_uni ])
         in
         let pu2 = pu_from_ht (res_per, res_uni) in
         if is_new then print_diff_per oc "" default_pu pu2 New
         else do {
           let pu1 = pu_from_ht (ini_per, ini_uni) in
           fprintf oc "    before\n";
           print_diff_per oc "  " pu2 pu1 Bef;
           fprintf oc "    after\n";
           print_diff_per oc "  " pu1 pu2 Aft;
         }
       })
      per_set;
    close_out oc;
  }
  else ();
  commit_patches base;
};

value poi base i = do {
  let p = poi base i in
  if trace_patches_file.val <> "" then do {
    if Hashtbl.mem ini_per i || Hashtbl.mem res_per i then ()
    else Hashtbl.add ini_per i p;
  }
  else ();
  p
};

value uoi base i = do {
  let u = uoi base i in
  if trace_patches_file.val <> "" then do {
    if Hashtbl.mem ini_uni i || Hashtbl.mem res_uni i then ()
    else Hashtbl.add ini_uni i u;
  }
  else ();
  u
};

value foi base i = do {
  let f = foi base i in
  if trace_patches_file.val <> "" then do {
    if Hashtbl.mem ini_fam i || Hashtbl.mem res_fam i then ()
    else Hashtbl.add ini_fam i f;
  }
  else ();
  f
};

value coi base i = do {
  let c = coi base i in
  if trace_patches_file.val <> "" then do {
    if Hashtbl.mem ini_cpl i || Hashtbl.mem res_cpl i then ()
    else Hashtbl.add ini_cpl i c;
  }
  else ();
  c
};

value doi base i = do {
  let d = doi base i in
  if trace_patches_file.val <> "" then do {
    if Hashtbl.mem ini_des i || Hashtbl.mem res_des i then ()
    else Hashtbl.add ini_des i d;
  }
  else ();
  d
};

value patch_person base ip p = do {
  if trace_patches_file.val <> "" then Hashtbl.replace res_per ip p else ();
  patch_person base ip p;
};

value patch_union base ip u = do {
  if trace_patches_file.val <> "" then Hashtbl.replace res_uni ip u else ();
  patch_union base ip u;
};

value patch_family base ifam f = do {
  if trace_patches_file.val <> "" then Hashtbl.replace res_fam ifam f else ();
  patch_family base ifam f;
};

value patch_descend base ifam d = do {
  if trace_patches_file.val <> "" then Hashtbl.replace res_des ifam d else ();
  patch_descend base ifam d;
};

value patch_couple base ifam c = do {
  if trace_patches_file.val <> "" then Hashtbl.replace res_cpl ifam c else ();
  patch_couple base ifam c;
};
*)
