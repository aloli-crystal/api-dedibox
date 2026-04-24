require "../spec_helper"

# Réponse réelle capturée sur serveur 186260 le 24 avril 2026, tronquée
# aux champs utilisés par la struct Server.
private FAKE_SERVER_186260 = <<-JSON
{
  "id": 186260,
  "offer": "Start-9-M",
  "hostname": "cookie",
  "os": { "name": "custom installation", "version": "" },
  "power": "ON",
  "boot_mode": "normal",
  "ip": [
    { "address": "10.88.226.29", "type": "private", "reverse": null, "mac": "d8:5e:d3:43:f9:cb" },
    { "address": "195.154.254.221", "type": "public", "reverse": "195-154-254-221.rev.poneytelecom.eu.", "mac": "d8:5e:d3:43:f9:ca" }
  ]
}
JSON

describe DediboxApi::Endpoints::Servers do
  describe "#list" do
    it "normalise les URIs en IDs entiers" do
      stub = StubTransport.new
      stub.responses << {200, %(["/api/v1/server/186260","/api/v1/server/42"])}
      client = DediboxApi::Client.new(token: "t", transport: stub)
      client.servers.list.should eq([186260, 42])
    end

    it "retourne tableau vide quand aucun serveur" do
      stub = StubTransport.new
      stub.responses << {200, "[]"}
      client = DediboxApi::Client.new(token: "t", transport: stub)
      client.servers.list.should eq([] of Int32)
    end
  end

  describe "#info" do
    it "retourne une struct Server exposant les champs clés" do
      stub = StubTransport.new
      stub.responses << {200, FAKE_SERVER_186260}
      client = DediboxApi::Client.new(token: "t", transport: stub)
      server = client.servers.info(186260)
      server.id.should eq(186260)
      server.offer.should eq("Start-9-M")
      server.hostname.should eq("cookie")
      server.os_name.should eq("custom installation")
      server.power.should eq("ON")
      server.boot_mode.should eq("normal")
      server.public_ip.should eq("195.154.254.221")
      server.public_reverse.should eq("195-154-254-221.rev.poneytelecom.eu.")
    end

    it "appelle GET /server/<id>" do
      stub = StubTransport.new
      stub.responses << {200, FAKE_SERVER_186260}
      client = DediboxApi::Client.new(token: "t", transport: stub)
      client.servers.info(186260)
      stub.last.method.should eq("GET")
      stub.last.url.should end_with("/server/186260")
    end
  end

  describe "#update_hostname" do
    it "PUT /server/<id> avec hostname en body" do
      stub = StubTransport.new
      stub.responses << {200, "true"}
      client = DediboxApi::Client.new(token: "t", transport: stub)
      client.servers.update_hostname(186260, "cookie").should be_true
      stub.last.method.should eq("PUT")
      stub.last.url.should end_with("/server/186260")
      JSON.parse(stub.last.body)["hostname"].should eq("cookie")
    end
  end

  describe "#rescue_images" do
    it "retourne la liste des slugs" do
      stub = StubTransport.new
      stub.responses << {200, %(["ubuntu-22.04_amd64v2","debian-12_amd64","debian-10_amd64"])}
      client = DediboxApi::Client.new(token: "t", transport: stub)
      client.servers.rescue_images(186260).should eq(
        ["ubuntu-22.04_amd64v2", "debian-12_amd64", "debian-10_amd64"]
      )
    end
  end

  describe "#prepare_rescue" do
    it "POST /server/boot/rescue/<id> avec l'image dans le body JSON" do
      stub = StubTransport.new
      stub.responses << {200, %({"login":"sd-186260","password":"kelG@w55","protocol":"ssh","ip":"195.154.254.221"})}
      client = DediboxApi::Client.new(token: "t", transport: stub)
      creds = client.servers.prepare_rescue(186260, "debian-12_amd64")
      stub.last.method.should eq("POST")
      stub.last.url.should end_with("/server/boot/rescue/186260")
      JSON.parse(stub.last.body)["image"].should eq("debian-12_amd64")
      creds.login.should eq("sd-186260")
      creds.password.should eq("kelG@w55")
      creds.ip.should eq("195.154.254.221")
      creds.protocol.should eq("ssh")
    end
  end

  describe "#reboot" do
    it "POST /server/reboot/<id>?reason=... (reason obligatoire côté Dedibox)" do
      stub = StubTransport.new
      stub.responses << {200, "true"}
      client = DediboxApi::Client.new(token: "t", transport: stub)
      client.servers.reboot(186260, reason: "beryl test").should be_true
      stub.last.method.should eq("POST")
      stub.last.url.should contain("/server/reboot/186260?reason=")
    end

    it "reason par défaut `beryl provisioning`" do
      stub = StubTransport.new
      stub.responses << {200, "true"}
      client = DediboxApi::Client.new(token: "t", transport: stub)
      client.servers.reboot(186260)
      stub.last.url.should contain("reason=beryl")
    end

    it "retourne false si Dedibox refuse le reboot (pas de reason valide)" do
      stub = StubTransport.new
      stub.responses << {200, "false"}
      client = DediboxApi::Client.new(token: "t", transport: stub)
      client.servers.reboot(186260).should be_false
    end
  end

  describe "#boot_normal" do
    it "POST /server/boot/normal/<id>" do
      stub = StubTransport.new
      stub.responses << {200, "true"}
      client = DediboxApi::Client.new(token: "t", transport: stub)
      client.servers.boot_normal(186260).should be_true
      stub.last.method.should eq("POST")
      stub.last.url.should end_with("/server/boot/normal/186260")
    end
  end

  describe "#reboot_to_disk" do
    it "enchaîne boot_normal + reboot(reason)" do
      stub = StubTransport.new
      stub.responses << {200, "true"} # boot_normal
      stub.responses << {200, "true"} # reboot
      client = DediboxApi::Client.new(token: "t", transport: stub)
      client.servers.reboot_to_disk(186260, reason: "post-install").should be_true
      # 2 appels HTTP : le 1er vers boot/normal, le 2e vers reboot
      stub.recorded.size.should eq(2)
      stub.recorded[0].url.should end_with("/server/boot/normal/186260")
      stub.recorded[1].url.should contain("/server/reboot/186260?reason=")
    end

    it "retourne false si boot_normal échoue (ne rebooote pas)" do
      stub = StubTransport.new
      stub.responses << {200, "false"} # boot_normal refusé
      client = DediboxApi::Client.new(token: "t", transport: stub)
      client.servers.reboot_to_disk(186260).should be_false
      # Un seul appel : boot_normal. Pas de reboot tentatif après refus.
      stub.recorded.size.should eq(1)
    end
  end
end

describe DediboxApi::Endpoints::Ip do
  it "distingue public / privé" do
    private_raw = JSON.parse(%({"address":"10.0.0.1","type":"private","reverse":null,"mac":"aa:bb"}))
    public_raw = JSON.parse(%({"address":"1.2.3.4","type":"public","reverse":"x.example.com","mac":"cc:dd"}))
    DediboxApi::Endpoints::Ip.new(private_raw).public?.should be_false
    DediboxApi::Endpoints::Ip.new(public_raw).public?.should be_true
    DediboxApi::Endpoints::Ip.new(public_raw).reverse.should eq("x.example.com")
    DediboxApi::Endpoints::Ip.new(private_raw).reverse.should be_nil
  end
end
