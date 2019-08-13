open Asttypes
open Parsetree

module SMap = Map.Make (String)
module SSet = Set.Make (String)

type module_unit_id = Path of string
module UStore = Map.Make(struct
  type t = module_unit_id
  let compare (Path a) (Path b) = String.compare a b
end)

type value =
  | Int of int
  | Int64 of int64
  | Fun of arg_label * expression option * pattern * expression * env ref
  | Function of case list * env ref
  | String of bytes
  | Float of float
  | Tuple of value list
  | Constructor of string * int * value option
  | Prim of (value -> value)
  | Fexpr of fexpr
  | ModVal of mdl
  | InChannel of in_channel
  | OutChannel of out_channel
  | Record of value ref SMap.t
  | Lz of (unit -> value) ref
  | Array of value array
  | Fun_with_extra_args of value * value list * (arg_label * value) SMap.t

and fexpr = Location.t -> (arg_label * expression) list -> expression option

and 'a env_map = (bool * 'a) SMap.t
(* the boolean tracks whether the value should be exported in the
   output environment *)

and env =
  { values : value env_map;
    units : module_unit_state UStore.t;
    modules : mdl env_map;
    constructors : int env_map
    }

and mdl =
  | Unit of module_unit_id
  | Module of mdl_val
  | Functor of string * module_expr * env

and mdl_val = value SMap.t * mdl SMap.t * int SMap.t

and module_unit_state =
  | Not_initialized_yet
  | Initialized of mdl_val
(* OCaml calls a "compilation unit" the language object corresponding
   to a group of files of the same name with different extensions
   (foo.ml, foo.mli in source form, foo.cm* in compiled form). From
   the language those are also visible implicitly as modules (Foo),
   but they are not exactly identical to modules as well -- in what
   sort of dependencies are allowed between units, in particular.

   Instead of "compilation units" which sounds strange in an
   interpreter, we just call these "module units" or "units".

   In our value representation, some of the modules in the environment
   may in fact be units (a unit is a category of module), and
   initialized units contain module data, like a normal module.

   The -no-alias-deps flag allows an OCaml source fragment to create
   an alias to a unit that has not been evaluated yet -- allowing
   cyclic dependencies where each cycle contains a "weak" edge that is
   just a module-alias occurrence

   From an operational point of view, this corresponds to allowing
   implicit recursive definition of units, where all units can
   alias/reference each other (even units evaluated later), but a unit
   may only dereference (access the module data of) a unit evaluated
   earlier.

   To support these recursive definitions, we give backpatching
   semantics to unit definitions: all the units that are to be
   evaluated are loaded at once in the environment as "non
   initialized" units, and after each unit is evaluated to some module
   data we mutate its slot in the environment, which makes
   non-aliasing uses possible for further units.

   We implement this by having a special store of units indexed by
   "unit identifiers", behaving like a mutable store with
   a single-write semantics in each location: first a unit is
   "declared" (it is given a valid unit id, which can be used to
   reference the corresponding module, but its definition in the store
   is [Not_yet_initialized]), then the module is "defined" exactly
   one, and its definition in the unit store is replaced by a module
   value.
*)

(* TODO: include arg restriction *)

exception InternalException of value

let unit = Constructor ("()", 0, None)

let is_true = function
  | Constructor ("true", _, None) -> true
  | Constructor ("false", _, None) -> false
  | _ -> assert false

let rec pp_print_value ff = function
  | Int n -> Format.fprintf ff "%d" n
  | Int64 n -> Format.fprintf ff "%Ld" n
  | Fexpr _ -> Format.fprintf ff "<fexpr>"
  | Fun _ | Function _ | Prim _ | Lz _ | Fun_with_extra_args _ ->
    Format.fprintf ff "<function>"
  | String s -> Format.fprintf ff "%S" (Bytes.to_string s)
  | Float f -> Format.fprintf ff "%f" f
  | Tuple l ->
    Format.fprintf
      ff
      "(%a)"
      (Format.pp_print_list
         ~pp_sep:(fun ff () -> Format.fprintf ff ", ")
         pp_print_value)
      l
  | Constructor (c, d, None) -> Format.fprintf ff "%s#%d" c d
  | Constructor (c, d, Some v) ->
    Format.fprintf ff "%s#%d %a" c d pp_print_value v
  | ModVal _ -> Format.fprintf ff "<module>"
  | InChannel _ -> Format.fprintf ff "<in_channel>"
  | OutChannel _ -> Format.fprintf ff "<out_channel>"
  | Record r ->
    Format.fprintf ff "{";
    SMap.iter (fun k v -> Format.fprintf ff "%s = %a; " k pp_print_value !v) r;
    Format.fprintf ff "}"
  | Array a ->
    Format.fprintf
      ff
      "[|%a|]"
      (Format.pp_print_list
         ~pp_sep:(fun ff () -> Format.fprintf ff "; ")
         pp_print_value)
      (Array.to_list a)

let pp_print_unit_id ppf (Path s) =
  Format.fprintf ppf "%S" s

let read_caml_int s =
  let c = ref 0L in
  let sign, init =
    if String.length s > 0 && s.[0] = '-' then (-1L, 1) else (1L, 0)
  in
  let base, init =
    if String.length s >= init + 2 && s.[init] = '0'
    then
      ( (match s.[init + 1] with
        | 'x' | 'X' -> 16L
        | 'b' | 'B' -> 2L
        | 'o' | 'O' -> 8L
        | _ -> assert false),
        init + 2 )
    else (10L, init)
  in
  for i = init to String.length s - 1 do
    match s.[i] with
    | '0' .. '9' as x ->
      c := Int64.(add (mul base !c) (of_int (int_of_char x - int_of_char '0')))
    | 'a' .. 'f' as x ->
      c :=
        Int64.(
          add (mul base !c) (of_int (int_of_char x - int_of_char 'a' + 10)))
    | 'A' .. 'F' as x ->
      c :=
        Int64.(
          add (mul base !c) (of_int (int_of_char x - int_of_char 'A' + 10)))
    | '_' -> ()
    | _ ->
      Format.eprintf "FIXME literal: %s@." s;
      assert false
  done;
  Int64.mul sign !c

let value_of_constant = function
  | Pconst_integer (s, (None | Some 'l')) ->
    Int (Int64.to_int (read_caml_int s))
  | Pconst_integer (s, Some ('L' | 'n')) -> Int64 (read_caml_int s)
  | Pconst_integer (_s, Some c) ->
    Format.eprintf "Unsupported suffix %c@." c;
    assert false
  | Pconst_char c -> Int (int_of_char c)
  | Pconst_float (f, _) -> Float (float_of_string f)
  | Pconst_string (s, _) -> String (Bytes.of_string s)

let rec value_equal v1 v2 =
  match (v1, v2) with
  | Fun _, _
  | Function _, _
  | _, Fun _
  | _, Function _
  | Lz _, _
  | _, Lz _
  | Fun_with_extra_args _, _
  | _, Fun_with_extra_args _ ->
    failwith "tried to compare function"
  | ModVal _, _ | _, ModVal _ -> failwith "tried to compare module"
  | InChannel _, _ | OutChannel _, _ | _, InChannel _ | _, OutChannel _ ->
    failwith "tried to compare channel"
  | Fexpr _, _ | _, Fexpr _ -> failwith "tried to compare fexpr"
  | Int n1, Int n2 -> n1 = n2
  | Int64 n1, Int64 n2 -> n1 = n2
  | Float f1, Float f2 -> f1 = f2
  | String s1, String s2 -> s1 = s2
  | Constructor (c1, d1, None), Constructor (c2, d2, None) ->
    d1 = d2 && c1 = c2
  | Constructor (c1, d1, Some v1), Constructor (c2, d2, Some v2) ->
    d1 = d2 && c1 = c2 && value_equal v1 v2
  | Constructor _, Constructor _ -> false
  | Tuple l1, Tuple l2 ->
    assert (List.length l1 = List.length l2);
    List.for_all2 value_equal l1 l2
  | Record r1, Record r2 ->
    SMap.for_all
      (fun _ b -> b)
      (SMap.merge
         (fun _ u v ->
           match (u, v) with
           | None, None -> None
           | None, Some _ | Some _, None -> Some false
           | Some u, Some v -> Some (value_equal !u !v))
         r1
         r2)
  | Array a1, Array a2 ->
    if Array.length a1 <> Array.length a2
    then false
    else (
      let ok = ref true in
      for i = 0 to Array.length a1 - 1 do
        ok := !ok && value_equal a1.(i) a2.(i)
      done;
      !ok)
  | _ -> false

let rec value_compare v1 v2 =
  match (v1, v2) with
  | Fun _, _
  | Function _, _
  | _, Fun _
  | _, Function _
  | Lz _, _
  | _, Lz _
  | Fun_with_extra_args _, _
  | _, Fun_with_extra_args _ ->
    failwith "tried to compare function"
  | ModVal _, _ | _, ModVal _ -> failwith "tried to compare module"
  | InChannel _, _ | OutChannel _, _ | _, InChannel _ | _, OutChannel _ ->
    failwith "tried to compare channel"
  | Int n1, Int n2 -> compare n1 n2
  | Int64 n1, Int64 n2 -> compare n1 n2
  | Float f1, Float f2 -> compare f1 f2
  | String s1, String s2 -> compare s1 s2
  | Constructor (_, _, None), Constructor (_, _, Some _) -> -1
  | Constructor (_, _, Some _), Constructor (_, _, None) -> 1
  | Constructor (c1, d1, vv1), Constructor (c2, d2, vv2) ->
    let c = compare (d1, c1) (d2, c2) in
    if c <> 0
    then c
    else (
      match (vv1, vv2) with
      | None, None -> 0
      | Some v1, Some v2 -> value_compare v1 v2
      | _ -> assert false)
  | Tuple l1, Tuple l2 ->
    assert (List.length l1 = List.length l2);
    List.fold_left2
      (fun cur x y -> if cur = 0 then value_compare x y else cur)
      0
      l1
      l2
  | Record r1, Record r2 ->
    let map1 =
      SMap.merge
        (fun _ u v ->
          match (u, v) with
          | None, None -> None
          | None, Some _ | Some _, None -> assert false
          | Some u, Some v -> Some (!u, !v))
        r1
        r2
    in
    SMap.fold
      (fun _ (u, v) cur -> if cur = 0 then value_compare u v else cur)
      map1
      0
  | _ -> assert false

let value_lt v1 v2 = value_compare v1 v2 < 0
let value_le v1 v2 = value_compare v1 v2 <= 0
let value_gt v1 v2 = value_compare v1 v2 > 0
let value_ge v1 v2 = value_compare v1 v2 >= 0

let next_exn_id =
  let last_exn_id = ref (-1) in
  fun () ->
    incr last_exn_id;
    !last_exn_id

exception No_module_data
let get_module_data env loc = function
  | Module data -> data
  | Functor _ ->
     Format.eprintf "%a@.Tried to access the components of a functor@."
       Location.print_loc loc;
     raise No_module_data
  | Unit id ->
     begin match UStore.find id env.units with
       | Initialized data -> data
       | exception Not_found ->
          Format.eprintf "%a@.Tried to access the undeclared unit %a@."
           Location.print_loc loc
           pp_print_unit_id id;
          raise No_module_data
       | Not_initialized_yet ->
          Format.eprintf "%a@.unit %a is not yet initialized@."
            Location.print_loc loc
            pp_print_unit_id id;
          raise No_module_data
     end

let module_name_of_unit_path path =
  path
  |> Filename.basename
  |> Filename.remove_extension
  |> String.capitalize_ascii
