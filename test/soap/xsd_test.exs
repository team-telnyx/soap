defmodule Soap.XsdTest do
  use ExUnit.Case
  doctest Soap.Xsd
  alias Soap.Xsd

  @xsd_path Fixtures.get_file_path("xsd/example.xsd")
  @raw_xsd Fixtures.load_xsd("example.xsd")
  @parsed_xsd %{
    complex_types: %{
      "purchaseordertype" => %{
        "BillTo" => %{type: "tns:USAddress"},
        "ShipTo" => %{maxOccurs: "2", type: "tns:USAddress"}
      },
      "usaddress" => %{
        "city" => %{type: "xsd:string"},
        "name" => %{type: "xsd:string"},
        "state" => %{type: "xsd:string"},
        "street" => %{type: "xsd:string"},
        "zip" => %{type: "xsd:integer"}
      }
    },
    simple_types: []
  }

  test "when file exists #parse returns corrent {:ok, data}" do
    assert Xsd.parse(@xsd_path) == {:ok, @parsed_xsd}
  end

  test "when the file does not exist" do
    assert Xsd.parse("does/not/exist.xsd") == {:error, :enoent}
  end

  test "when file available on external resource" do
    Req.Test.stub(Soap, fn conn -> Plug.Conn.send_resp(conn, 200, @raw_xsd) end)

    assert Xsd.parse("https://example.com") == {:ok, @parsed_xsd}
  end

  test "when file not found on external resource" do
    Req.Test.stub(Soap, fn conn -> Plug.Conn.send_resp(conn, 404, "") end)

    assert Xsd.parse("https://example.com") == {:error, :not_found}
  end

  test "when response is error on external resource" do
    Req.Test.stub(Soap, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

    assert {:error, %Req.TransportError{reason: :econnrefused}} = Xsd.parse("https://example.com")
  end
end
