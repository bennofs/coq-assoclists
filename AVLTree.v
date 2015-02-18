Require Import NArith.
Require Import Bool.
Require Import String.
Definition admit {T:Type} : T. Admitted.

Open Scope N.

Inductive sign : Type :=
  | negative : sign
  | zero : sign
  | positive : sign.

Definition sign_negate (a:sign) : sign :=
  match a with
    | negative => positive
    | zero     => zero
    | positive => negative
  end.

Definition sign_eq_dec (a b:sign) : {a = b} + {a <> b}.
Proof.
  destruct a; destruct b; auto || (right; discriminate 1).
Defined.

Definition beq_sign (a b:sign) : bool :=
  match (a,b) with
    | (negative, negative) => true
    | (zero, zero) => true
    | (positive, positive) => true
    | (_, _) => false
  end.

Inductive avl_tree (T:Type) : Type :=
  (* A branch consists of a balance, the left subtree, the key + value and the
   * right subtree. The balance if [positive] if the left subtree's height is greater
   * than the height of the right subtree. If the heights are the same, the balance is
   * [zero], otherwise it will be [negative].
   *)
  | avl_branch : sign -> avl_tree T -> N * T -> avl_tree T -> avl_tree T
  | avl_empty  : avl_tree T.
Arguments avl_branch [T] _ _ _ _.
Arguments avl_empty [T].

Fixpoint In {T:Type} (v:N * T) (t:avl_tree T) : Prop :=
  match t with
    | avl_empty => False
    | avl_branch _ l v' r => v = v' \/ In v l \/ In v r
  end.

Definition avl_singleton {T:Type} (k:N) (v:T) : avl_tree T :=
  avl_branch zero avl_empty (k,v) avl_empty.

Theorem not_In_empty : forall (T:Type) (k:N) (v:T), ~In (k,v) avl_empty.
Proof. intros. destruct 1. Qed.

Section Height.

  Variable T : Type.

  Fixpoint avl_height (t:avl_tree T) : N :=
    match t with
      | avl_empty => 0
      | avl_branch _ l _ r => N.max (avl_height l) (avl_height r) + 1
    end.

  Example avl_height_ex_empty : avl_height avl_empty = 0.
  Proof. reflexivity. Qed.

  Example avl_height_ex_1 :
    forall a b c d : T,
      avl_height
        (avl_branch
           negative
           (avl_singleton 1 a)
           (2,b)
           (avl_branch
              positive
              (avl_singleton 3 c)
              (4,d)
              avl_empty)) = 3.
  Proof. reflexivity. Qed.

End Height.

Section Invariants.

  Variable T : Type.

  Fixpoint forall_keys (f:N -> Prop) (t:avl_tree T) : Prop :=
    match t with
      | avl_empty => True
      | avl_branch _ l p r => f (fst p) /\ forall_keys f l /\ forall_keys f r
    end.
  Global Arguments forall_keys : default implicits.


  Theorem all_keys_greater_chain :
    forall (k k':N) (t:avl_tree T),
      k' < k -> forall_keys (N.lt k) t -> forall_keys (N.lt k') t.
  Proof.
    Hint Resolve N.lt_trans.
    intros k k' t ineq H.
    induction t as [b l IHl [k'' v] r IHr|];
      hnf in *;
      intuition eauto.
  Qed.

  Theorem all_keys_smaller_chain :
    forall (k k':N) (t:avl_tree T),
      k < k' -> forall_keys (N.gt k) t -> forall_keys (N.gt k') t.
  Proof.
    Hint Resolve N.lt_trans.
    intros k k' t ineq H.
    induction t as [b l IHl [k'' v] r IHr|];
      hnf in *;
      rewrite_all N.gt_lt_iff;
      intuition eauto.
  Qed.

  Theorem all_keys_greater_chain_eq :
    forall (k k':N) (t:avl_tree T),
      k' <= k -> forall_keys (N.lt k) t -> forall_keys (N.lt k') t.
  Proof.
    Hint Resolve N.le_lt_trans.
    intros k k' t ineq H.
    induction t as [b l IH [k'' v] r IHr|]; simpl in *; intuition eauto.
  Qed.

  Lemma invert_tuple_eq :
    forall (A B:Type) (a a':A) (b b':B),
      (a,b) = (a',b') <-> a = a' /\ b = b'.
  Proof. split; inversion 1; subst; auto. Qed.

  Theorem forall_keys_In_iff :
    forall (P:N -> Prop) (t:avl_tree T),
      forall_keys P t <-> (forall p, In p t -> P (fst p)).
  Proof.
    intros P t. induction t as [b l IHl p r IHr|].
    - simpl. rewrite IHl. rewrite IHr. split; intuition (subst; eauto).
    - split; simpl; intuition auto.
  Qed.

  Fixpoint binary_tree_invariant (t:avl_tree T) : Prop :=
    match t with
      | avl_empty => True
      | avl_branch _ l p r =>
        forall_keys (N.gt (fst p)) l /\ forall_keys (N.lt (fst p)) r /\
        binary_tree_invariant l /\ binary_tree_invariant r
    end.
  Global Arguments binary_tree_invariant : default implicits.

End Invariants.

Section Node.

  Variable T : Type.

  (* Calculate the balance change from the height change of a subtree. *)
  Let balance_change (a:sign + sign) : sign :=
    match a with
      | inl s  => s
      | inr s => sign_negate s
    end.

  (* Apply a balance change.
   * Returns the new balance if we don't need to do a rotation.
   * Otherwise, returns true if the left tree is higher or
     false if the right tree is higher.
   *)
  Let apply_balance_change (c:sign) (b:sign) : bool + sign :=
    match c with
      | negative =>
        match b with
          | negative => inl false
          | zero     => inr negative
          | positive => inr zero
        end
      | zero     => inr b
      | positive =>
        match b with
          | negative => inr zero
          | zero => inr positive
          | positive => inl true
        end
    end.

  (* Return the height change of the subtree (discarding which subtree changed). *)
  Let height_change (s:sign + sign) : sign := match s with | inr x => x | inl x => x end.

  (* Rotation for when the right subtree is higher *)
  Let rotate_right (removed:bool) (l:avl_tree T) (p:N * T) (r:avl_tree T)
  : avl_tree T * sign :=
    match r with
      | avl_branch positive (avl_branch rlb rll rlp rlr) rp rr =>
        ( avl_branch
            zero
            (avl_branch (sign_negate rlb) l p rll)
            rlp
            (avl_branch (sign_negate rlb) rlr rp rr)
          , if removed then negative else zero
        )
      | avl_branch b rl rp rr =>
        let b' := if beq_sign b zero then positive else zero in
        ( avl_branch
            b'
            (avl_branch (sign_negate b') l p rl)
            rp
            rr
          , if removed && beq_sign b negative then negative else zero
        )
      | avl_empty =>
        (* This branch should never happen, because if the right subtree has height zero,
         * it cannot be higher than the left subtree.
         * In this case, we still return the tree without doing a rotation, because that
         * way the invariant of the tree is preserved, which makes the proofs simpler.
         *)
        let b := match l with
                   | avl_empty => zero
                   | _ => positive
                 end
        in (avl_branch b l p r, zero)
    end.

  (* Rotation for when the left subtree is higher *)
  Let rotate_left (removed:bool) (l:avl_tree T) (p:N * T) (r:avl_tree T)
  : avl_tree T * sign :=
    match l with
      | avl_branch negative ll lp (avl_branch lrb lrl lrp lrr) =>
        ( avl_branch
            zero
            (avl_branch (sign_negate lrb) ll lp lrl)
            lrp
            (avl_branch (sign_negate lrb) lrr p r)
          , if removed then negative else zero
        )
      | avl_branch b ll lp lr =>
        let b' := if beq_sign zero b then negative else zero in
        ( avl_branch
            b'
            ll
            lp
            (avl_branch (sign_negate b') lr p r)
          , if removed && beq_sign b positive then negative else zero
        )
      | avl_empty =>
        (* See comment for this branch in [rotate_right] *)
        let b := match r with
                   | avl_empty => zero
                   | _         => negative
                 end
        in (avl_branch b avl_empty p r, zero)
    end.

  (* This function recreates a tree node after one of it's subtrees changed.
   *
   * Arguments:
   *
   * - [b] is the balance of the node before the change.
   * - [s] is either [inl c] or [inr c], where [c : sign] is the change in the height
   *   of the left or right subtree respectively (the other subtree's height must stay
   *   the same). [c] is positive if the height increased by 1, zero if it stayed the
   *   same or negative if it decreased by 1.
   * - [l] is the new left subtree.
   * - [p] is the value at the node (should be the same as before the change)
   * - [r] is the new right subtree
   *
   * Given these arguments, the function will compute the new balance and rebalance the
   * tree if necessary. It returns the new tree and the height change for the whole
   * new tree.
   *)
  Definition node (b:sign) (s:sign + sign) (l:avl_tree T) (p:N * T) (r:avl_tree T)
  : avl_tree T * sign :=
    if beq_sign (height_change s) zero
    then
      (* In this case, the subtree height did not change at all so the balance
       * stays the same.
       *)
      (avl_branch b l p r, zero)
    else let hd := height_change s in
       match apply_balance_change (balance_change s) b with
        | inl true  => rotate_left (beq_sign hd negative) l p r
        | inl false => rotate_right (beq_sign hd negative) l p r
        | inr b'    =>
          if beq_sign hd positive && beq_sign b' zero
          then
            (* The subtree height increased, but the balance is now zero. This means
             * that the height of the smaller subtree must have increased (if not, the
             * node would be unbalanced), so the height of the node did not change *)
            (avl_branch b' l p r, zero)
          else
            if beq_sign hd negative && negb (beq_sign b' zero)
            then
              (* The subtree height decreased, and the node's balance is not zero. This
               * means that the balance was zero before, and because we only change
               * one subtree, the height of the node cannot have changed if it is still
               * balanced.
               *)
              (avl_branch b' l p r, zero)
            else
              (* In all other cases, the change in the height of the node is the same
               * as the subtree height change.
               *)
              (avl_branch b' l p r, hd)
       end.
  Global Arguments node : default implicits.

  Lemma rotate_left_binary_tree_invariant :
    forall (b:bool) (p:N * T) (l r:avl_tree T),
      binary_tree_invariant l -> binary_tree_invariant r ->
      forall_keys (N.gt (fst p)) l -> forall_keys (N.lt (fst p)) r ->
      binary_tree_invariant (fst (rotate_left b l p r)).
  Proof.
    Hint Resolve all_keys_smaller_chain all_keys_greater_chain.
    intros b p l r bt_inv_l bt_inv_r l_smaller r_greater.
    destruct l as [lb ll lp lr|].
    - simpl. destruct lb; destruct lr as [lrb lrl lrp lrr|];
          simpl in *;
          rewrite_all N.gt_lt_iff;
          intuition eauto.
    - simpl. auto.
  Qed.

  Lemma rotate_right_binary_tree_invariant :
    forall (b:bool) (p:N * T) (l r:avl_tree T),
      binary_tree_invariant l -> binary_tree_invariant r ->
      forall_keys (N.gt (fst p)) l -> forall_keys (N.lt (fst p)) r ->
      binary_tree_invariant (fst (rotate_right b l p r)).
  Proof.
    Hint Resolve all_keys_smaller_chain all_keys_greater_chain.
    intros b p l r bt_inv_l bt_inv_r l_smaller r_greater.
    destruct r as [rb rl rp rr|].
    - simpl. destruct rb; destruct rl as [rlb rll rlp rlr|];
        simpl in *; simpl in *;
        rewrite_all N.gt_lt_iff; intuition eauto.
    - simpl. auto.
  Qed.

  Lemma rotate_left_same_elements :
    forall (b:bool) (p p':N * T) (l r:avl_tree T),
      In p' (avl_branch zero l p r) <->
      In p' (fst (rotate_left b l p r)).
  Proof.
    intros b p p' l r.
    destruct l as [lb ll lp lr|].
    - simpl. destruct lb;
        destruct lr as [lrb lrl lrp lrr|];
        simpl in *;
        intuition (subst; assumption || discriminate).
    - simpl. reflexivity.
  Qed.

  Lemma rotate_right_same_elements :
    forall (b:bool) (p p':N * T) (l r:avl_tree T),
      In p' (avl_branch zero l p r) <->
      In p' (fst (rotate_right b l p r)).
  Proof.
    intros b p p' l r.
    destruct r as [rb rl rp rr|].
    - simpl. destruct rb;
        destruct rl as [rlb rll rlp rlr|];
        simpl in *;
        intuition (subst; assumption || discriminate).
    - simpl. reflexivity.
  Qed.

  Theorem node_binary_tree_invariant :
    forall (b:sign) (s:sign + sign) (l r:avl_tree T) (p:N * T),
      binary_tree_invariant l -> binary_tree_invariant r ->
      forall_keys (N.gt (fst p)) l -> forall_keys (N.lt (fst p)) r ->
      binary_tree_invariant (fst (node b s l p r)).
  Proof.
    Hint Resolve rotate_right_binary_tree_invariant rotate_left_binary_tree_invariant.
    intros b s l p v bt_inv_l bt_inv_r l_smaller r_greater. unfold node.
    destruct s as [s|s]; destruct s; destruct b; simpl; auto.
  Qed.

  Theorem node_same_elements :
    forall (b:sign) (s:sign + sign) (l r:avl_tree T) (p p':N * T),
      p' = p \/ In p' l \/ In p' r <->
      In p' (fst (node b s l p r)).
  Proof.
    Hint Rewrite <- rotate_right_same_elements rotate_left_same_elements : core.
    intros b s l r p p'.
    destruct s as [s|s]; destruct s; destruct b; unfold node; simpl;
    autorewrite with core; simpl; split; trivial.
  Qed.

  Lemma node_preserve_forall :
    forall (l r:avl_tree T) (p:N * T) (b:sign) (s:sign + sign) (P:N -> Prop),
      forall_keys P l -> forall_keys P r -> P (fst p) ->
      forall_keys P (fst (node b s l p r)).
  Proof.
    Hint Rewrite -> forall_keys_In_iff.
    Hint Rewrite <- node_same_elements.
    intros l r p b s P forall_l forall_r P_k.
    apply forall_keys_In_iff. intros. autorewrite with core in *.
    rewrite_all invert_tuple_eq. intuition (subst; simpl in *; eauto).
  Qed.

End Node.

Section Insert.

  Variable T : Type.

  Fixpoint avl_insert_go (k:N) (v:T) (t:avl_tree T) : avl_tree T * sign :=
    match t with
      | avl_empty => (avl_branch zero avl_empty (k,v) avl_empty, positive)
      | avl_branch b l (k',v') r =>
        match N.compare k k' with
          | Eq => (avl_branch b l (k,v) r, zero)
          | Lt =>
            let (l', s) := avl_insert_go k v l
            in node b (inl s) l' (k',v') r
          | Gt =>
            let (r', s) := avl_insert_go k v r
            in node b (inr s) l (k',v') r'
        end
    end.

  Definition avl_insert (k:N) (v:T) (t:avl_tree T) : avl_tree T :=
    fst (avl_insert_go k v t).
  Global Arguments avl_insert : default implicits.

  Example avl_insert_ex1 :
    forall a b c : T,
      avl_insert 1 a (avl_insert 2 b (avl_insert 3 c avl_empty)) =
      avl_branch zero
                 (avl_branch zero avl_empty (1,a) avl_empty)
                 (2,b)
                 (avl_branch zero avl_empty (3,c) avl_empty).
  Proof. intros. unfold avl_insert. simpl. reflexivity. Qed.

  Example avl_insert_ex2 :
    forall a b c d : T,
      avl_insert 3 c (avl_insert 4 d (avl_insert 2 b (avl_insert 1 a avl_empty))) =
      avl_branch negative
                 (avl_branch zero avl_empty (1,a) avl_empty)
                 (2,b)
                 (avl_branch positive
                             (avl_branch zero avl_empty (3,c) avl_empty)
                             (4,d)
                             avl_empty).
  Proof. intros. reflexivity. Qed.

  Example avl_insert_ex3 :
    forall a b c d : T,
      avl_insert 3 c (avl_insert 2 b (avl_insert 4 d (avl_insert 1 a avl_empty))) =
      avl_insert 3 c (avl_insert 4 d (avl_insert 2 b (avl_insert 1 a avl_empty))).
  Proof. intros. reflexivity. Qed.

  Theorem insert_In :
    forall (k:N) (v:T) (t:avl_tree T),
      In (k,v) (avl_insert k v t).
  Proof.
    Hint Resolve -> node_same_elements.
    intros k v t. induction t as [b l IHl [k' v'] r IHr|].
    - unfold avl_insert in *. simpl. destruct (N.compare k k').
      + simpl. tauto.
      + destruct (avl_insert_go k v l). auto.
      + destruct (avl_insert_go k v r). auto.
    - simpl. auto.
  Qed.

  Theorem insert_preserve_other :
    forall (k k':N) (v v':T) (t:avl_tree T),
      k <> k' -> (In (k,v) t <-> In (k,v) (avl_insert k' v' t)).
  Proof.
    Hint Rewrite invert_tuple_eq : core.
    Hint Rewrite <- node_same_elements : core.
    intros k k' v v' t ineq. induction t as [b l IHl [k'' v''] r IHr|].
    - unfold avl_insert in *. simpl. destruct (N.compare k' k'') eqn:E.
      + apply N.compare_eq_iff in E. subst k''. simpl. rewrite_all invert_tuple_eq.
        split; intuition (assumption || (exfalso; auto)).
      + destruct (avl_insert_go k' v' l). simpl in *.
        autorewrite with core. rewrite IHl. reflexivity.
      + destruct (avl_insert_go k' v' r). simpl in *.
        autorewrite with core. rewrite IHr. reflexivity.
    - simpl. autorewrite with core. intuition auto.
  Qed.

  Theorem insert_forall_keys :
    forall (k:N) (v:T) (t:avl_tree T) (P:N -> Prop),
      forall_keys P t -> P k -> forall_keys P (avl_insert k v t).
  Proof.
    Hint Resolve <- insert_preserve_other.
    setoid_rewrite forall_keys_In_iff. intros k v t P forall_t for_P [k' v'].
    destruct (N.eq_dec k k'); subst; eauto.
  Qed.

  Theorem insert_binary_tree_invariant :
    forall (k:N) (v:T) (t:avl_tree T),
      binary_tree_invariant t -> binary_tree_invariant (avl_insert k v t).
  Proof.
    Hint Resolve node_binary_tree_invariant insert_forall_keys.
    Hint Resolve -> N.gt_lt_iff.
    Hint Resolve <- N.gt_lt_iff.
    intros k v t bt_inv_t. induction t as [b l IHl [k' v'] r IHr|].
    - unfold avl_insert in *. simpl. destruct (N.compare_spec k k') as [C|C|C].
      + simpl in *. subst k'. auto.
      + destruct (avl_insert_go k v l) as [a s] eqn:X.
        replace a with (avl_insert k v l) in * by (unfold avl_insert; rewrite X; auto).
        simpl in *. intuition auto.
      + destruct (avl_insert_go k v r) as [a s] eqn:X.
        replace a with (avl_insert k v r) in * by (unfold avl_insert; rewrite X; auto).
        simpl in *. intuition auto.
    - simpl. auto.
  Qed.

End Insert.

Section Remove.
  Variable T : Type.

  Fixpoint avl_find_minimum (t:avl_tree T) (def:N * T): (N * T) :=
    match t with
      | avl_empty => def
      | avl_branch lb ll lp lr => avl_find_minimum ll lp
    end.

  Example avl_find_minimum_ex1 :
    forall a b c d : T,
      avl_find_minimum
        (avl_insert 1 a (avl_insert 2 b (avl_insert 3 c (avl_insert 4 d avl_empty))))
        (5,d)
      = (1,a).
  Proof. intros. reflexivity. Qed.

  Theorem avl_find_minimum_In :
    forall (t:avl_tree T) (def:N * T),
      In (avl_find_minimum t def) t \/ avl_find_minimum t def = def.
  Proof.
    intros t. induction t as [b l IHl p r IHr|].
    - intros def. clear IHr. specialize IHl with p. simpl in *. intuition eauto.
    - intros. simpl. tauto.
  Qed.

  Theorem avl_find_minimum_is_min :
    forall (t:avl_tree T) (def:N * T),
      binary_tree_invariant t ->
      forall_keys (N.le (fst (avl_find_minimum t def))) t.
  Proof.
    Hint Resolve N.gt_lt N.lt_le_incl.
    intros t def bt_inv. generalize dependent def. induction t as [b l IHl p r IHr|].
    - intros def. clear IHr. simpl. specialize IHl with p. destruct p as [k v].
      simpl in *.
      assert (min_le_k: fst (avl_find_minimum l (k,v)) <= k).
      {
        destruct avl_find_minimum_In with (t := l) (def := (k,v)) as [H|H].
        - rewrite_all forall_keys_In_iff. intuition eauto.
        - rewrite H. reflexivity.
      }
      repeat split.
      + auto.
      + intuition auto.
      + rewrite_all forall_keys_In_iff. intros p in_r.
        rewrite min_le_k. apply N.lt_le_incl. intuition eauto.
    - simpl. auto.
  Qed.

  Fixpoint avl_remove_minimum (b:sign) (l:avl_tree T) (p:N * T) (r:avl_tree T)
  : (avl_tree T * sign) :=
    match l with
      | avl_empty => (r, negative)
      | avl_branch lb ll lp lr =>
        let (l',s) := avl_remove_minimum lb ll lp lr
        in node b (inl s) l' p r
    end.

  Theorem avl_remove_minimum_preserve_other :
    forall (l:avl_tree T) (p':N * T) (b:sign) (p:N * T) (r:avl_tree T),
      p' = p \/ In p' l \/ In p' r <->
      (In p' (fst (avl_remove_minimum b l p r)) \/ p' = avl_find_minimum l p).
  Proof.
    intros l p'. induction l as [lb ll IHll lp lr IHlr|].
    - intros b p r. simpl in *.
      destruct (avl_remove_minimum lb ll lp lr) as [l' s] eqn:rec_eq.
      rewrite <- node_same_elements.
      assert (l'_eq: l' = fst (l', s)) by reflexivity. rewrite <- rec_eq in l'_eq.
      subst l'. rewrite IHll with (b := lb). tauto.
    - intros. simpl. tauto.
  Qed.

  Theorem avl_remove_minimum_subset :
    forall (l:avl_tree T) (p':N * T) (b:sign) (p:N * T) (r:avl_tree T),
      In p' (fst (avl_remove_minimum b l p r)) -> p' = p \/ In p' l \/ In p' r.
  Proof.
    intros l p'. induction l as [lb ll IHll lp lr IHlr|].
    - intros b p r. clear IHlr. specialize IHll with lb lp lr. simpl in *.
      destruct (avl_remove_minimum lb ll lp lr) as [l' s] eqn:rec_eq.
      replace l' with (fst (l',s)) by reflexivity.
      rewrite <- node_same_elements. intuition auto.
    - intros. simpl. auto.
  Qed.

  Theorem avl_remove_preserve_forall :
    forall (P:N -> Prop) (b:sign) (l:avl_tree T) (p:N * T) (r:avl_tree T),
      P (fst p) /\ forall_keys P l /\ forall_keys P r ->
      forall_keys P (fst (avl_remove_minimum b l p r)).
  Proof.
    Hint Resolve avl_remove_minimum_subset.
    intros. rewrite_all forall_keys_In_iff. intros p' in_rm.
    apply avl_remove_minimum_subset in in_rm. intuition (subst; eauto).
  Qed.

  Theorem avl_remove_minimum_binary_tree_invariant:
    forall (l:avl_tree T) (b:sign) (p:N * T) (r:avl_tree T),
      binary_tree_invariant (avl_branch b l p r) ->
      binary_tree_invariant (fst (avl_remove_minimum b l p r)).
  Proof.
    Hint Resolve node_binary_tree_invariant avl_remove_preserve_forall.
    intros l. induction l as [lb ll IHll lp lr IHlr|].
    - intros b p r bt_inv. simpl in *. clear IHlr. specialize IHll with lb lp lr.
      simpl in *. destruct p as [k v]. destruct lp as [lk lv].
      destruct (avl_remove_minimum lb ll (lk,lv) lr) as [l' s] eqn:min_eq.
      replace l' with (fst (l',s)) by reflexivity. rewrite_all <- min_eq.
      intuition eauto.
    - intros b [k v] r. simpl in *. tauto.
  Qed.

  Theorem avl_remove_minimum_min_not_In :
    forall (l:avl_tree T) (b:sign) (p:N * T) (r:avl_tree T),
      binary_tree_invariant (avl_branch b l p r) ->
      ~In (avl_find_minimum l p) (fst (avl_remove_minimum b l p r)).
  Proof.
    Hint Resolve N.gt_lt.
    intros l. induction l as [lb ll IHll lp lr IHlr|].
    - intros b p r bt_inv H. simpl in *.
      destruct (avl_remove_minimum lb ll lp lr) as [l' s] eqn:rec_eq.
      rewrite <- node_same_elements in H. specialize IHll with lb lp lr.
      clear IHlr. replace l' with (fst (l', s)) in H by reflexivity.
      rewrite_all <- rec_eq. rewrite_all forall_keys_In_iff. destruct H as [H|[H|H]].
      + destruct avl_find_minimum_In with (t := ll) (def := lp) as [P|P].
        * apply N.lt_irrefl with (x := fst p). subst. intuition eauto.
        * apply N.lt_irrefl with (x := fst p). rewrite_all P. subst. intuition auto.
      + apply IHll; intuition eauto.
      + destruct avl_find_minimum_In with (t := ll) (def := lp) as [P|P].
        * apply N.lt_asymm with (n := fst p) (m := fst (avl_find_minimum ll lp));
            intuition eauto.
        * rewrite_all P. apply N.lt_asymm with (n := fst lp) (m := fst p);
            intuition eauto.
    - intros b p r inv_bt H. simpl in *. rewrite_all forall_keys_In_iff.
      apply N.lt_irrefl with (x := fst p). intuition eauto.
  Qed.

  Theorem avl_remove_minimum_removes_minimum :
    forall (l:avl_tree T) (min_k:N) (b:sign) (p:N * T) (r:avl_tree T),
      binary_tree_invariant (avl_branch b l p r) ->
      forall_keys (N.le min_k) (avl_branch b l p r) ->
      forall_keys (N.lt min_k) (fst (avl_remove_minimum b l p r)).
  Proof.
    Hint Resolve all_keys_greater_chain_eq all_keys_greater_chain N.le_lt_trans
         node_preserve_forall.
    intros l min_k. induction l as [lb ll IHll lp lr IHlr|].
    - intros b p r bt_inv H. simpl in *. clear IHlr. specialize IHll with lb lp lr.
      destruct (avl_remove_minimum lb ll lp lr) as [l' s] eqn:rec_eq.
      replace l' with (fst (l', s)) by reflexivity. rewrite_all <- rec_eq.
      intuition eauto.
    - intros. simpl in *. intuition eauto.
  Qed.

  Theorem avl_remove_minimum_all_greater :
    forall (l:avl_tree T) (b:sign) (p:N * T) (r:avl_tree T),
      binary_tree_invariant (avl_branch b l p r) ->
      forall_keys (N.lt (fst (avl_find_minimum l p))) (fst (avl_remove_minimum b l p r)).
  Proof.
    intros l b p r bt_inv. apply avl_remove_minimum_removes_minimum.
    - assumption.
    - simpl.
      destruct avl_find_minimum_In with (t := l) (def := p) as [H|H].
      + simpl in *. repeat split.
        * rewrite_all forall_keys_In_iff. intuition eauto.
        * apply avl_find_minimum_is_min. tauto.
        * rewrite_all forall_keys_In_iff.
          assert (pk_gt: fst (avl_find_minimum l p) <= fst p) by intuition eauto.
          intros p' in_r.
          assert (p'_gt: fst p < fst p') by intuition auto.
          eapply N.le_lt_trans in p'_gt; eauto.
      + simpl in *. rewrite_all H. repeat split.
        * reflexivity.
        * rewrite <- H. apply avl_find_minimum_is_min. tauto.
        * rewrite_all forall_keys_In_iff. intros p' in_r. apply N.lt_le_incl.
          intuition eauto.
  Qed.


  Definition avl_remove_top (b:sign) (l:avl_tree T) (r:avl_tree T) : avl_tree T * sign :=
    match r with
      | avl_empty => (l, negative)
      | avl_branch rb rl rp rr =>
        let (r',s) := avl_remove_minimum rb rl rp rr
        in node b (inr s) l (avl_find_minimum rl rp) r'
    end.

  Theorem avl_remove_top_preserve_other :
    forall (b:sign) (l:avl_tree T) (r:avl_tree T) (p:N * T),
      (In p r \/ In p l) <-> In p (fst (avl_remove_top b l r)).
  Proof.
    intros b l r p. destruct r as [rb rl rp rr|] eqn:r_eq.
    - simpl. destruct (avl_remove_minimum rb rl rp rr) as [r' s] eqn:rm_min_eq.
      replace r' with (fst (r',s)) by reflexivity. rewrite <- rm_min_eq.
      rewrite <- node_same_elements.
      rewrite avl_remove_minimum_preserve_other with (b := rb).
      tauto.
    - subst. simpl. tauto.
  Qed.

  Theorem avl_remove_top_binary_tree_invariant :
    forall (b:sign) (l:avl_tree T) (r:avl_tree T) (k:N),
      forall_keys (N.gt k) l -> forall_keys (N.lt k) r ->
      binary_tree_invariant l -> binary_tree_invariant r ->
      binary_tree_invariant (fst (avl_remove_top b l r)).
  Proof.
    Hint Resolve node_binary_tree_invariant avl_remove_minimum_binary_tree_invariant
      avl_remove_minimum_subset.
    intros b l r k k_gt_l k_lt_r bt_inv_l bt_inv_r. destruct r as [rb rl rp rr|].
    - simpl in *. destruct (avl_remove_minimum rb rl rp rr) as [r' s] eqn:rm_min_eq.
      replace r' with (fst (r', s)) by reflexivity. rewrite_all <- rm_min_eq.
      apply node_binary_tree_invariant.
      + intuition auto.
      + apply avl_remove_minimum_binary_tree_invariant. simpl. intuition auto.
      + destruct avl_find_minimum_In with rl rp as [H|H].
        * rewrite_all forall_keys_In_iff. intros p' in_l.
          apply N.lt_gt. apply N.lt_trans with k; intuition eauto.
        * rewrite H. apply all_keys_smaller_chain with k; intuition eauto.
      + apply avl_remove_minimum_all_greater. simpl. intuition eauto.
    - simpl in *. auto.
  Qed.

  Fixpoint avl_remove_go (k:N) (t:avl_tree T) : avl_tree T * sign :=
    match t with
      | avl_empty => (avl_empty, zero)
      | avl_branch b l (k',v') r =>
        match N.compare k k' with
          | Lt => let (l',s) := avl_remove_go k l in node b (inl s) l' (k',v') r
          | Gt => let (r',s) := avl_remove_go k r in node b (inr s) l (k',v') r'
          | Eq => avl_remove_top b l r
        end
    end.

  Definition avl_remove (k:N) (t:avl_tree T) : avl_tree T := fst (avl_remove_go k t).

  Example avl_remove_ex1 :
    forall a b c : T,
      avl_remove 2 (avl_insert 1 a (avl_insert 2 b (avl_insert 3 c avl_empty))) =
      avl_branch positive (avl_insert 1 a avl_empty) (3,c) avl_empty.
  Proof. reflexivity. Qed.

  Example avl_remove_ex2 :
    forall a b c d : T,
      avl_remove
        2
        (avl_insert 3 c (avl_insert 4 d (avl_insert 2 b (avl_insert 1 a avl_empty)))) =
      avl_insert 1 a (avl_insert 4 d (avl_insert 3 c avl_empty)).
  Proof. reflexivity. Qed.

  Example avl_remove_ex3 :
    forall a b c d e f g h : T,
      avl_remove
        4
        (avl_branch
           positive
           (avl_branch
              positive
              (avl_branch
                 zero
                 (avl_singleton 1 a)
                 (2,b)
                 (avl_singleton 3 c))
              (4,d)
              (avl_singleton 5 e))
           (6,f)
           (avl_branch negative avl_empty (7,g) (avl_singleton 8 h)))
      = avl_branch
          positive
          (avl_branch
             negative
             (avl_singleton 1 a)
             (2,b)
             (avl_branch positive (avl_singleton 3 c) (5,e) avl_empty))
          (6,f)
          (avl_branch negative avl_empty (7,g) (avl_singleton 8 h)).
  Proof. reflexivity. Qed.

  Theorem remove_not_In :
    forall k v t,
      binary_tree_invariant t ->
      ~In (k,v) (avl_remove k t).
  Proof.
    intros k v t bt_inv_t. induction t as [b l IHl p r IHr|].
    - unfold avl_remove. simpl. destruct p as [k' v'] eqn:peq.
      destruct (N.compare_spec k k') as [C|C|C].
      + intros H. rewrite <- avl_remove_top_preserve_other in H. simpl in *.
        rewrite_all forall_keys_In_iff. subst k. apply N.lt_irrefl with k'.
        replace k' with (fst (k', v)) by reflexivity. intuition eauto.
      + destruct (avl_remove_go k l) as [l' s] eqn:rec_eq.
        replace l' with (fst (l', s)) by reflexivity.
        rewrite <- rec_eq. unfold avl_remove in *. rewrite <- node_same_elements.
        rewrite invert_tuple_eq. intros H. unfold not in *. simpl in *.
        rewrite_all forall_keys_In_iff.
        intuition (subst; (eapply N.lt_irrefl; eauto) || eauto).
      + destruct (avl_remove_go k r) as [r' s] eqn:rec_eq.
        replace r' with (fst (r',s)) by reflexivity.
        rewrite <- rec_eq. unfold avl_remove in *. rewrite <- node_same_elements.
        rewrite invert_tuple_eq. intros H. unfold not in *. simpl in *.
        rewrite_all forall_keys_In_iff.
        intuition (subst; (eapply N.lt_irrefl; eauto) || eauto).
    - simpl. auto.
  Qed.

  Theorem remove_preserve_other :
    forall (p:N * T) (k:N) (t:avl_tree T),
      (In p t <-> (In p (avl_remove k t) \/ (fst p = k /\ In p t))).
  Proof.
    intros. unfold avl_remove. induction t as [b l IHl [k' v'] r IHr|].
    - simpl. destruct (N.compare_spec k k') as [C|C|C].
      + rewrite <- avl_remove_top_preserve_other.
        split; intuition (subst; auto).
      + destruct (avl_remove_go k l) as [l' s] eqn:rec_eq.
        rewrite <- node_same_elements. replace l' with (fst (l', s)) by reflexivity.
        rewrite IHl. tauto.
      + destruct (avl_remove_go k r) as [r' s] eqn:rec_eq.
        rewrite <- node_same_elements. replace r' with (fst (r', s)) by reflexivity.
        rewrite IHr. tauto.
    - simpl. tauto.
  Qed.

  Theorem remove_subset :
    forall (p:N * T) (k:N) (t:avl_tree T),
      In p (avl_remove k t) -> In p t.
  Proof.
    intros. rewrite remove_preserve_other with (k := k). tauto.
  Qed.

  Theorem remove_preserve_forall :
    forall (P:N -> Prop) (k:N) (t:avl_tree T),
      forall_keys P t -> forall_keys P (avl_remove k t).
  Proof.
    Hint Resolve remove_subset.
    intros P k t H. rewrite_all forall_keys_In_iff. intros p in_rm.
    eauto.
  Qed.

  Theorem remove_binary_tree_invariant :
    forall (k:N) (t:avl_tree T),
      binary_tree_invariant t -> binary_tree_invariant (avl_remove k t).
  Proof.
    Hint Resolve avl_remove_top_binary_tree_invariant node_binary_tree_invariant
         remove_preserve_forall.
    intros k t bt_inv. unfold avl_remove. induction t as [b l IHl [k' v'] r IHr|].
    - simpl. destruct (N.compare_spec k k') as [C|C|C].
      + subst k'. simpl in *. intuition eauto.
      + destruct (avl_remove_go k l) as [l' s] eqn:rec_eq.
        replace l' with (fst (l', s)) by reflexivity. rewrite_all <- rec_eq.
        simpl in *. fold (avl_remove k l) in *. intuition eauto.
      + destruct (avl_remove_go k r) as [r' s] eqn:rec_eq.
        replace r' with (fst (r', s)) by reflexivity. rewrite_all <- rec_eq.
        simpl in *. fold (avl_remove k r) in *. intuition eauto.
    - simpl. constructor.
  Qed.

Section Lookup.

  Variable T : Type.

  Fixpoint avl_lookup (k:N) (t:avl_tree T) : option T :=
    match t with
      | avl_empty => None
      | avl_branch _ l (k',v) r =>
        match N.compare k k' with
          | Lt => avl_lookup k l
          | Gt => avl_lookup k r
          | Eq => Some v
        end
    end.

  Example avl_lookup_ex1 :
    forall a b c d : T,
      avl_lookup
        4
        (avl_insert 3 c (avl_insert 4 d (avl_insert 2 b (avl_insert 1 a avl_empty))))
      = Some d.
  Proof. reflexivity. Qed.

  Example avl_lookup_ex2 :
    forall a b c d : T,
      avl_lookup
        5
        (avl_insert 3 c (avl_insert 4 d (avl_insert 2 b (avl_insert 1 a avl_empty))))
      = None.
  Proof. reflexivity. Qed.

End Lookup.