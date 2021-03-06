type token_p = 
| Token_info
| Balance of key_hash
| Transfer_token of (key_hash * nat)
| Approve of (key_hash * nat)
| Transfer_token_from_approve_dict of (key_hash * key_hash * nat)
| Allowance of (key_hash * key_hash)

type token_r_variant =
| General_return
| Token_info_return of nat * nat * string * string
| Balance_return of nat

type token_r = nat * token_r_variant
type token_contract = (token_p, token_r) contract

type token = nat
type odd_index = nat
type odd_decimal = nat    (* it should be div 1000 *)

type state =
| Open
| Disabled of string
| Settled

type info = {
  name : string;
  created_date : timestamp;
  bet_time_range : timestamp * timestamp;
  report_time_range : timestamp * timestamp;
  odds_lst : string list;
}

type bookmaker = {
  key : key_hash option;
  margin : token;
  odds : (odd_index, odd_decimal) map;
}

type storage_t = {
  self_key : key_hash;
  token_contract : token_contract;

  state : state;
  info : info;
  bookmaker : bookmaker;

  all_token_amount : token;
  all_bets_token_amount: (odd_index, token) map;
  orders : (odd_index, (key_hash * odd_decimal * token) list) map;
  reports : (key_hash, odd_index) map;
  distribution: (key_hash, token) map;
}

type bet_parameter_t = 
| Check
| Override of storage_t

(* =============== All aboves are commonly used in betting contracts =============== *)

type parameter_t = token * (bet_parameter_t, storage_t) contract

type return_t = 
| Success
| Transfer_fail of nat
| Fail of string

let%entry main 
  (parameter : parameter_t) 
  (storage : parameter_t * storage_t) 
  [%return : return_t] =
  let (_, bet_contract) = parameter in
  let (_, bet_storage) = storage in
  let (bet_storage, storage) = Contract.call bet_contract 0tz (parameter, bet_storage) Check in
  let (parameter, _) = storage in
  let source = Contract.manager (Source : (unit, unit) contract) in

  let isvalid = match bet_storage.bookmaker.key with
  | None -> true
  | Some key -> 
    if key = source then 
      true
    else 
      false
  in
  if isvalid then
    let (token, _) = parameter in
    let (result, storage) = Contract.call bet_storage.token_contract 0tz (parameter, bet_storage) (Transfer_token_from_approve_dict (source, bet_storage.self_key, token)) in
    if result.(0) = 0p then
      let (parameter, bet_storage) = storage in
      let (token, bet_contract) = parameter in
      let bet_storage = bet_storage.bookmaker.margin <- bet_storage.bookmaker.margin + token in
      let bet_storage = 
        match bet_storage.bookmaker.key with 
        | None -> 
          let source = Contract.manager (Source : (unit, unit) contract) in
          bet_storage.bookmaker.key <- Some source
        | Some _ -> bet_storage
      in
      let bet_storage = bet_storage.all_token_amount <- bet_storage.all_token_amount + token in
      let (z, storage) = Contract.call bet_contract 0tz (parameter, bet_storage) (Override bet_storage) in
      (Success, storage)
    else
      (Transfer_fail result.(0), storage)
  else
    (Fail "Source key doesn't match the bookmaker's key", storage)

  
