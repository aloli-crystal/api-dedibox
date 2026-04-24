require "json"

module DediboxApi
  module Endpoints
    # Endpoints `/user/key/ssh` de l'API Dedibox.
    #
    # Les clés SSH IAM sont **globales au compte** (pas attachées à un
    # serveur précis). Lors d'un passage en rescue, Dedibox injecte
    # automatiquement toutes les clés listées ici dans le rescue,
    # accessibles à l'utilisateur `root`.
    #
    # Si la liste est vide, le rescue est joignable uniquement via un
    # mot de passe généré et renvoyé dans la réponse de `prepare_rescue`.
    class SshKeys
      def initialize(@client : DediboxApi::Client)
      end

      # Liste des clés SSH IAM du compte. Dedibox renvoie une liste
      # d'URIs `["/api/v1/user/key/ssh/42", ...]` — on la normalise en
      # structs {SshKey} en récupérant le détail de chaque clé (n+1
      # requêtes mais la liste est petite et stable).
      def list : Array(SshKey)
        result = @client.call("GET", "/user/key/ssh")
        return [] of SshKey unless result
        uris = result.as_a.compact_map(&.as_s?)
        uris.compact_map do |uri|
          id = uri.split('/').last.to_i?
          next nil unless id
          info(id)
        end
      end

      # Détail d'une clé SSH par son ID.
      def info(id : Int32) : SshKey
        SshKey.new(@client.call("GET", "/user/key/ssh/#{id}").not_nil!)
      end

      # Ajoute une clé SSH au compte. `key` doit être la ligne complète
      # format OpenSSH (`ssh-ed25519 AAAA... commentaire`).
      def create(description : String, key : String) : JSON::Any
        @client.call(
          "POST", "/user/key/ssh",
          body: {"description" => description, "key" => key},
        ).not_nil!
      end

      # Supprime une clé SSH du compte.
      def delete(id : Int32) : Nil
        @client.call("DELETE", "/user/key/ssh/#{id}")
      end
    end

    # Clé SSH IAM Dedibox.
    struct SshKey
      getter raw : JSON::Any

      def initialize(@raw : JSON::Any)
      end

      def id : Int32
        @raw["id"].as_i
      end

      # Description humaine posée à la création (ex: "philippe@aloli").
      def description : String
        @raw["description"]?.try(&.as_s?) || ""
      end

      # Clé publique complète (format OpenSSH).
      def key : String
        @raw["key"]?.try(&.as_s?) || ""
      end

      # Fingerprint éventuel (Dedibox le calcule côté serveur).
      def fingerprint : String?
        @raw["fingerprint"]?.try(&.as_s?)
      end
    end
  end
end
