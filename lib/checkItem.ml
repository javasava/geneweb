open Def
open Gwdb

type base_error = person error
type base_warning = (iper, person, ifam, family, title, pers_event, fam_event) warning
type base_misc = (person, family, title) misc

(* Constants used for computing the warnings. *)
let max_age_btw_cpl = 50
let max_days_btw_sibl = 10
let max_month_btw_sibl = 7
let lim_date_death = 1900
let max_death_after_lim_date_death = 105
let max_death_before_lim_date_death = 100
let min_parent_age = 11
let max_father_age = 70
let max_mother_age = 55
let min_age_marriage = 12
let max_age_marriage = 100
let max_siblings_gap = 50

(* Check if d1 < d2 *)
let strictly_before_dmy d1 d2 =
  match Date.compare_dmy_opt ~strict:true d1 d2 with
  | Some x -> x < 0
  | None -> false

let strictly_before d1 d2 =
  match d1, d2 with
  | Dgreg (d1, _), Dgreg (d2, _) -> strictly_before_dmy d1 d2
  | _ -> false

let strictly_after_dmy d1 d2 =
  match Date.compare_dmy_opt ~strict:true d1 d2 with
  | Some x -> x > 0
  | None -> false

let strictly_after d1 d2 =
  match d1, d2 with
  | Dgreg (d1, _), Dgreg (d2, _) -> strictly_after_dmy d1 d2
  | _ -> false

let strictly_younger age year =
  match age.prec with
  | After -> false
  | Sure | About | Maybe
  | Before | OrYear _ | YearInt _ -> age.year < year

let strictly_older age year =
  match age.prec with
  | Before -> false
  | Sure | About | Maybe
  | After | OrYear _ | YearInt _ -> age.year > year

let odate = function
  | Some (Dgreg (d, _)) -> Some d
  | Some (Dtext _) | None -> None

let obirth x =
  get_birth x |> Adef.od_of_cdate |> odate

let title_dates warning p t =
  let t_date_start = Adef.od_of_cdate t.t_date_start in
  let t_date_end = Adef.od_of_cdate t.t_date_end in
  match t_date_start, t_date_end with
  | None, None -> ()
  | Some d1, Some d2 when strictly_after d1 d2 -> warning (TitleDatesError (p, t))
  | _ ->
    match Adef.od_of_cdate (get_birth p) with
    | None -> ()
    | Some d1 ->
      match t_date_start with
      | Some d -> if strictly_after d1 d then warning (TitleDatesError (p, t))
      | None -> match t_date_end with
        | Some d -> if strictly_after d1 d then warning (TitleDatesError (p, t))
        | None -> ()

let check_person_age warning p =
  let aux d1 d2 =
    Date.time_elapsed_opt d1 d2 |> Option.iter @@ fun a ->
    if a.year < 0 then warning (BirthAfterDeath p)
    else if d2.year > lim_date_death then begin
      if strictly_older a max_death_after_lim_date_death
      then warning (DeadOld (p, a))
    end else if strictly_older a max_death_before_lim_date_death
    then warning (DeadOld (p, a))
  in
  (* On pourrait faire un calcul sur la descendance ou l'ascendance si  *)
  (* on ne trouve rien ... mais c'est peut être un peu trop gourmand    *)
  (* juste pour un warning ?                                            *)
  match Date.date_of_death (get_death p) with
  | Some (Dgreg (d2, _)) ->
    begin
      match Adef.od_of_cdate (get_birth p) with
      | Some (Dgreg (d, _)) -> aux d d2
      | _ -> match Adef.od_of_cdate (get_baptism p) with
        | Some (Dgreg (d, _)) -> aux d d2
        | Some (Dtext _) | None -> ()
    end
  | _ -> ()

let try_to_fix_relation_sex base warning p_ref =
  let p_index = Some (get_iper p_ref) in
  let fixed = ref 0 in
  let not_fixed = ref 0 in
  let changed_related =
    List.fold_right
      (fun ip changed_related ->
         let p = poi base ip in
         let (rparents, changed, not_changed) =
           List.fold_right
             (fun rel (rparents, changed, not_changed) ->
                let (rel, changed, not_changed) =
                  match p_index = rel.r_fath, p_index = rel.r_moth with
                    true, false ->
                      if get_sex p_ref = Female then
                        match rel.r_moth with
                          Some ip ->
                            let oth_p = poi base ip in
                            if get_sex oth_p = Male then
                              let rel =
                                {rel with r_fath = rel.r_moth;
                                 r_moth = p_index}
                              in
                              rel, changed + 1, not_changed
                            else rel, changed, not_changed + 1
                        | None ->
                            let rel =
                              {rel with r_fath = None; r_moth = p_index}
                            in
                            rel, changed + 1, not_changed
                      else rel, changed, not_changed
                  | false, true ->
                      if get_sex p_ref = Male then
                        match rel.r_fath with
                          Some ip ->
                            let oth_p = poi base ip in
                            if get_sex oth_p = Female then
                              let rel =
                                {rel with r_moth = rel.r_fath;
                                 r_fath = p_index}
                              in
                              rel, changed + 1, not_changed
                            else rel, changed, not_changed + 1
                        | None ->
                            let rel =
                              {rel with r_moth = None; r_fath = p_index}
                            in
                            rel, changed + 1, not_changed
                      else rel, changed, not_changed
                  | false, false -> rel, changed, not_changed
                  | true, true -> rel, changed, not_changed + 1
                in
                rel :: rparents, changed, not_changed)
             (get_rparents p) ([], 0, 0)
         in
         fixed := !fixed + changed;
         not_fixed := !not_fixed + not_changed ;
         if changed > 0 then (ip, p, None, Some rparents) :: changed_related
         else changed_related)
      (get_related p_ref) []
  in
  warning (IncoherentSex (p_ref, !fixed, !not_fixed));
  if !fixed > 0 then Some changed_related else None

let related_sex_is_coherent base warning p_ref =
  let p_index = Some (get_iper p_ref) in
  let merge_sex g1 g2 =
    match g1, g2 with
      Some Male, Some Male -> Some Male
    | Some Female, Some Female -> Some Female
    | Some Neuter, Some g -> Some g
    | Some g, Some Neuter -> Some g
    | _ -> None
  in
  let check_sex sex rparents =
    List.fold_left
      (fun g rel ->
         match p_index = rel.r_fath, p_index = rel.r_moth with
           true, false -> merge_sex g (Some Male)
         | false, true -> merge_sex g (Some Female)
         | false, false -> g
         | true, true -> None)
      sex rparents
  in
  let new_sex =
    List.fold_left
      (fun g ip -> let p = poi base ip in check_sex g (get_rparents p))
      (Some (get_sex p_ref)) (get_related p_ref)
  in
  match new_sex with
    Some g ->
      if get_sex p_ref != g then
        Some [get_iper p_ref, p_ref, Some g, None]
      else None
  | None -> try_to_fix_relation_sex base warning p_ref

let check_difference_age_between_cpl warning fath moth =
  let find_date p =
    match Adef.od_of_cdate (get_birth p) with
    | Some (Dgreg (d, _)) -> Some d
    | _ -> match Adef.od_of_cdate (get_baptism p) with
      | Some (Dgreg (d, _)) -> Some d
      | _ -> None
  in
  match find_date fath with
  | None -> ()
  | Some d1 ->
    match find_date moth with
    | None -> ()
    | Some d2 ->
      (if d1.year < d2.year then Date.time_elapsed_opt d1 d2
       else Date.time_elapsed_opt d2 d1)
      |> Option.iter @@ fun a ->
      if strictly_older a max_age_btw_cpl
      then warning (BigAgeBetweenSpouses (fath, moth, a))

(*
 * Semi sort children by birth dates.
 * If all children have birth dates, no problem.
 * Otherwise, sorting groups of consecutive children who have dates.
 * In not possible cases, try to keep order of children of same sex.
 *   ex: G1, B2 being resp. girl and boy with date(G1) < date(B2)
 *       and G and B begin resp. girls boys without dates
 *     if order is ... B2 B B B G1 ... it becomes ... G1 B2 B B B ...
 *     if order is ... B2 G G G G1 ... it becomes ... G G G G1 B2 ...
 *     if order is ... B2 G B G G1 ... no change (a warning appears).
 *)

let semi_sort base a before comp di =
  let rec loop i =
    if i < 0 || i >= Array.length a then ()
    else
      let p1 = poi base a.(i) in
      let d1 =
        match Adef.od_of_cdate (get_birth p1) with
          Some d1 -> Some d1
        | None -> Adef.od_of_cdate (get_baptism p1)
      in
      match d1 with
        Some d1 ->
          let rec loop_j sex_interm_sib j =
            if j < 0 || j >= Array.length a then loop (i + di)
            else
              let p2 = poi base a.(j) in
              let d2 =
                match Adef.od_of_cdate (get_birth p2) with
                  Some d2 -> Some d2
                | None -> Adef.od_of_cdate (get_baptism p2)
              in
              match d2 with
                Some d2 ->
                  if comp d1 d2 then
                    let j =
                      match sex_interm_sib with
                        Some s ->
                          if s = get_sex p1 then None
                          else if s = get_sex p2 then Some j
                          else None
                      | None -> Some j
                    in
                    match j with
                      Some j ->
                        let k =
                          let rec loop_k k =
                            if k < 0 || k >= Array.length a then k + di
                            else
                              let p3 = poi base a.(k) in
                              let d3 =
                                match Adef.od_of_cdate (get_birth p3) with
                                  Some d3 -> Some d3
                                | None -> Adef.od_of_cdate (get_baptism p3)
                              in
                              match d3 with
                                Some d3 ->
                                  if comp d1 d3 then loop_k (k - di)
                                  else k + di
                              | None -> k + di
                          in
                          loop_k (j - di)
                        in
                        begin match !before with
                          Some _ -> ()
                        | None -> before := Some (Array.copy a)
                        end;
                        let ip = a.(i) in
                        begin let rec loop_up j =
                          if j = k then ()
                          else begin a.(j) <- a.(j-di); loop_up (j - di) end
                        in
                          loop_up i
                        end;
                        a.(k) <- ip;
                        loop (i + di)
                    | None -> loop (i + di)
                  else loop (i + di)
              | None ->
                  match sex_interm_sib with
                    Some s ->
                      if s = get_sex p2 then loop_j sex_interm_sib (j - di)
                      else loop (i + di)
                  | None -> loop_j (Some (get_sex p2)) (j - di)
          in
          loop_j None (i - di)
      | None -> loop (i + di)
  in
  loop

let sort_children base children =
  let before = ref None in
  semi_sort base children before strictly_before 1 1;
  semi_sort base children before strictly_after (~-1) 1;
  semi_sort base children before strictly_before 1 1;
  match !before with
    Some b -> Some (b, children)
  | None -> None

let changed_marriages_order base warning p =
  let b = Array.copy (get_family p) in
  (* Astuce : on construire un tableau identique à la famille dans *)
  (* lequel on remplace toutes les dates inconnues par la dernière *)
  (* date maximale que l'on ait vu.                                *)
  (* Exemple : Ma (mariage sans date), et M3 après M1              *)
  (* ordre initial Ma M5 Mb M3 M1 ... devient Ma M1 M3 M5 Mb       *)
  let (_, a) =
    Array.fold_left
      (fun (max_date, tab) ifam ->
         let fam = foi base ifam in
         let date =
           match Adef.od_of_cdate (get_marriage fam) with
             Some d -> Some d
           | None -> max_date
         in
         let max_date =
           match date, max_date with
             Some d1, Some d2 ->
               if Date.compare_date d1 d2 = 1 then Some d1 else Some d2
           | Some d1, None -> Some d1
           | _ -> max_date
         in
         max_date, Array.append tab [| ifam, date |])
      (None, [| |]) (get_family p)
  in
  Array.stable_sort
    (fun (_f1, d1) (_f2, d2) ->
       match d1, d2 with
         Some d1, Some d2 -> Date.compare_date d1 d2
       | _ -> 0)
    a;
  let a = Array.map (fun (f, _) -> f) a in
  if a <> b then
    begin
      warning (ChangedOrderOfMarriages (p, b, a));
      let rec loop i fam =
        if i = Array.length fam then ()
        else begin fam.(i) <- a.(i); loop (i + 1) fam end
      in
      loop 0 (get_family p)
    end

let close_siblings warning x np ifam =
  match np with
  | Some (elder, d1) ->
    begin match odate @@ Adef.od_of_cdate (get_birth x) with
      | Some d2 ->
        Date.time_elapsed_opt d1 d2 |> Option.iter @@ fun d ->
        (* On vérifie les jumeaux ou naissances proches. *)
        if d.year = 0
        && (d.month < max_month_btw_sibl)
        && (d.month <> 0 || d.day >= max_days_btw_sibl)
        then warning (CloseChildren (ifam, elder, x))
      | None -> ()
    end
  | None -> ()

let born_after_his_elder_sibling warning x b np ifam des =
  match np with
  | None -> ()
  | Some (elder, d1) ->
    match b with
    | Some d2 ->
      if strictly_after_dmy d1 d2 then
        warning (ChildrenNotInOrder (ifam, des, elder, x))
    | None -> match odate @@ Date.date_of_death (get_death x) with
      | Some d2 ->
        if strictly_after_dmy d1 d2 then
          warning (ChildrenNotInOrder (ifam, des, elder, x))
      | None -> ()

let siblings_gap gap child = function
  | None -> gap
  | Some b ->
    match gap with
    | None -> Some ((b, child), (b, child))
    | Some ((min, minp), (max, maxp)) ->
      Some
        ( (if strictly_before_dmy b min then (b, child) else (min, minp))
        , (if strictly_after_dmy b max then (b, child) else (max, maxp)) )

let child_born_after_his_parent warning x parent =
  match Adef.od_of_cdate (get_birth parent) with
  | Some (Dgreg (g1, _)) ->
    begin match Adef.od_of_cdate (get_birth x) with
      | Some (Dgreg (g2, _)) ->
        if strictly_after_dmy g1 g2 then warning (ParentBornAfterChild (parent, x))
        else Date.time_elapsed_opt g1 g2 |> Option.iter @@ fun a ->
          if strictly_younger a min_parent_age
          then warning (ParentTooYoung (parent, a, x))
          else if (get_sex parent = Female && strictly_older a max_mother_age)
               || (get_sex parent = Male && strictly_older a max_father_age)
          then warning (ParentTooOld (parent, a, x))
      | _ -> match Date.date_of_death (get_death x) with
        | Some (Dgreg (g2, _)) ->
          if strictly_after_dmy g1 g2 then warning (ParentBornAfterChild (parent, x))
          else Date.time_elapsed_opt g1 g2 |> Option.iter @@ fun a ->
            if strictly_younger a min_parent_age
            then warning (ParentTooYoung (parent, a, x))
        | _ -> ()
    end
  | _ -> ()

let child_born_before_mother_death warning x mother =
  match Adef.od_of_cdate (get_birth x) with
  | Some (Dgreg (d1, _)) ->
    begin
      match Date.date_of_death @@ get_death mother with
      | Some (Dgreg (d2, _)) ->
        if strictly_after_dmy d1 d2
        then warning (MotherDeadBeforeChildBirth (mother, x))
      | _ -> ()
    end
  | _ -> ()

let possible_father warning x father =
  match Adef.od_of_cdate (get_birth x) with
  | Some (Dgreg (d1, _)) when d1.prec <> Before ->
    begin
      match Date.date_of_death (get_death father) with
      | Some (Dgreg (d2, _)) when d2.prec <> After ->
        let a2 =
          match d2 with
          | {prec = YearInt dmy2} -> dmy2.year2
          | {prec = OrYear dmy2} -> dmy2.year2
          | {year = a} -> a
        in
        if d1.year > a2 + 1 then warning (DeadTooEarlyToBeFather (father, x))
      | _ -> ()
    end
  | _ -> ()

let child_has_sex warning child =
  if get_sex child = Neuter then warning (UndefinedSex child)

(* this check if events chronology is sound (e.g. no baptism before birth *)
let check_order_pfevents get_name get_date warning events =
  let events = Event.sort_events get_name get_date events in
  let rec loop = function
    | e1 :: e2 :: events ->
      begin match get_name e1 with
        | Event.Pevent (Epers_Name _) | Event.Fevent (Efam_Name _) ->
          loop (e2 :: events)
        | n1 ->
          match  get_name e2 with
          | Event.Pevent (Epers_Name _) | Event.Fevent (Efam_Name _) ->
            loop (e1 :: events)
          | n2 ->
            if Event.compare_event_name n1 n2 = 1
            then warning e1 e2 ;
            loop (e2 :: events)
      end
    | _ -> ()
  in
  loop events

let check_order_pevents warning p =
  check_order_pfevents
    (fun evt -> Event.Pevent evt.epers_name)
    (fun evt -> evt.epers_date)
    (fun e1 e2 -> warning (PEventOrder (p, e1, e2)))
    (get_pevents p)

let check_order_fevents base warning fam =
  let p = poi base (get_father fam) in
  check_order_pfevents
    (fun evt -> Event.Fevent evt.efam_name)
    (fun evt -> evt.efam_date)
    (fun e1 e2 -> warning (FEventOrder (p, e1, e2)))
    (get_fevents fam)

let check_witness_pevents_aux warning origin evt date b d p witness_kind =
  match b, d with
  | Some (Dgreg (d1, _)), _ when strictly_before_dmy date d1 ->
    warning (PWitnessEventBeforeBirth (p, evt, origin))
  | _, Some (Dgreg (d3, _)) when strictly_after_dmy date d3 ->
     if witness_kind <> Def.Witness_Mentioned && witness_kind <> Def.Witness_Other then
       warning (PWitnessEventAfterDeath (p, evt, origin))
  | _ -> ()

let check_witness_pevents base warning origin =
  List.iter begin fun evt ->
    match Adef.od_of_cdate evt.epers_date with
    | Some (Dgreg (d2, _)) ->
      Array.iter begin fun (iw, witness_kind) ->
        let p = poi base iw in
        check_witness_pevents_aux warning origin evt d2
          (Adef.od_of_cdate @@ get_birth p)
          (Date.date_of_death @@ get_death p) p
          witness_kind
      end evt.epers_witnesses
    | _ -> ()
  end (get_pevents origin)

(** Returns wether [iper] can be found in the provided associative array and
    wether it was found associated only with the Mentionned or Other witness kind.
**)
let witness_occur : iper -> (iper * witness_kind) array -> bool * bool =
  let f iper (is_witness, only_mentioned_or_other) (i, wk) =
    if i = iper then
      true, only_mentioned_or_other && (wk = Def.Witness_Mentioned || wk = Def.Witness_Other)
    else is_witness, only_mentioned_or_other
  in
  fun iper a ->
  let is_w, only_mentioned_or_other = Array.fold_left (f iper) (false, true) a in
  is_w, is_w && only_mentioned_or_other

let witness_kind_of_witness_array iper witnesses =
  let is_witness, only_mentioned_or_other = witness_occur iper witnesses in
  if is_witness then
    let kind = if only_mentioned_or_other then Def.Witness_Mentioned else Def.Witness in
    Some kind
  else
    None

let check_person_dates_as_witness base warning p =
  let ip = get_iper p in
  let birth_date =
    match Adef.od_of_cdate (get_birth p) with
    | Some (Dgreg (_, _) as d) -> Some d
    | _ -> None
  in
  let death_date =
    match get_death p with
    | Death (_, d3) -> Some (Adef.date_of_cdate d3)
    | _ -> None
  in
  let aux date w1 w2 = fun evt ->
    begin match Adef.od_of_cdate (date evt) with
      | Some (Dgreg (_, _) as d) ->
        begin match birth_date with
          | Some (Dgreg (_, _) as d') -> if strictly_before d d' then w1 evt
          | _ -> ()
        end ;
        begin match death_date with
          | Some d' -> if strictly_after d d' then w2 evt
          | _ -> ()
        end
      | _ -> ()
    end
  in
  let related_p = get_related p in
  let related_fam =
    List.fold_left begin fun acc ir ->
      let r = poi base ir in
      if get_sex r = Male
      then
        Array.fold_left
          begin fun acc ifam ->
            let fam = foi base ifam in
            if Array.mem ip (get_witnesses fam)
            then fam :: acc
            else acc
          end acc (get_family r)
      else acc
    end [] related_p
  in
  List.iter begin fun fam ->
    List.iter begin fun evt ->
      match witness_kind_of_witness_array ip evt.efam_witnesses with
      | Some Def.Witness_Mentioned | Some Def.Witness_Other ->
         aux
           (fun e -> e.efam_date)
           (fun e -> warning (FWitnessEventBeforeBirth (p, e, get_ifam fam)))
           (fun _ -> ())
           evt
      | Some _ ->
         aux
           (fun e -> e.efam_date)
           (fun e -> warning (FWitnessEventBeforeBirth (p, e, get_ifam fam)))
           (fun e -> warning (FWitnessEventAfterDeath (p, e, get_ifam fam)))
           evt
      | None -> ()
    end (get_fevents fam)
  end related_fam ;
  let related_pers =
    List.fold_left begin fun acc ir ->
      let r = poi base ir in
      List.fold_left
        begin fun acc e ->
        let witness_kind = witness_kind_of_witness_array ip e.epers_witnesses in
        match witness_kind with
        | Some kind -> (e, r, kind) :: acc
        | _ -> acc
        end
        acc (get_pevents r)
    end [] related_p
  in
  List.iter begin fun (evt, r, kind) ->
    match kind with
    | Def.Witness_Mentioned | Def.Witness_Other ->
       aux
         (fun e -> e.epers_date)
         (fun e -> warning (PWitnessEventBeforeBirth (p, e, r)))
         (fun _ -> ())
         evt
    | _ ->
       aux
         (fun e -> e.epers_date)
         (fun e -> warning (PWitnessEventBeforeBirth (p, e, r)))
         (fun e -> warning (PWitnessEventAfterDeath (p, e, r)))
         evt
  end related_pers

let check_pevents base warning p =
  (* check order of events *)
  check_order_pevents warning p ;
  (* check person's witnesses *)
  check_witness_pevents base warning p;
  (* check another witness dates where person is a witness *)
  check_person_dates_as_witness base warning p

let check_siblings ?(onchange = true) base warning (ifam, fam) callback =
  let children =
    if onchange then
      let b = get_children fam in
      match sort_children base b with
      | None -> b
      | Some (b, a) ->
        warning (ChangedOrderOfChildren (ifam, fam, b, a)) ;
        a
    else get_children fam
  in
  let (_, gap) =
    Array.fold_left begin fun (np, gap) child ->
      let child = poi base child in
      let b = obirth child in
      let gap = siblings_gap gap child b in
      born_after_his_elder_sibling warning child b np ifam fam;
      close_siblings warning child np ifam ;
      callback child ;
      let np = match b with
        | Some d -> Some (child, d)
        | _ -> np
      in
      (np, gap)
    end (None, None) children
  in
  match gap with
  | Some ((d1, p1), (d2, p2)) ->
    Date.time_elapsed_opt d1 d2 |> Option.iter @@ fun e ->
    if e.year > max_siblings_gap then warning (DistantChildren (ifam, p1, p2))
   | _ -> ()

let check_children ?(onchange = true) base warning (ifam, fam) fath moth =
  check_siblings ~onchange base warning (ifam, fam) @@ fun child ->
  check_pevents base warning child;
  child_born_after_his_parent warning child fath;
  child_born_after_his_parent warning child moth;
  child_born_before_mother_death warning child moth;
  possible_father warning child fath;
  child_has_sex warning child

let has_family_sources fam =
  not
    (is_empty_string (get_fsources fam) &&
     is_empty_string (get_marriage_src fam))

let has_person_sources p =
  not
    (is_empty_string (get_psources p) &&
     is_empty_string (get_baptism_src p) &&
     is_empty_string (get_birth_src p) && is_empty_string (get_death_src p) &&
     is_empty_string (get_burial_src p))


(* ************************************************************************* *)
(*  [Fonc] check_sources :
      base -> (Def.misc -> unit) -> ifam -> family -> unit                   *)
(** [Description] : Il y a un avertissment 'miscellaneous' si aucune des
                    personnes (conjoint1 ET conjoint2) n'a de sources
                    (indiduelles ou familliales).
    [Args] :
      - base : base
      - misc : fonction qui ajoute un misc à la liste des miscs
      - ifam : ifam
      - fam  : family
    [Retour] : Néant
    [Rem] : Non exporté en clair hors de ce module.                          *)
(* ************************************************************************* *)
let check_sources base misc ifam fam =
  if has_family_sources fam then ()
  else
    let cpl = foi base ifam in
    let fath = poi base (get_father cpl) in
    let moth = poi base (get_mother cpl) in
    if has_person_sources fath && has_person_sources moth then ()
    else misc MissingSources

let check_witness_fevents_aux warning fam evt date b d p witness_kind =
  match b, d with
  | Some (Dgreg (d1, _)), _ when strictly_before_dmy date d1 ->
    warning (FWitnessEventBeforeBirth (p, evt, get_ifam fam))
  | _, Some (Dgreg (d3, _)) when strictly_after_dmy date d3 ->
     if witness_kind <> Def.Witness_Mentioned && witness_kind <> Def.Witness_Other then
       warning (FWitnessEventAfterDeath (p, evt, get_ifam fam))
  | _ -> ()

let check_witness_fevents base warning fam =
  List.iter begin fun evt ->
    match Adef.od_of_cdate evt.efam_date with
    | Some (Dgreg (d2, _)) ->
      Array.iter begin fun (iw, witness_kind) ->
        let p = poi base iw in
        check_witness_fevents_aux warning fam evt d2
          (Adef.od_of_cdate @@ get_birth p)
          (Date.date_of_death @@ get_death p) p
          witness_kind
      end evt.efam_witnesses
    | _ -> ()
  end (get_fevents fam)

let check_parent_marriage_age warning fam p =
  let rec loop = function
    | [] -> ()
    | { efam_name = (Efam_Marriage|Efam_PACS) ; efam_date ; _ } :: list ->
        begin match Adef.od_of_cdate efam_date with
          | Some (Dgreg (g2, _) as d2) ->
            begin match Date.date_of_death (get_death p) with
              | Some d1 when strictly_after d2 d1 ->
                warning (MarriageDateAfterDeath p)
              | _ ->
                match Adef.od_of_cdate (get_birth p) with
                | Some (Dgreg (g1, _) as d1) ->
                  if strictly_before d2 d1
                  then warning (MarriageDateBeforeBirth p)
                  else Date.time_elapsed_opt g1 g2 |> Option.iter @@ fun e ->
                    if strictly_younger e min_age_marriage
                    then warning (YoungForMarriage (p, e, get_ifam fam))
                    else if strictly_older e max_age_marriage
                    then warning (OldForMarriage (p, e, get_ifam fam))
                    else loop list
                | _ -> loop list
            end
          | _ -> loop list
        end
      | _ :: list -> loop list
  in
  loop (get_fevents fam)

let check_possible_duplicate_family ?p base warning family father mother =
  let ifath = get_father family in
  let imoth = get_mother family in
  let ifam = get_ifam family in

  let name fn i = Name.strip_lower @@ sou base (fn i) in
  let first_name = name get_first_name in
  let surname = name get_surname in

  let father_fn, father_sn = first_name father, surname father in
  let mother_fn, mother_sn = first_name mother, surname mother in
  let fath_families = get_family father in
  let moth_families = get_family mother in

  let f get_parent (_current_parent, current_parent_iper, current_parent_fn, current_parent_sn) parent_source ifam' =
    if eq_ifam ifam ifam' then ()
    else begin
        let fam' = foi base ifam' in
        let parent' = get_parent fam' in
        let person = poi base parent' in
        let fn, sn = first_name person, surname person in
        (* Parent is strictly the same *)
        if eq_iper parent' current_parent_iper then
          warning (PossibleDuplicateFam (ifam, ifam'))
        (*  Homonymous parents *)
        else if fn = current_parent_fn && sn = current_parent_sn then
          warning (PossibleDuplicateFamHomonymous (ifam, ifam', parent_source))
        else ()
      end
  in

  match p with
  | Some p when eq_iper (get_iper p) ifath ->
     Array.iter (f get_mother (mother, imoth, mother_fn, mother_sn) father) fath_families
  | Some p when eq_iper (get_iper p) imoth ->
     Array.iter (f get_father (father, ifath, father_fn, father_sn) mother) moth_families
  | _ ->
     Array.iter (f get_mother (mother, imoth, mother_fn, mother_sn) father) fath_families;
     Array.iter (f get_father (father, ifath, father_fn, father_sn) mother) moth_families


let check_parents base warning fam fath moth =
  (* check father's marriage date *)
  check_parent_marriage_age warning fam fath ;
  (* check mother's marriage date *)
  check_parent_marriage_age warning fam moth ;
  (* check age difference between spouses *)
  check_difference_age_between_cpl warning fath moth;
  check_possible_duplicate_family base warning fam fath moth

let changed_pevents_order warning p =
  let a = get_pevents p in
  let b =
    Event.sort_events
      (fun evt -> Pevent evt.epers_name) (fun evt -> evt.epers_date)
      a
  in
  if a <> b then warning (ChangedOrderOfPersonEvents (p, a, b))

let changed_fevents_order warning (ifam, fam) =
  let a =
    Event.sort_events (fun evt -> Fevent evt.efam_name) (fun evt -> evt.efam_date)
      (get_fevents fam)
  in
  let b = get_fevents fam in
  if compare b a <> 0 then warning (ChangedOrderOfFamilyEvents (ifam, b, a))

(* main *)

let person ?(onchange = true) base warning p =
  (* check personal events *)
  check_pevents base warning p;
  (* check person's age *)
  check_person_age warning p;
  (* check titles dates *)
  List.iter (title_dates warning p) (get_titles p);
  (* check order of personal events *)
  if onchange then changed_pevents_order warning p ;
  related_sex_is_coherent base warning p

let family ?(onchange = true) base warning ifam fam =
  let fath = poi base @@ get_father fam in
  let moth = poi base @@ get_mother fam in
  (* check order of familial events *)
  check_order_fevents base warning fam ;
  (* check family's witnesses *)
  check_witness_fevents base warning fam ;
  (* check parents marraige *)
  check_parents base warning fam fath moth ;
  (* check children *)
  check_children ~onchange base warning (ifam, fam) fath moth ;
  if onchange then begin
    changed_fevents_order warning (ifam, fam);
    let father = poi base (get_father fam) in
    let mother = poi base (get_mother fam) in
    (* change order of father's families *)
    changed_marriages_order base warning father;
    (* change order of mother's families *)
    changed_marriages_order base warning mother
  end

let check_related_person_pevents warning birth_date death_date p iper related_p =
  List.iter begin fun e ->
    match Adef.od_of_cdate e.epers_date with
    | Some (Dgreg (date, _)) ->
       let is_witness, only_mentioned = witness_occur iper e.epers_witnesses in
       if is_witness then
         let witness_kind = if only_mentioned then Def.Witness_Mentioned else Def.Witness in
         check_witness_pevents_aux warning related_p e date birth_date death_date p witness_kind
    | _ -> ()
    end (get_pevents related_p)

let check_related_person_fevents warning base birth_date death_date p iper related_p =
  Array.iter begin fun i ->
    let f = foi base i in
    List.iter begin fun e ->
      match Adef.od_of_cdate e.efam_date with
      | Some (Dgreg (date, _)) ->
         let is_witness, only_mentioned = witness_occur iper e.efam_witnesses in
         if is_witness then
           let witness_kind = if only_mentioned then Def.Witness_Mentioned else Def.Witness in
           check_witness_fevents_aux warning f e date birth_date death_date p witness_kind
      | _ -> ()
      end (get_fevents f)
    end (get_family related_p)


let check_related_on_person_update warning base birth_date death_date p iper irel =
  let related_p = poi base irel in
  check_related_person_pevents warning birth_date death_date p iper related_p;
  check_related_person_fevents warning base birth_date death_date p iper related_p


let on_person_update base warning p =
  begin match get_parents p with
    | Some i ->
      let fam = foi base i in
      let fath = poi base @@ get_father fam in
      let moth = poi base @@ get_mother fam in
      child_born_after_his_parent warning p fath ;
      child_born_after_his_parent warning p moth ;
      check_siblings base warning (i, fam) ignore
    | _ -> ()
  end ;
  let b = Adef.od_of_cdate (get_birth p) in
  let d = Date.date_of_death @@ get_death p in
  let iper = get_iper p in
  if b <> None || d <> None then
    List.iter (check_related_on_person_update warning base b d p iper) (get_related p);
  Array.iter begin fun ifam ->
    let fam = foi base ifam in
    let fath, moth =
      if get_iper p = get_father fam
      then p, poi base @@ get_mother fam
      else poi base @@ get_father fam, p
    in
    check_parent_marriage_age warning fam p ;
    check_difference_age_between_cpl warning fath moth ;
    check_possible_duplicate_family ~p base warning fam fath moth;
    Array.iter begin fun child ->
      let child = poi base child in
      child_born_after_his_parent warning child p ;
      match get_sex p with
      | Male -> possible_father warning child p ;
      | Female -> child_born_before_mother_death warning child p
      | Neuter -> ()
    end (get_children fam)
  end (get_family p)

(* ************************************************************************* *)
(*  [Fonc] check_other_fields :
      base -> (Def.misc -> unit) -> ifam -> family -> unit                   *)
(** [Description] : Vérifie les autres champs de saisie des formulaires
                    individu et famille.
    [Args] :
      - base : base
      - misc : fonction qui ajoute un misc à la liste des miscs
      - ifam : ifam
      - fam  : family
    [Retour] : Néant
    [Rem] : Exporté en clair hors de ce module.                              *)
(* ************************************************************************* *)
let check_other_fields base misc ifam fam = check_sources base misc ifam fam


let first_name base p = Name.strip_lower @@ sou base @@ get_first_name p
let surname base p = Name.strip_lower @@ sou base @@ get_surname p

let hom_person base p1 p2 =
  let fn1, sn1 = first_name base p1, surname base p1 in
  let fn2, sn2 = first_name base p2, surname base p2 in
  fn1 = fn2 && sn1 = sn2

let hom_fam base f1 f2 =
  let f1, f2 = foi base f1, foi base f2 in
  let fa1, mo1 = poi base @@ get_father f1, poi base @@ get_mother f1 in
  let fa2, mo2 = poi base @@ get_father f2, poi base @@ get_mother f2 in
  hom_person base fa1 fa2 && hom_person base mo1 mo2

let eq_person p1 p2 =
  eq_iper (get_iper p1) (get_iper p2)

let eq_family f1 f2 =
  eq_ifam (get_ifam f1) (get_ifam f2)

let eq_warning base w1 w2 = match w1, w2 with
  | PossibleDuplicateFam (f1, f2),
    PossibleDuplicateFam (f1', f2') ->
     eq_ifam f1 f1' && eq_ifam f2 f2'
     || eq_ifam f1 f2' && eq_ifam f2 f1'
  | PossibleDuplicateFamHomonymous (f1, f2, _),
    PossibleDuplicateFamHomonymous (f1', f2', _) ->
     hom_fam base f1 f1' && hom_fam base f2 f2'
     || hom_fam base f1 f2' && hom_fam base f2 f1'
  | BigAgeBetweenSpouses (p1, p2, d),
    BigAgeBetweenSpouses (p1', p2', d') ->
     (eq_person p1 p1' && eq_person p2 p2'
      || eq_person p1 p2' && eq_person p2 p1')
     && d = d'
  | BirthAfterDeath p,
    BirthAfterDeath p' ->
     eq_person p p'
  | IncoherentSex (p, s1, s2),
    IncoherentSex (p', s1', s2') ->
     eq_person p p'
     && (s1 = s1' && s2 = s2' || s1 = s2' && s2 = s1')
  | ChangedOrderOfChildren (ifam, fam, ipers1, ipers2),
    ChangedOrderOfChildren (ifam', fam', ipers1', ipers2')->
     eq_ifam ifam ifam'
     && (eq_family fam fam')
     && ipers1 = ipers1' && ipers2 = ipers2'
  | ChangedOrderOfMarriages (p, ifams, ifams2),
    ChangedOrderOfMarriages (p', ifams', ifams2') ->
     eq_person p p' && ifams = ifams' && ifams2 = ifams2'
  | ChangedOrderOfFamilyEvents (ifam, fevents, fevents2),
    ChangedOrderOfFamilyEvents (ifam', fevents', fevents2') ->
     eq_ifam ifam ifam' && fevents = fevents' && fevents2 = fevents2'
  | ChangedOrderOfPersonEvents (p, pevents, pevents2),
    ChangedOrderOfPersonEvents (p', pevents', pevents2') ->
     eq_person p p' && pevents = pevents' && pevents2 = pevents2'
  | ChildrenNotInOrder (ifam, fam, p1, p2),
    ChildrenNotInOrder (ifam', fam', p1', p2') ->
     eq_ifam ifam ifam' && eq_family fam fam' && eq_person p1 p1' && eq_person p2 p2'
  | CloseChildren (ifam, p1, p2),
    CloseChildren (ifam', p1', p2') ->
     eq_ifam ifam ifam'
     && (eq_person p1 p1' && eq_person p2 p2'
         || eq_person p1 p2' && eq_person p2 p1')
  | DeadOld (p, d), DeadOld (p', d') ->
     eq_person p p' && d = d'
  | DeadTooEarlyToBeFather (p1, p2), DeadTooEarlyToBeFather (p1', p2') ->
     eq_person p1 p1' && eq_person p2 p2'
  | DistantChildren (ifam, p1, p2), DistantChildren (ifam', p1', p2') ->
     eq_ifam ifam ifam' && eq_person p1 p1' && eq_person p2 p2'
  | FEventOrder (p, fevent, fevent2), FEventOrder (p', fevent', fevent2') ->
     eq_person p p' && fevent = fevent' && fevent2 = fevent2'
  | FWitnessEventAfterDeath (p, fevent, ifam),
    FWitnessEventAfterDeath (p', fevent', ifam') ->
     eq_person p p' && fevent = fevent' && eq_ifam ifam ifam'
  | FWitnessEventBeforeBirth (p, fevent, ifam),
    FWitnessEventBeforeBirth (p', fevent', ifam') ->
     eq_person p p' && fevent = fevent' && eq_ifam ifam ifam'
  | IncoherentAncestorDate (p1, p2),
    IncoherentAncestorDate (p1', p2') ->
     eq_person p1 p1' && eq_person p2 p2'
  | MarriageDateAfterDeath p, MarriageDateAfterDeath p' ->
     eq_person p p'
  | MarriageDateBeforeBirth p, MarriageDateBeforeBirth p' ->
     eq_person p p'
  | MotherDeadBeforeChildBirth (p1, p2), MotherDeadBeforeChildBirth (p1', p2') ->
     eq_person p1 p1' && eq_person p2 p2'
  | ParentBornAfterChild (p1, p2), ParentBornAfterChild (p1', p2') ->
     eq_person p1 p1' && eq_person p2 p2'
  | ParentTooOld (p1, d, p2), ParentTooOld (p1', d', p2') ->
     eq_person p1 p1' && eq_person p2 p2' && d = d'
  | ParentTooYoung (p1, d, p2), ParentTooYoung (p1', d', p2') ->
     eq_person p1 p1' && eq_person p2 p2' && d = d'
  | PEventOrder (p, pevent1, pevent2), PEventOrder (p', pevent1', pevent2') ->
     eq_person p p' && pevent1 = pevent1' && pevent2 = pevent2'
  | PWitnessEventAfterDeath (p1, pevent, p2), PWitnessEventAfterDeath (p1', pevent', p2') ->
     eq_person p1 p1' && eq_person p2 p2' && pevent = pevent'
  | PWitnessEventBeforeBirth (p1, pevent, p2), PWitnessEventBeforeBirth (p1', pevent', p2') ->
     eq_person p1 p1' && eq_person p2 p2' && pevent = pevent'
  | TitleDatesError (p, title), TitleDatesError (p', title') ->
     eq_person p p' && title = title'
  | UndefinedSex p, UndefinedSex p' ->
     eq_person p p'
  | YoungForMarriage (p, d, ifam), YoungForMarriage (p', d', ifam') ->
     eq_person p p' && d = d' && eq_ifam ifam ifam'
  | OldForMarriage (p, d, ifam), OldForMarriage (p', d', ifam') ->
     eq_person p p' && d = d' && eq_ifam ifam ifam'
  | _ -> false

let person_warnings conf base p =
  let w = ref [] in
  let filter x =
    if not (List.exists (eq_warning base x) !w) && Util.auth_warning conf base x
    then w := x :: !w
  in
  ignore @@ person base filter p ;
  on_person_update base filter p ;
  Array.iter begin fun ifam ->
    check_siblings ~onchange:false base filter (ifam, foi base ifam) ignore
  end (get_family p) ;
  !w
