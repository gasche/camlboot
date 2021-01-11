(* type out_channel *)
external caml_ml_open_descriptor_out : int -> out_channel = "caml_ml_open_descriptor_out"
external caml_ml_output : out_channel -> string -> int -> int -> unit = "caml_ml_output"
external caml_ml_flush : out_channel -> unit = "caml_ml_flush"
external caml_ml_bytes_length : string -> int = "caml_ml_bytes_length"
external format_int : string -> int -> string = "caml_format_int"
external ( ~- ) : int -> int = "%negint"
external ( + ) : int -> int -> int = "%addint"
external ( - ) : int -> int -> int = "%subint"
external ( * ) : int -> int -> int = "%mulint"
external ( / ) : int -> int -> int = "%divint"
external ( mod ) : int -> int -> int = "%modint"
external ( land ) : int -> int -> int = "%andint"
external ( lor ) : int -> int -> int = "%orint"
external ( lxor ) : int -> int -> int = "%xorint"
external ( lsl ) : int -> int -> int = "%lslint"
external ( lsr ) : int -> int -> int = "%lsrint"
external ( asr ) : int -> int -> int = "%asrint"
external ( = ) : 'a -> 'a -> bool = "caml_equal"
external ( <> ) : 'a -> 'a -> bool = "caml_notequal"
external ( > ) : 'a -> 'a -> bool = "caml_greaterthan"
external ( >= ) : 'a -> 'a -> bool = "caml_greaterequal"
external ( < ) : 'a -> 'a -> bool = "caml_lessthan"
external ( <= ) : 'a -> 'a -> bool = "caml_lessequal"
external raise : exn -> 'a = "%raise"

let failwith s = raise (Failure s)
let invalid_arg s = raise (Invalid_argument s)
let assert b = if b then () else raise (Assert_failure ("", 0, 0))
let fst (a, b) = a
let snd (a, b) = b

let stdout = caml_ml_open_descriptor_out 1

let flush () = caml_ml_flush stdout

let print_string s = caml_ml_output stdout s 0 (caml_ml_bytes_length s)
let print_int n = print_string (format_int "%d" n)
let show_int n = print_string " "; print_int n

let print_newline () =
  print_string "\n";
  flush ()

let print_endline s =
  print_string s ;
  print_string "\n" ;
  flush ()

(* various types used in the tests *)

(* variants *)
type bool = false | true
type 'a list = [] | (::) of 'a * 'a list
type 'a option = None | Some of 'a

(* synonyms *)
type 'a t = 'a * int

(* references *)
type 'a ref = { mutable contents : 'a }

let ref x = { contents = x }
let ( ! ) x = x.contents
let ( := ) x v = x.contents <- v

let __atexit () = flush ()
