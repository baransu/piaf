(* This module uses the interfaces in `s.ml` to abstract over HTTP/1 and HTTP/2
 * and their respective insecure / secure versions. *)

open Lwt.Infix

let error_handler notify_response_received error =
  let error_str =
    match error with
    | `Malformed_response s ->
      s
    | `Exn exn ->
      Printexc.to_string exn
    | `Protocol_error (_code, msg) ->
      Format.asprintf "Protocol Error: %s" msg
    | `Invalid_response_body_length _ ->
      Format.asprintf "invalid response body length"
  in
  Lwt.wakeup notify_response_received (Error error_str)

let read_body
    : type a.
      (module S.BASE.Body with type Read.t = a) -> a -> string Lwt_stream.t
  =
 fun (module Body) body ->
  let module Body = Body.Read in
  let read_fn () =
    let r, notify = Lwt.wait () in
    Body.schedule_read
      body
      ~on_eof:(fun () ->
        Body.close_reader body;
        Lwt.wakeup_later notify None)
      ~on_read:(fun response_fragment ~off ~len ->
        (* Note: we always need to make a copy here for now. See the following
         * comment for an explanation why:
         * https://github.com/inhabitedtype/httpaf/issues/140#issuecomment-517072327
         *)
        let response_fragment_bytes = Bytes.create len in
        (* TODO: decide on the type of Body, and on the type of the stream
         * elements. For now they're always strings. *)
        Lwt_bytes.blit_to_bytes
          response_fragment
          off
          response_fragment_bytes
          0
          len;
        Lwt.wakeup_later notify (Some (Bytes.to_string response_fragment_bytes)));
    r
  in
  Lwt_stream.from read_fn

let send_request
    : type a.
      (module S.HTTPCommon with type Client.t = a)
      -> a
      -> ?body:string
      -> Request.t
      -> (Response.t, 'err) Lwt_result.t
  =
 fun (module Http) conn ?body request_headers ->
  let open Http in
  let response_received, notify_response_received = Lwt.wait () in
  let response_handler response response_body =
    Lwt.wakeup_later notify_response_received (Ok (response, response_body))
  in
  let _error_received, notify_error_received = Lwt.wait () in
  let error_handler = error_handler notify_error_received in
  let request_body =
    Http.Client.request conn request_headers ~error_handler ~response_handler
  in
  (match body with
  | Some body ->
    Body.Write.write_string request_body body
  | None ->
    ());
  Body.Write.flush request_body (fun () -> Body.Write.close_writer request_body);
  (* Lwt.return (response_received, error_received) *)
  response_received >>= function
  | Ok (response, response_body) ->
    let body = read_body (module Body) response_body in
    let b = Buffer.create 0x2000 in
    Lwt_stream.iter_s
      (fun x ->
        Buffer.add_string b x;
        Lwt.return_unit)
      body
    >|= fun () -> Ok response
  | Error e ->
    Lwt.return (Error e)