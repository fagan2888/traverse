type ('a, 'b) eq = Eq : ('a, 'a) eq

module type TypeS = sig
  type t
end

module type UnaryTypeS = sig
  type 'a t
end

module Monoid = struct
  module type S = sig
    type t

    val zero : t

    val ( + ) : t -> t -> t
  end

  type 'a t = (module S with type t = 'a)
end

module Functor = struct
  module type S = sig
    type 'a t

    val map : ('a -> 'b) -> 'a t -> 'b t
  end
end

module Applicative = struct
  module type S = sig
    include Functor.S

    val pure : 'a -> 'a t

    val apply : ('a -> 'b) t -> (unit -> 'a t) -> 'b t
  end

  module type MonomorphicS = sig
    module Applicative : S

    type a

    type a_t

    type b

    type b_t

    val eq_a : (a_t, a Applicative.t) eq

    val eq_b : (b_t, b Applicative.t) eq
  end

  type ('a, 'a_t, 'b, 'b_t) t = unit ->
      (module MonomorphicS with type a = 'a and type a_t = 'a_t
      and type b = 'b and type b_t = 'b_t)

  module type InstanceS = sig
    module Applicative : S

    val instance : ('a, 'a Applicative.t, 'b, 'b Applicative.t) t
  end

  module Make (Applicative : S) : InstanceS
  with module Applicative = Applicative = struct
    module Applicative = Applicative

    let instance (type a0 b0) : (a0, a0 Applicative.t, b0, b0 Applicative.t) t =
    fun () ->
      let module M = struct
        module Applicative = Applicative
        type a = a0
        type a_t = a Applicative.t
        type b = b0
        type b_t = b Applicative.t
        let eq_a : (a_t, a Applicative.t) eq = Eq
        let eq_b : (b_t, b Applicative.t) eq = Eq
      end in
      (module M)
  end

  module Iter : S with type 'a t = unit = struct
    type 'a t = unit

    let map _f () = ()

    let pure _x = ()

    let apply _f _ = ()
  end

  let iter () =
   let module M = Make (Iter) in
   M.instance ()

  module Map : S with type 'a t = 'a = struct
    type 'a t = 'a

    let map f x = f x

    let pure x = x

    let apply f x = f (x ())
  end

  let map () =
    let module M = Make (Map) in
    M.instance ()

  module Reduce (Monoid : Monoid.S) : S with type 'a t = Monoid.t = struct
    type 'a t = Monoid.t

    let map _f accu =
      accu

    let pure _x =
      Monoid.zero

    let apply a b = Monoid.(a + b ())
  end

  let reduce (type m) (monoid : m Monoid.t) =
    let module Monoid = (val monoid) in
    let module M = Make (Reduce (Monoid)) in
    M.instance

  module Env (E : TypeS) (Base : S) : S
  with type 'a t = E.t -> 'a Base.t = struct
    type 'a t = E.t -> 'a Base.t

    let map f x env =
      Base.map f (x env)

    let pure x _env =
      Base.pure x

    let apply f x env =
      Base.apply (f env) (fun () -> x () env)
  end

  let env (type a b c d e) (base : (a, b, c, d) t) : (a, e -> b, c, e -> d) t =
    let module Base = (val (base ())) in
    let Eq = Base.eq_a in
    let Eq = Base.eq_b in
    let module E = struct
      type t = e
    end in
   let module M = Make (Env (E) (Base.Applicative)) in
   M.instance

  module Fold (Accu : TypeS) : S with type 'a t = Accu.t -> Accu.t = struct
    type 'a t = Accu.t -> Accu.t

    let map _f x accu =
      x accu

    let pure _x accu =
      accu

    let apply f x accu =
      x () (f accu)
  end

  let fold (type acc) () =
    let module Accu = struct
      type t = acc
    end in
    let module M = Make (Fold (Accu)) in
    M.instance ()

  module Pair (U : S) (V : S) : S
  with type 'a t = 'a U.t * 'a V.t = struct
    type 'a t = 'a U.t * 'a V.t

    let map f (u, v) =
      (U.map f u, V.map f v)

    let pure x =
      (U.pure x, V.pure x)

    let apply (fu, fv) uv =
      let uv = lazy (uv ()) in
      (U.apply fu (fun () -> fst (Lazy.force uv)),
        V.apply fv (fun () -> snd (Lazy.force uv)))
  end

  let pair (type a b b' c d d') (u : (a, b, c, d) t) (v : (a, b', c, d') t)
      : (a, b * b', c, d * d') t =
    let module U = (val (u ())) in
    let Eq = U.eq_a in
    let Eq = U.eq_b in
    let module V = (val (v ())) in
    let Eq = V.eq_a in
    let Eq = V.eq_b in
    let module M = Make (Pair (U.Applicative) (V.Applicative)) in
    M.instance

  module Forall : S with type 'a t = bool = struct
    type 'a t = bool

    let map _f b = b

    let pure _x = true

    let apply f x = f && x ()
  end

  let forall () =
    let module M = Make (Forall) in
    M.instance ()

  module Exists : S with type 'a t = bool = struct
    type 'a t = bool

    let map _f b = b

    let pure _x = false

    let apply f x = f || x ()
  end

  let exists () =
    let module M = Make (Exists) in
    M.instance ()

  module Option (Base : S) : S with type 'a t = 'a Base.t option = struct
    type 'a t = 'a Base.t option

    let map f o =
      Option.map (Base.map f) o

    let pure x =
      Some (Base.pure x)

    let apply f o =
      Option.bind f (fun f ->
        Option.map (fun v ->
          Base.apply f (fun () -> v)) (o ()))
  end

  let option (type a b c d) (base : (a, b, c, d) t)
      : (a, b option, c, d option) t =
    let module Base = (val (base ())) in
    let Eq = Base.eq_a in
    let Eq = Base.eq_b in
    let module M = Make (Option (Base.Applicative)) in
    M.instance

  module Result (Base : S) (Err : TypeS) : S
  with type 'a t = ('a Base.t, Err.t) result = struct
    type 'a t = ('a Base.t, Err.t) result

    let map f r =
      Result.map (Base.map f) r

    let pure x =
      Ok (Base.pure x)

    let apply f r =
      Result.bind f (fun f ->
        Result.map (fun v ->
          Base.apply f (fun () -> v)) (r ()))
  end

  let result (type a b c d err) (base : (a, b, c, d) t) :
      (a, (b, err) result, c, (d, err) result) t =
    let module Base = (val (base ())) in
    let Eq = Base.eq_a in
    let Eq = Base.eq_b in
    let module Err = struct type t = err end in
    let module M = Make (Result (Base.Applicative) (Err)) in
    M.instance

  module List (Base : S) : S
  with type 'a t = 'a Base.t list = struct
    type 'a t = 'a Base.t list

    let map f l =
      List.map (Base.map f) l

    let pure x =
      [Base.pure x]

    let apply f r =
      match f with
      | [] -> []
      | _ ->
          let r = r () in
          List.concat_map (fun f ->
            List.map (fun v ->
              Base.apply f (fun () -> v)) r) f
  end

  let list (type a b c d) (base : (a, b, c, d) t) :
      (a, b list, c, d list) t =
    let module Base = (val (base ())) in
    let Eq = Base.eq_a in
    let Eq = Base.eq_b in
    let module M = Make (List (Base.Applicative)) in
    M.instance
end

module Arity (T : UnaryTypeS) = struct
  type ('a, 'a_t, 'f, 'result, 'is_empty) t =
    | O : ('a, 'a_t, 'a, 'a_t, [`Empty]) t
    | S : ('a, 'a_t, 'f, 'result, _) t ->
        ('a, 'a_t, 'x -> 'f, 'x T.t -> 'result, [`Not_empty]) t
end

module type SequenceSpecS = sig
  type 'a t

  type 'a desc =
    | Nil
    | Cons of 'a * 'a t

  val destruct : 'a t -> 'a desc

  val construct : 'a desc -> 'a t
end

module type SequenceS = sig
  type 'a s

  module Arity : sig
    type ('a, 'a_t, 'f, 'result, 'is_empty) t =
      | O : ('a, 'a_t, 'a, 'a_t, [`Empty]) t
      | S : ('a, 'a_t, 'f, 'result, _) t ->
          ('a, 'a_t, 'x -> 'f, 'x s -> 'result, [`Not_empty]) t
  end

  module Make (Applicative : Applicative.S) : sig
    val traverse :
        ('a Applicative.t, 'a s Applicative.t, 'f, 'result,
         [`Not_empty]) Arity.t -> 'f -> 'result
  end

  val traverse :
    ('a, 'b, 'a s, 'b_seq) Applicative.t ->
    ('b, 'b_seq, 'f, 'result, [`Not_empty]) Arity.t ->
    'f -> 'result
end

module Sequence (S : SequenceSpecS) : SequenceS with type 'a s = 'a S.t = struct
  type 'a s = 'a S.t

  module Arity = Arity (S)

  let cons hd tl =
    S.construct (Cons (hd, tl))

  module Make (Applicative : Applicative.S) = struct
    open Applicative

    let rec traverse : type a f result .
          (a Applicative.t, a S.t Applicative.t, f, result,
            [`Not_empty]) Arity.t -> f -> result =
    fun arity f ->
      let rec empty : type a f result w .
        (a Applicative.t, a S.t Applicative.t, f, result, w) Arity.t ->
          result =
      fun arity ->
        match arity with
        | O -> pure (S.construct Nil)
        | S arity' ->
            fun l ->
              match S.destruct l with
              | Nil -> empty arity'
              | Cons _ -> invalid_arg "traverse" in
      let rec non_empty : type a f result w .
        (a Applicative.t, a S.t Applicative.t, f, result, w) Arity.t -> f ->
          (unit -> result) -> result =
      fun arity f k ->
        match arity with
        | O -> apply (map cons f) k
        | S arity ->
            fun l ->
              match S.destruct l with
              | Nil -> invalid_arg "traverse"
              | Cons (hd, tl) ->
                  non_empty arity (f hd) (fun () -> k () tl) in
      let S arity' = arity in
      fun a ->
      match S.destruct a with
      | Nil -> empty arity'
      | Cons (hd, tl) -> non_empty arity' (f hd) (fun () -> traverse arity f tl)
  end

  let traverse (type a b b_seq f result)
    (app : (a, b, a S.t, b_seq) Applicative.t)
    (arity : (b, b_seq, f, result, [`Not_empty]) Arity.t)
    (f : f) : result =
    let module M = (val (app ())) in
    let Eq = M.eq_a in
    let Eq = M.eq_b in
    let module Traverse = Make (M.Applicative) in
    Traverse.traverse arity f
end

module List = Sequence (struct
  type 'a t = 'a list

  type 'a desc =
    | Nil
    | Cons of 'a * 'a t

  let destruct l =
    match l with
    | [] -> Nil
    | hd :: tl -> Cons (hd, tl)

  let construct d =
    match d with
    | Nil -> []
    | Cons (hd, tl) -> hd :: tl
end)

let list = List.traverse

module Seq = Sequence (struct
  type 'a t = 'a Seq.t

  type 'a desc = 'a Seq.node =
    | Nil
    | Cons of 'a * 'a t

  let destruct l = l ()

  let construct d () = d
end)

let seq = Seq.traverse
