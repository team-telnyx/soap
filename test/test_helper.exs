Code.require_file("support/fixtures.exs", __DIR__)

# Req stubs its own transport, so nothing has to mock the client module.
Application.put_env(:soap, :req_options, plug: {Req.Test, Soap})

ExUnit.start()
