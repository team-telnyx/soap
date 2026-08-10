defmodule Soap.RequestTest do
  use ExUnit.Case
  import Mock
  doctest Soap.Request
  alias Soap.{Request, Response, Wsdl}

  # A client that knows nothing about HTTPoison, which is the point of the seam.
  defmodule OwnStructClient do
    def post(_url, _body, _headers, _opts),
      do: {:ok, %Response{status_code: 201, body: "own", headers: [], request_url: "http://x"}}

    def get(_url, _headers, _opts), do: {:error, :nope}
  end

  @request_with_header ~S"""
                       <?xml version="1.0" encoding="UTF-8"?>
                       <env:Envelope xmlns:env="http://schemas.xmlsoap.org/soap/envelope/" xmlns:tns="http://test.com" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                         <env:Header>
                            <Authentication xmlns="http://test.com">
                               <token>barbaz</token>
                            </Authentication>
                         </env:Header>
                         <env:Body>
                           <tns:sayHello xmlns="http://test.com">
                             <body>Hello John</body>
                           </tns:sayHello>
                         </env:Body>
                       </env:Envelope>
                       """
                       |> String.replace(~r/>\n.*?</, "><")
                       |> String.trim()

  test "#call returns response body" do
    {_, wsdl} = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Wsdl.parse_from_file()
    operation = "SendMessage"
    params = %{inCommonParms: [{"userID", "WSPB"}]}
    http_poison_result = {:ok, %HTTPoison.Response{status_code: 200, body: "Anything"}}

    with_mock HTTPoison, post: fn _, _, _, _ -> http_poison_result end do
      assert {:ok, %Soap.Response{status_code: 200, body: "Anything"}} = Request.call(wsdl, operation, params)
    end
  end

  test "#call can take request options" do
    {_, wsdl} = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Wsdl.parse_from_file()
    operation = "SendMessage"
    params = %{inCommonParms: [{"userID", "WSPB"}]}
    http_poison_result = {:ok, %HTTPoison.Response{status_code: 200, body: "Anything"}}
    hackney = [basic_auth: {"user", "pass"}]

    with_mock HTTPoison, post: fn _, _, _, [hackney: ^hackney] -> http_poison_result end do
      assert {:ok, %Soap.Response{status_code: 200, body: "Anything"}} =
               Request.call(wsdl, operation, params, [], hackney: hackney)
    end
  end

  describe "a client that answers Soap structs" do
    setup do
      # :globals also carries the SOAP version and namespaces, so it is merged.
      globals = Application.fetch_env!(:soap, :globals)
      Application.put_env(:soap, :globals, Keyword.put(globals, :http_client, OwnStructClient))
      on_exit(fn -> Application.put_env(:soap, :globals, globals) end)
    end

    test "is passed through untouched" do
      {_, wsdl} = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Wsdl.parse_from_file()

      assert {:ok, %Response{status_code: 201, body: "own"}} =
               Request.call(wsdl, "SendMessage", %{inCommonParms: [{"userID", "WSPB"}]})
    end

    test "keeps its own error term" do
      assert {:error, :nope} = Request.get("http://example.com")
    end
  end

  test "#get_url returns correct soap:address" do
    endpoint = "http://localhost:8080/soap/SendService"
    {_, wsdl} = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Wsdl.parse_from_file()
    result = wsdl[:endpoint]

    assert result == endpoint
  end

  test "#call takes a tuple with soap headers and params" do
    {_, wsdl} = Fixtures.get_file_path("wsdl/SoapHeader.wsdl") |> Wsdl.parse_from_file()
    operation = "sayHello"
    params = {%{token: "barbaz"}, %{body: "Hello John"}}

    with_mock HTTPoison, post: fn _, body, _, _ -> body end do
      assert(Request.call(wsdl, operation, params) == @request_with_header)
    end
  end

  test "#call takes a params tuple to add attributes" do
    {_, wsdl} = Fixtures.get_file_path("wsdl/SoapHeader.wsdl") |> Wsdl.parse_from_file()
    operation = "sayHello"
    params = {%{token: "barbaz"}, {:body, %{foo: "bar"}, "Hello John"}}

    with_mock HTTPoison, post: fn _, body, _, _ -> body end do
      assert Request.call(wsdl, operation, params) ==
               String.replace(@request_with_header, "<body>", ~s{<body foo="bar">})
    end
  end
end
