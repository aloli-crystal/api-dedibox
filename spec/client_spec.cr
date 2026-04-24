require "./spec_helper"

describe DediboxApi::Client do
  describe "#call" do
    it "envoie l'header Authorization Bearer avec le token" do
      stub = StubTransport.new
      stub.responses << {200, %({"ok":true})}
      client = DediboxApi::Client.new(token: "mytoken", transport: stub)
      client.call("GET", "/server/42")
      stub.last.headers["Authorization"].should eq("Bearer mytoken")
      stub.last.headers["Accept"].should eq("application/json")
    end

    it "construit l'URL absolue avec le endpoint par défaut" do
      stub = StubTransport.new
      stub.responses << {200, "[]"}
      client = DediboxApi::Client.new(token: "t", transport: stub)
      client.call("GET", "/server/")
      stub.last.url.should eq("https://api.online.net/api/v1/server/")
    end

    it "permet un endpoint custom (tests, proxys)" do
      stub = StubTransport.new
      stub.responses << {200, "{}"}
      client = DediboxApi::Client.new(token: "t", endpoint: "https://fake.test/v9", transport: stub)
      client.call("GET", "/x")
      stub.last.url.should eq("https://fake.test/v9/x")
    end

    it "sérialise un body Hash en JSON" do
      stub = StubTransport.new
      stub.responses << {200, "{}"}
      client = DediboxApi::Client.new(token: "t", transport: stub)
      client.call("POST", "/x", body: {"image" => "debian-12_amd64"})
      JSON.parse(stub.last.body)["image"].should eq("debian-12_amd64")
    end

    it "retourne nil sur corps vide (DELETE)" do
      stub = StubTransport.new
      stub.responses << {204, ""}
      client = DediboxApi::Client.new(token: "t", transport: stub)
      client.call("DELETE", "/user/key/ssh/1").should be_nil
    end

    it "lève AuthenticationError sur 401" do
      stub = StubTransport.new
      stub.responses << {401, %({"error":"Unauthorized"})}
      client = DediboxApi::Client.new(token: "bad", transport: stub)
      expect_raises(DediboxApi::AuthenticationError, /401/) do
        client.call("GET", "/server/")
      end
    end

    it "lève NotFound sur 404" do
      stub = StubTransport.new
      stub.responses << {404, %({"error":"Unknown method","code":3})}
      client = DediboxApi::Client.new(token: "t", transport: stub)
      expect_raises(DediboxApi::NotFound, /404/) do
        client.call("GET", "/server/reverse/42")
      end
    end

    it "lève RateLimited sur 429 avec retry_after si présent" do
      stub = StubTransport.new
      stub.responses << {429, %({"error":"Too many","retryAfter":30})}
      client = DediboxApi::Client.new(token: "t", transport: stub)
      ex = expect_raises(DediboxApi::RateLimited) { client.call("GET", "/x") }
      ex.retry_after.should eq(30)
    end

    it "lève ApiError générique sur 5xx" do
      stub = StubTransport.new
      stub.responses << {500, %({"error":"boom"})}
      client = DediboxApi::Client.new(token: "t", transport: stub)
      expect_raises(DediboxApi::ApiError, /500/) { client.call("GET", "/x") }
    end
  end
end
