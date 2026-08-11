defmodule Soap.RequestTest do
  use ExUnit.Case
  doctest Soap.Request
  alias Soap.{Request, Response, Wsdl}

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
    Req.Test.stub(Soap, fn conn -> Plug.Conn.send_resp(conn, 200, "Anything") end)

    assert {:ok, %Response{status_code: 200, body: "Anything"}} = Request.call(wsdl, operation, params)
  end

  test "#call can take request options" do
    {_, wsdl} = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Wsdl.parse_from_file()
    operation = "SendMessage"
    params = %{inCommonParms: [{"userID", "WSPB"}]}
    parent = self()

    Req.Test.stub(Soap, fn conn ->
      send(parent, {:authorization, Plug.Conn.get_req_header(conn, "authorization")})
      Plug.Conn.send_resp(conn, 200, "Anything")
    end)

    assert {:ok, %Response{status_code: 200, body: "Anything"}} =
             Request.call(wsdl, operation, params, [], auth: {:basic, "user:pass"})

    assert_received {:authorization, ["Basic " <> _]}
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

    assert sent_body(wsdl, operation, params) == @request_with_header
  end

  test "#call takes a params tuple to add attributes" do
    {_, wsdl} = Fixtures.get_file_path("wsdl/SoapHeader.wsdl") |> Wsdl.parse_from_file()
    operation = "sayHello"
    params = {%{token: "barbaz"}, {:body, %{foo: "bar"}, "Hello John"}}

    assert sent_body(wsdl, operation, params) ==
             String.replace(@request_with_header, "<body>", ~s{<body foo="bar">})
  end

  describe "get/3" do
    test "answers a Soap.Response" do
      Req.Test.stub(Soap, fn conn -> Plug.Conn.send_resp(conn, 200, "doc") end)

      assert {:ok, %Response{status_code: 200, body: "doc"}} = Request.get("https://example.com/x")
    end

    test "carries the status through rather than treating it as an error" do
      Req.Test.stub(Soap, fn conn -> Plug.Conn.send_resp(conn, 404, "") end)

      assert {:ok, %Response{status_code: 404}} = Request.get("https://example.com/x")
    end

    test "answers the error when the transport fails" do
      Req.Test.stub(Soap, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, %Req.TransportError{reason: :econnrefused}} = Request.get("https://example.com/x")
    end
  end

  describe "get!/3" do
    test "answers the response itself" do
      Req.Test.stub(Soap, fn conn -> Plug.Conn.send_resp(conn, 200, "doc") end)

      assert %Response{status_code: 200, body: "doc"} = Request.get!("https://example.com/x")
    end

    test "raises when the transport fails" do
      Req.Test.stub(Soap, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert_raise RequestError, fn -> Request.get!("https://example.com/x") end
    end
  end

  describe "retries" do
    setup do
      parent = self()

      Req.Test.stub(Soap, fn conn ->
        send(parent, :attempt)
        Req.Test.transport_error(conn, :econnrefused)
      end)
    end

    test "are off by default, so a SOAP call is never repeated blindly" do
      assert {:error, _} = Request.get("https://example.com/x")

      assert_received :attempt
      refute_received :attempt
    end

    test "can be turned back on per call" do
      assert {:error, _} =
               Request.get("https://example.com/x", [], retry: :transient, max_retries: 1, retry_delay: 0)

      assert_received :attempt
      assert_received :attempt
    end
  end

  # Asserts on what actually left over the wire rather than on the client's
  # argument, which is what the old client double could observe.
  defp sent_body(wsdl, operation, params) do
    parent = self()

    Req.Test.stub(Soap, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:sent_body, body})
      Plug.Conn.send_resp(conn, 200, "")
    end)

    Request.call(wsdl, operation, params)
    assert_received {:sent_body, body}
    body
  end
end
