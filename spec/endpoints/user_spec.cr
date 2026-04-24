require "../spec_helper"

describe DediboxApi::Endpoints::User do
  it "GET /user retourne les infos du compte" do
    stub = StubTransport.new
    stub.responses << {200, %({"id":313469,"login":"aloli","email":"it@aloli.fr","first_name":"Philippe","last_name":"Nénert","company":"ALOLI sas"})}
    client = DediboxApi::Client.new(token: "t", transport: stub)
    info = client.user.info
    info.id.should eq(313469)
    info.login.should eq("aloli")
    info.email.should eq("it@aloli.fr")
    info.display_name.should eq("Philippe Nénert")
    info.company.should eq("ALOLI sas")
    stub.last.url.should end_with("/user")
  end

  it "display_name tolère first_name/last_name manquants" do
    raw = JSON.parse(%({"id":1,"login":"user","first_name":"","last_name":"Doe"}))
    info = DediboxApi::Endpoints::UserInfo.new(raw)
    info.display_name.should eq("Doe")
  end
end
