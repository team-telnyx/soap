# Soap

[![Quality](https://github.com/team-telnyx/soap/actions/workflows/quality.yml/badge.svg)](https://github.com/team-telnyx/soap/actions/workflows/quality.yml)
[![Compatibility](https://github.com/team-telnyx/soap/actions/workflows/compatibility.yml/badge.svg)](https://github.com/team-telnyx/soap/actions/workflows/compatibility.yml)
[![Elixir](https://img.shields.io/badge/elixir-%3E%3D%201.15-purple.svg)](https://elixir-lang.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.md)
[![Last Updated](https://img.shields.io/github/last-commit/team-telnyx/soap.svg)](https://github.com/team-telnyx/soap/commits/master)

A SOAP client for Elixir. It reads a WSDL, tells you the operations it
describes, builds the envelope for a call from a plain map, and parses what
comes back — including faults.

## About this fork

This is a fork of [elixir-soap/soap](https://github.com/elixir-soap/soap),
taken at release 1.1.1. Upstream is alive but has not released since August
2023, and the changes here were needed sooner than that.

**The specs describe what the code does.** `Wsdl.parse/3` hands the parsed XML
document to its helpers while their specs said `String.t()`, which dialyzer
reads as a contract nothing can satisfy — eighteen warnings from one mistaken
description. A `Soap.xml()` type names what those functions really take.

**The HTTP boundary answers `Soap.Response`.** Call sites used to decide what
had happened by matching the HTTP client's own structs, so a different client
could not be an adapter, only an impersonation. Every request now comes back as
`Soap.Response` regardless of what is underneath.

**[Req](https://hex.pm/packages/req) replaced HTTPoison**, and with it the
swappable-client mechanism, which existed mainly so tests could inject a double
— something Req provides itself. Two consequences worth knowing:

- **Request options are Req's**, and Req rejects names it does not know rather
  than ignoring them. Code carrying hackney names hears about it at the first
  request: `unknown option :recv_timeout. Did you mean :receive_timeout?`
- **Retries are off by default.** Req retries out of the box and HTTPoison did
  not. A repeated SOAP call is a repeated *command*, not a repeated read, so the
  old behaviour is kept. Pass `retry:` to opt in.

**Two defects surfaced while covering the paths the suite left open.**
`Wsdl.parse_from_file/2` raised `MatchError` on a missing file instead of
reporting it, and `operations/1` answers maps while its spec promised strings.

The floor is Elixir 1.15, which is what the dependencies require, and the
quality chain — formatting, warnings, credo, dialyzer and coverage above 90% —
is enforced in CI.

## Installation

This fork is not published to Hex. Depend on it by ref, never by branch, so a
build is reproducible:

```elixir
def deps do
  [
    {:soap, github: "team-telnyx/soap", ref: "a-full-commit-sha"}
  ]
end
```

Nothing else is needed — Mix starts the application and its dependencies.

## Configuration

The SOAP protocol version, `1.1` (default) or `1.2`:

```elixir
config :soap, :globals, version: "1.1"
```

Options applied to every request. These are
[Req options](https://hexdocs.pm/req/Req.html#new/1), and per-call options
override them:

```elixir
config :soap, req_options: [receive_timeout: 30_000]
```

## Usage

Read a WSDL, from a URL or a local file:

```elixir
iex> {:ok, wsdl} = Soap.init_model("http://www.dneonline.com/calculator.asmx?WSDL", :url)
{:ok, %{operations: [...], endpoint: "...", ...}}
```

Ask what it describes. Each operation is a map, not a name — `soap_action` is
what goes on the wire, `input` describes the body and header it expects:

```elixir
iex> Soap.operations(wsdl)
[
  %{input: %{body: nil, header: nil}, name: "Add", soap_action: "http://tempuri.org/Add"},
  %{input: %{body: nil, header: nil}, name: "Subtract", soap_action: "http://tempuri.org/Subtract"},
  %{input: %{body: nil, header: nil}, name: "Multiply", soap_action: "http://tempuri.org/Multiply"},
  %{input: %{body: nil, header: nil}, name: "Divide", soap_action: "http://tempuri.org/Divide"}
]
```

Call one. The parameter map is validated against the operation's type
definitions before the envelope is built, and an operation the WSDL does not
describe raises `OperationError`:

```elixir
iex> {:ok, response} = Soap.call(wsdl, "Add", %{intA: 1, intB: 2})
{:ok,
 %Soap.Response{
   body: "<?xml version=\"1.0\" encoding=\"utf-8\"?>...<AddResult>3</AddResult>...",
   headers: [
     {"cache-control", "private, max-age=0"},
     {"content-type", "text/xml; charset=utf-8"},
     {"date", "Thu, 14 Feb 2019 07:52:04 GMT"}
   ],
   request_url: "http://www.dneonline.com/calculator.asmx",
   status_code: 200
 }}
```

Header names are lowercase, which is how Req delivers them.

A SOAP fault is a successful HTTP exchange carrying an error, so it arrives as
`{:ok, response}` with a 4xx or 5xx status. `{:error, reason}` means the request
never completed — a connection refused, a timeout. Both are worth handling:

```elixir
case Soap.call(wsdl, "Add", %{intA: 1, intB: 2}) do
  {:ok, %Soap.Response{status_code: status} = response} when status < 400 ->
    Soap.Response.parse(response)

  {:ok, response} ->
    {:fault, Soap.Response.parse(response)}

  {:error, reason} ->
    {:transport_error, reason}
end
```

`Soap.Response.parse/1` reads the status to pick its parser, so it answers the
body of a successful response or the fault of a failed one:

```elixir
iex> Soap.Response.parse(response)
%{AddResponse: %{AddResult: "3"}}

iex> Soap.Response.parse(fault_response)
%{faultcode: "soap:Server", faultstring: "Server was unable to process request."}
```

To send SOAP headers, pass `{headers, params}` where params alone would go:

```elixir
{:ok, %Soap.Response{}} = Soap.call(wsdl, "Add", {%{Token: "foo"}, %{intA: 1, intB: 2}})
```

## Testing against it

Req stubs its own transport, so nothing has to mock a client module. Point the
library at a stub and answer the request yourself:

```elixir
# test_helper.exs
Application.put_env(:soap, :req_options, plug: {Req.Test, MyApp.SoapStub})

# in a test
Req.Test.stub(MyApp.SoapStub, fn conn ->
  Plug.Conn.send_resp(conn, 200, File.read!("test/fixtures/add_response.xml"))
end)
```

`Req.Test.transport_error/2` covers the failure side.

## Contributing

Issues and pull requests for this fork go to
[team-telnyx/soap](https://github.com/team-telnyx/soap/issues). Changes that
are not specific to Telnyx's use are worth offering to
[upstream](https://github.com/elixir-soap/soap) as well.

## Copyright and License

Copyright (c) 2017 Petr Stepchenko

Copyright (c) 2026 Telnyx LLC

This work is free. You can redistribute it and/or modify it under the
terms of the MIT License. See the [LICENSE.md](./LICENSE.md) file for more details.
