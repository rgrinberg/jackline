open Lwt
open React

let start_client cfgdir debug () =
  ignore (LTerm_inputrc.load ());
  Tls_lwt.rng_init () >>= fun () ->

  Lazy.force LTerm.stdout >>= fun term ->

  Persistency.load_config cfgdir >>= ( function
      | None ->
        Cli_config.configure term () >>= fun config ->
        Persistency.dump_config cfgdir config >|= fun () ->
        config
      | Some cfg -> return cfg ) >>= fun config ->

  Persistency.load_users cfgdir >>= fun (users) ->

  let history = LTerm_history.create [] in

  (* setup self contact *)
  let jid, resource = User.bare_jid config.Config.jid in
  let user = User.find_or_create users jid in
  let user, _ = User.find_or_create_session user resource config.Config.otr_config in
  User.Users.replace users jid user ;

  let state = Cli_state.empty_ui_state cfgdir jid resource users in
  let n, log = S.create (`Local "welcome to jackline", "type /help for help") in

  ( if debug then
      Persistency.open_append (Unix.getenv "PWD") "out.txt" >|= fun fd ->
      Some fd
    else
      return None ) >>= fun out ->

  Cli_client.init_system (log ?step:None) ;

  ignore (LTerm.save_state term);  (* save the terminal state *)

  Cli_client.loop ?out config term history state n (log ?step:None) >>= fun state ->

  ( match out with
    | None -> return_unit
    | Some fd -> Lwt_unix.close fd ) >>= fun () ->

  Persistency.dump_users cfgdir state.Cli_state.users >>= fun () ->

  LTerm.load_state term   (* restore the terminal state *)



let config_dir = ref ""
let debug = ref false
let rest = ref []

let _ =
  let home = Unix.getenv "HOME" in
  let cfgdir = Filename.concat home ".config" in
  config_dir := Filename.concat cfgdir "ocaml-xmpp-client"

let usage = "usage " ^ Sys.argv.(0)

let arglist = [
  ("-f", Arg.String (fun d -> config_dir := d), "configuration directory (defaults to ~/.config/ocaml-xmpp-client/)") ;
  ("-d", Arg.Bool (fun d -> debug := d), "log to out.txt in current working directory")
]

let _ =
  try
    Arg.parse arglist (fun x -> rest := x :: !rest) usage ;
    Lwt_main.run (start_client !config_dir !debug ())
  with
  | Sys_error s -> print_endline s
