[%%metapackage metapp]
[%%metadir "meta/.traverse_meta.objs/byte/"]

let variable_count = [%meta Metapp.Exp.of_int Traverse_meta.variable_count]

module Applicative = struct
  include Traverse_interface

  module Make (Applicative : Traverse_modules.Applicative.S) : InstanceS
  with module Applicative = Applicative = struct
    module Applicative = Applicative

    let instance () =
      [%meta
        Traverse_meta.newtypes Traverse_meta.ti [%expr
          A (
            let module M = struct
              module Applicative = Applicative
              [%%meta Metapp.Stri.of_list
                (List.init Traverse_meta.variable_count (fun i ->
                  let ti = Traverse_meta.ti i in
                  let ti_t = Traverse_meta.ti_t i in
                  Metapp.Stri.of_list [
                    Ast_helper.Str.type_ Nonrecursive
                      [Ast_helper.Type.mk (Metapp.mkloc ti)
                        ~manifest:(Traverse_meta.type_of_string ti);
                        Ast_helper.Type.mk (Metapp.mkloc ti_t)
                        ~manifest:
                          [%type: [%meta Traverse_meta.type_of_string ti]
                          Applicative.t]];
                    Ast_helper.Str.value Nonrecursive
                      [Ast_helper.Vb.mk
                        [%pat? ([%meta Metapp.Pat.var (Traverse_meta.eqi i)] :
                          ([%meta Traverse_meta.type_of_string ti]
                          Applicative.t,
                          [%meta Traverse_meta.type_of_string ti_t]) eq)]
                        [%expr Eq]]]))]
            end in
            (module M))]]
  end

  let iter () =
    let module M = Make (Traverse_modules.Applicative.Iter) in
    M.instance ()

  let map () =
    let module M = Make (Traverse_modules.Applicative.Map) in
    M.instance ()

  let reduce (type m) (monoid : m Traverse_modules.Monoid.t) =
    let module Monoid = (val monoid) in
    let module M = Make (Traverse_modules.Applicative.Reduce (Monoid)) in
    M.instance

  [%%metadef
  let param modname k =
    let tim i = Traverse_meta.ti_t i ^ modname in
    Traverse_meta.newtypes tim [%expr fun (m :
      [%meta Traverse_meta.mk_t (fun i ->
        (Traverse_meta.type_of_string (Traverse_meta.ti i),
          Traverse_meta.type_of_string (tim i)))]) ->
        let A m = m () in
        [%meta Ast_helper.Exp.letmodule (Metapp.mkloc (Some modname))
          (Ast_helper.Mod.unpack [%expr m])
          (Traverse_meta.compose (fun i acc ->
            [%expr let Eq = [%meta Ast_helper.Exp.ident (Metapp.mkloc
              (Longident.Ldot (Lident modname, Traverse_meta.eqi i)))] in
              [%meta acc]])
              (k tim))]]]

  let env (type env) =
    [%meta Traverse_meta.newtypes Traverse_meta.ti
      (param "Base" (fun tib -> [%expr
        let module E = struct
          type t = env
        end in
        let module M =
          Make (Traverse_modules.Applicative.Env (E) (Base.Applicative)) in
        (M.instance :
          [%meta Traverse_meta.mk_t (fun i ->
            (Traverse_meta.type_of_string (Traverse_meta.ti i), [%type: env ->
              [%meta Traverse_meta.type_of_string (tib i)]]))])]))]

  let fold (type acc) () =
    let module Accu = struct
      type t = acc
    end in
    let module M = Make (Traverse_modules.Applicative.Fold (Accu)) in
    M.instance ()

  let pair =
    [%meta Traverse_meta.newtypes Traverse_meta.ti
      (param "U" (fun tiu -> param "V" (fun tiv -> [%expr
        let module M =
          Make (Traverse_modules.Applicative.Pair
            (U.Applicative) (V.Applicative)) in
        (M.instance : [%meta Traverse_meta.mk_t (fun i ->
          (Traverse_meta.type_of_string (Traverse_meta.ti i),
            [%type:
               [%meta Traverse_meta.type_of_string (tiu i)] *
               [%meta Traverse_meta.type_of_string (tiv i)]]))])])))]

  let forall () =
    let module M = Make (Traverse_modules.Applicative.Forall) in
    M.instance ()

  let exists () =
    let module M = Make (Traverse_modules.Applicative.Exists) in
    M.instance ()

  let option = [%meta Traverse_meta.newtypes Traverse_meta.ti (param "Base"
    (fun tib -> [%expr
      let module M =
        Make (Traverse_modules.Applicative.Option (Base.Applicative)) in
      (M.instance : [%meta Traverse_meta.mk_t (fun i ->
        (Traverse_meta.type_of_string (Traverse_meta.ti i),
        [%type: [%meta Traverse_meta.type_of_string (tib i)] option]))])]))]

  let result (type err) =
    [%meta Traverse_meta.newtypes Traverse_meta.ti (param "Base"
      (fun tib -> [%expr
        let module Err = struct
          type t = err
        end in
        let module M =
          Make (Traverse_modules.Applicative.Result (Base.Applicative) (Err)) in
        (M.instance :
          [%meta Traverse_meta.mk_t (fun i ->
            (Traverse_meta.type_of_string (Traverse_meta.ti i), [%type:
              ([%meta Traverse_meta.type_of_string (tib i)], err)
                result]))])]))]

  let list =
    [%meta Traverse_meta.newtypes Traverse_meta.ti (param "Base"
      (fun tib -> [%expr
        let module M =
          Make (Traverse_modules.Applicative.List (Base.Applicative)) in
        (M.instance : [%meta Traverse_meta.mk_t (fun i ->
          (Traverse_meta.type_of_string (Traverse_meta.ti i),
          [%type: [%meta Traverse_meta.type_of_string (tib i)] list]))])]))]
end

let list (type a b b_seq f result tail)
  (app : (a * b * (a list * b_seq * tail)) Applicative.t)
  (arity : (b, b_seq, f, result, [`Not_empty]) Traverse_modules.List.Arity.t)
  (f : f) : result =
  let A app = app () in
  let module M = (val app) in
  let Eq = M.eq0 in
  let Eq = M.eq1 in
  let module Traverse = Traverse_modules.List.Make (M.Applicative) in
  Traverse.traverse arity f

let seq (type a b b_seq f result tail)
  (app : (a * b * (a Seq.t * b_seq * tail)) Applicative.t)
  (arity : (b, b_seq, f, result, [`Not_empty]) Traverse_modules.Seq.Arity.t)
  (f : f) : result =
  let A app = app () in
  let module M = (val app) in
  let Eq = M.eq0 in
  let Eq = M.eq1 in
  let module Traverse = Traverse_modules.Seq.Make (M.Applicative) in
  Traverse.traverse arity f
