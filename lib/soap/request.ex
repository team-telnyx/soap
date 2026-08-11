defmodule Soap.Request do
  @moduledoc """
  The HTTP side of Soap, built on `Req`.

  Every request goes through `call/5`, `get/3` or `get!/3`, and each answers
  `Soap.Response` — the rest of the library never sees the client's own structs.

  Per-call options are Req options and are passed through as given. Defaults for
  every request can be set once:

      config :soap, req_options: [receive_timeout: 30_000, retry: false]

  which is also where a test stub goes, since `Req` provides its own:

      config :soap, req_options: [plug: {Req.Test, MyStub}]
  """
  alias Soap.Request.{Headers, Params}
  alias Soap.Response

  @type result :: {:ok, Response.t()} | {:error, term()}

  @doc """
  Executing with parsed wsdl and headers with body map.

  Posts the built envelope to the endpoint the WSDL names.
  """
  @spec call(wsdl :: map(), operation :: String.t(), params :: any(), headers :: any(), opts :: keyword()) :: result()
  def call(wsdl, operation, soap_headers_and_params, request_headers \\ [], opts \\ [])

  def call(wsdl, operation, {soap_headers, params}, request_headers, opts) do
    url = get_url(wsdl)
    request_headers = Headers.build(wsdl, operation, request_headers)
    body = Params.build_body(wsdl, operation, params, soap_headers)

    run(:post, url, [body: body, headers: request_headers] ++ opts)
  end

  def call(wsdl, operation, params, request_headers, opts),
    do: call(wsdl, operation, {%{}, params}, request_headers, opts)

  @doc "Fetches a document — a WSDL or an imported XSD — over HTTP."
  @spec get(url :: String.t(), headers :: list(), opts :: keyword()) :: result()
  def get(url, headers \\ [], opts \\ []), do: run(:get, url, [headers: headers] ++ opts)

  @doc """
  As `get/3`, raising rather than answering `{:error, reason}`.

  Used where a missing document is not a case the caller can carry on from.
  """
  @spec get!(url :: String.t(), headers :: list(), opts :: keyword()) :: Response.t()
  def get!(url, headers \\ [], opts \\ []) do
    case get(url, headers, opts) do
      {:ok, response} -> response
      {:error, reason} -> raise RequestError, reason
    end
  end

  defp run(method, url, opts) do
    # Req retries transport errors and some statuses by default. SOAP calls are
    # not safe to repeat blindly — a retried OTA command is a second command —
    # so retries are off unless a caller asks for them.
    [url: url, method: method, retry: false]
    |> Keyword.merge(default_options())
    |> Keyword.merge(opts)
    |> Req.request()
    |> to_response(url)
  end

  defp default_options, do: Application.get_env(:soap, :req_options, [])

  defp to_response({:ok, %Req.Response{body: body, headers: headers, status: status}}, url),
    do: {:ok, %Response{body: body, headers: flatten_headers(headers), request_url: url, status_code: status}}

  defp to_response({:error, exception}, _url), do: {:error, exception}

  # Req keeps every header value as a list. Soap.Response has always carried
  # `{name, value}` pairs, and consumers read them that way.
  defp flatten_headers(headers), do: Enum.map(headers, fn {name, values} -> {name, Enum.join(values, ", ")} end)

  @spec get_url(wsdl :: map()) :: String.t()
  defp get_url(wsdl) do
    wsdl.endpoint
  end
end
