defmodule SoapTest do
  use ExUnit.Case
  alias Soap.{Response, Wsdl}

  defp stub_xml(body, status \\ 200) do
    Req.Test.stub(Soap, fn conn ->
      conn |> Plug.Conn.put_resp_content_type("text/xml") |> Plug.Conn.send_resp(status, body)
    end)
  end

  @operation "SendMessage"
  @request_params %{inCommonParms: [{"userID", "WSPB"}]}

  test "#call was success" do
    {_, wsdl} = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Wsdl.parse_from_file()
    response_xml = Fixtures.load_xml("send_service/SendMessageResponse.xml")
    stub_xml(response_xml)

    assert {:ok, %Response{status_code: 200, body: ^response_xml}} = Soap.call(wsdl, @operation, @request_params)
  end

  test "#call can take request options" do
    {_, wsdl} = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Wsdl.parse_from_file()
    response_xml = Fixtures.load_xml("send_service/SendMessageResponse.xml")
    parent = self()

    Req.Test.stub(Soap, fn conn ->
      send(parent, {:authorization, Plug.Conn.get_req_header(conn, "authorization")})
      conn |> Plug.Conn.put_resp_content_type("text/xml") |> Plug.Conn.send_resp(200, response_xml)
    end)

    assert {:ok, %Response{status_code: 200}} =
             Soap.call(wsdl, @operation, @request_params, [], auth: {:basic, "user:pass"})

    assert_received {:authorization, ["Basic " <> _]}
  end

  test "#call was success, but fault" do
    {_, wsdl} = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Wsdl.parse_from_file()
    fault_xml = Fixtures.load_xml("send_service/SendMessageFault.xml")
    stub_xml(fault_xml, 500)

    assert {:ok, %Response{status_code: 500, body: ^fault_xml}} = Soap.call(wsdl, @operation, @request_params)
  end

  test "#call returns error" do
    {_, wsdl} = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Wsdl.parse_from_file()
    Req.Test.stub(Soap, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

    assert {:error, %Req.TransportError{reason: :econnrefused}} = Soap.call(wsdl, @operation, @request_params)
  end

  test "to #call pass unknown soap operation" do
    {_, wsdl} = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Wsdl.parse_from_file()
    operation = "IncorrectOperation"

    assert_raise OperationError, fn -> Soap.call(wsdl, operation, @request_params) end
  end

  test "#init_model with :file type parses the local wsdl" do
    wsdl_path = Fixtures.get_file_path("wsdl/SendService.wsdl")

    assert {:ok, %{operations: _}} = Soap.init_model(wsdl_path)
  end

  test "#init_model with :file type reports a missing file" do
    assert {:error, :enoent} = Soap.init_model("does/not/exist.wsdl")
  end

  test "#operations lists what the wsdl describes" do
    {:ok, wsdl} = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Wsdl.parse_from_file()

    assert @operation in Enum.map(Soap.operations(wsdl), & &1.name)
  end

  test "#init_model with :url type can take request options" do
    wsdl_path = Fixtures.get_file_path("wsdl/SoapHeader.wsdl")
    {:ok, wsdl_body} = File.read(wsdl_path)
    {_, parsed_wsdl} = Wsdl.parse_from_file(wsdl_path)
    stub_xml(wsdl_body)

    assert Soap.init_model(wsdl_path, :url, receive_timeout: 1000) == {:ok, parsed_wsdl}
  end
end
