module Versions : sig
  module HTTP : sig
    include module type of struct
      include Httpaf.Version
    end

    val v1_0 : t

    val v1_1 : t

    val v2_0 : t
  end

  module TLS : sig
    type t =
      | Any
      | SSLv3
      | TLSv1_0
      | TLSv1_1
      | TLSv1_2
      | TLSv1_3

    val compare : t -> t -> int

    val of_string : string -> (t, string) result

    val pp_hum : Format.formatter -> t -> unit
  end

  module ALPN : sig
    type nonrec t =
      | HTTP_1_0
      | HTTP_1_1
      | HTTP_2

    val of_version : HTTP.t -> t option

    val to_version : t -> HTTP.t

    val of_string : string -> t option

    val to_string : t -> string
  end
end

module Config : sig
  type t =
    { follow_redirects : bool  (** whether to follow redirects *)
    ; max_redirects : int
          (** max redirects to follow. Could probably be rolled up into one
              option *)
    ; allow_insecure : bool
          (** Wether to allow insecure server connections when using SSL *)
    ; max_http_version : Versions.HTTP.t
          (** Use this as the highest HTTP version when sending requests *)
    ; h2c_upgrade : bool
          (** Send an upgrade to `h2c` (HTTP/2 over TCP) request to the server.
              `http2_prior_knowledge` below ignores this option. *)
    ; http2_prior_knowledge : bool
          (** Assume HTTP/2 prior knowledge -- don't use HTTP/1.1 Upgrade when
              communicating with "http" URIs, default to HTTP/2.0 when we can't
              agree to an ALPN protocol and communicating with "https" URIs. *)
    ; cacert : string option
          (** The path to a CA certificates file in PEM format *)
    ; capath : string option
          (** The path to a directory which contains CA certificates in PEM
              format *)
    ; min_tls_version : Versions.TLS.t
    ; max_tls_version : Versions.TLS.t
    ; tcp_nodelay : bool
    ; connect_timeout : float
    }

  val default : t
end

module Body : sig
  type t

  type length =
    [ `Fixed of Int64.t
    | `Chunked
    | `Error of [ `Bad_request | `Bad_gateway | `Internal_server_error ]
    | `Unknown
    | `Close_delimited
    ]

  val to_string : t -> string Lwt.t

  val to_string_stream : t -> string Lwt_stream.t

  val drain : t -> unit Lwt.t
end

module Response : sig
  type t = private
    { (* `H2.Status.t` is a strict superset of `Httpaf.Status.t` *)
      status : H2.Status.t
    ; headers : H2.Headers.t
    ; version : Versions.HTTP.t
    ; body_length : Body.length
    }

  val persistent_connection : t -> bool

  val pp_hum : Format.formatter -> t -> unit [@@ocaml.toplevel_printer]
end

(** {2 Client -- Issuing requests} *)

(** There are two options for issuing requests with Piaf:

    + client: useful if multiple requests are going to be sent to the remote
      endpoint, avoids setting up a TCP connection for each request. Or if
      HTTP/1.0, you can think of this as effectively a connection manager.
    + oneshot: issues a single request and tears down the underlying connection
      once the request is done. Useful for isolated requests. *)

module Client : sig
  type t

  val create : ?config:Config.t -> Uri.t -> (t, string) Lwt_result.t
  (** [create ?config uri] opens a connection to [uri] (initially) that can be
      used to issue multiple requests to the remote endpoint. *)

  val head
    :  t
    -> ?headers:(string * string) list
    -> string
    -> (Response.t * Body.t, string) Lwt_result.t

  val get
    :  t
    -> ?headers:(string * string) list
    -> string
    -> (Response.t * Body.t, string) Lwt_result.t

  val post
    :  t
    -> ?headers:(string * string) list
    -> string
    -> (Response.t * Body.t, string) Lwt_result.t

  val put
    :  t
    -> ?headers:(string * string) list
    -> string
    -> (Response.t * Body.t, string) Lwt_result.t

  val patch
    :  t
    -> ?headers:(string * string) list
    -> string
    -> (Response.t * Body.t, string) Lwt_result.t

  val delete
    :  t
    -> ?headers:(string * string) list
    -> string
    -> (Response.t * Body.t, string) Lwt_result.t

  val request
    :  t
    -> ?headers:(string * string) list
    -> meth:Method.t
    -> string
    -> (Response.t * Body.t, string) Lwt_result.t

  val shutdown : t -> unit
  (** [shutdown t] tears down the connection [t] and frees up all the resources
      associated with it. *)

  module Oneshot : sig
    val head
      :  ?config:Config.t
      -> ?headers:(string * string) list
      -> Uri.t
      -> (Response.t * Body.t, string) Lwt_result.t

    val get
      :  ?config:Config.t
      -> ?headers:(string * string) list
      -> Uri.t
      -> (Response.t * Body.t, string) Lwt_result.t

    val post
      :  ?config:Config.t
      -> ?headers:(string * string) list
      -> Uri.t
      -> (Response.t * Body.t, string) Lwt_result.t

    val put
      :  ?config:Config.t
      -> ?headers:(string * string) list
      -> Uri.t
      -> (Response.t * Body.t, string) Lwt_result.t

    val patch
      :  ?config:Config.t
      -> ?headers:(string * string) list
      -> Uri.t
      -> (Response.t * Body.t, string) Lwt_result.t

    val delete
      :  ?config:Config.t
      -> ?headers:(string * string) list
      -> Uri.t
      -> (Response.t * Body.t, string) Lwt_result.t

    val request
      :  ?config:Config.t
      -> ?headers:(string * string) list
      -> meth:Method.t
      -> Uri.t
      -> (Response.t * Body.t, string) Lwt_result.t
    (** Use another request method. *)
  end

  (* (Httpaf.Response.t * (string, 'a) result) Lwt.t *)
end

module Method : module type of Method

module Headers : module type of struct
  include H2.Headers
end

module Scheme : sig
  type t =
    | HTTP
    | HTTPS

  val of_uri : Uri.t -> (t, string) result

  val to_string : t -> string

  val pp_hum : Format.formatter -> t -> unit [@@ocaml.toplevel_printer]
end

module Status : module type of struct
  include H2.Status
end
