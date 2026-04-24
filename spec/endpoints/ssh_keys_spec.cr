require "../spec_helper"

describe DediboxApi::Endpoints::SshKeys do
  describe "#list" do
    it "retourne tableau vide quand aucune clé IAM (cas typique début)" do
      stub = StubTransport.new
      stub.responses << {200, "[]"}
      client = DediboxApi::Client.new(token: "t", transport: stub)
      client.ssh_keys.list.should eq([] of DediboxApi::Endpoints::SshKey)
    end

    it "enrichit chaque URI par un appel de détail" do
      stub = StubTransport.new
      stub.responses << {200, %(["/api/v1/user/key/ssh/42"])}
      stub.responses << {200, %({"id":42,"description":"philippe@laptop","key":"ssh-ed25519 AAAA"})}
      client = DediboxApi::Client.new(token: "t", transport: stub)
      keys = client.ssh_keys.list
      keys.size.should eq(1)
      keys.first.id.should eq(42)
      keys.first.description.should eq("philippe@laptop")
    end
  end

  describe "#create" do
    it "POST /user/key/ssh avec description + key" do
      stub = StubTransport.new
      stub.responses << {200, %({"id":99})}
      client = DediboxApi::Client.new(token: "t", transport: stub)
      client.ssh_keys.create("laptop", "ssh-ed25519 AAAA me@laptop")
      stub.last.method.should eq("POST")
      stub.last.url.should end_with("/user/key/ssh")
      parsed = JSON.parse(stub.last.body)
      parsed["description"].should eq("laptop")
      parsed["key"].should eq("ssh-ed25519 AAAA me@laptop")
    end
  end

  describe "#delete" do
    it "DELETE /user/key/ssh/<id>" do
      stub = StubTransport.new
      stub.responses << {204, ""}
      client = DediboxApi::Client.new(token: "t", transport: stub)
      client.ssh_keys.delete(42)
      stub.last.method.should eq("DELETE")
      stub.last.url.should end_with("/user/key/ssh/42")
    end
  end
end
