defmodule Soap.Request do
  @moduledoc """
  The seam between Soap and the HTTP library underneath it.

  Every request Soap makes goes through `call/5`, `get/3` or `get!/3`, and each
  answers `Soap.Response` rather than whatever struct the client returned. That
  is what keeps the rest of the library from naming a particular HTTP client.

  The client is swappable:

      config :soap, globals: [http_client: MyClient]

  and defaults to `HTTPoison`. A replacement may answer either `Soap.Response`
  or the HTTPoison shapes, since existing configurations — test doubles, mostly
  — were written against the latter. Anything else is passed through untouched.
  """
  alias Soap.Request.{Headers, Params}
  alias Soap.Response

  @type result :: {:ok, Response.t()} | {:error, term()} | term()

  @doc """
  Executing with parsed wsdl and headers with body map.

  Posts the built envelope to the endpoint the WSDL names.
  """
  @spec call(wsdl :: map(), operation :: String.t(), params :: any(), headers :: any(), opts :: any()) :: result()
  def call(wsdl, operation, soap_headers_and_params, request_headers \\ [], opts \\ [])

  def call(wsdl, operation, {soap_headers, params}, request_headers, opts) do
    url = get_url(wsdl)
    request_headers = Headers.build(wsdl, operation, request_headers)
    body = Params.build_body(wsdl, operation, params, soap_headers)

    normalise(get_http_client().post(url, body, request_headers, opts))
  end

  def call(wsdl, operation, params, request_headers, opts),
    do: call(wsdl, operation, {%{}, params}, request_headers, opts)

  @doc "Fetches a document — a WSDL or an imported XSD — over HTTP."
  @spec get(url :: String.t(), headers :: list(), opts :: keyword()) :: result()
  def get(url, headers \\ [], opts \\ []), do: normalise(get_http_client().get(url, headers, opts))

  @doc "As `get/3`, raising through whatever the client raises."
  @spec get!(url :: String.t(), headers :: list(), opts :: keyword()) :: Response.t() | term()
  def get!(url, headers \\ [], opts \\ []), do: normalise(get_http_client().get!(url, headers, opts))

  @spec get_http_client() :: module()
  def get_http_client do
    Application.get_env(:soap, :globals)[:http_client] || HTTPoison
  end

  # Only the HTTPoison shapes are converted. Everything else — a client that
  # already answers Soap.Response, or one that answers something Soap does not
  # model — is left exactly as it came back.
  defp normalise({:ok, response = %HTTPoison.Response{}}), do: {:ok, to_response(response)}
  defp normalise({:error, %HTTPoison.Error{reason: reason}}), do: {:error, reason}
  defp normalise(response = %HTTPoison.Response{}), do: to_response(response)
  defp normalise(other), do: other

  defp to_response(%HTTPoison.Response{body: body, headers: headers, request_url: request_url, status_code: status}),
    do: %Response{body: body, headers: headers, request_url: request_url, status_code: status}

  @spec get_url(wsdl :: map()) :: String.t()
  defp get_url(wsdl) do
    wsdl.endpoint
  end
end
