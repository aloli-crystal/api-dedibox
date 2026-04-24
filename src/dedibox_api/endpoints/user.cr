require "json"

module DediboxApi
  module Endpoints
    # Endpoint `/user` — informations sur le compte Dedibox authentifié.
    # Utile pour `beryl init` (confirmer à quel compte appartient le
    # token) et pour les diagnostics « est-ce bien ma clé qui est
    # configurée ? ».
    class User
      def initialize(@client : DediboxApi::Client)
      end

      # Détail du compte courant (celui du token utilisé).
      def info : UserInfo
        UserInfo.new(@client.call("GET", "/user").not_nil!)
      end
    end

    # Détail d'un compte Dedibox.
    struct UserInfo
      getter raw : JSON::Any

      def initialize(@raw : JSON::Any)
      end

      def id : Int32
        @raw["id"].as_i
      end

      def login : String
        @raw["login"].as_s
      end

      def email : String
        @raw["email"]?.try(&.as_s?) || ""
      end

      def first_name : String
        @raw["first_name"]?.try(&.as_s?) || ""
      end

      def last_name : String
        @raw["last_name"]?.try(&.as_s?) || ""
      end

      def company : String
        @raw["company"]?.try(&.as_s?) || ""
      end

      def display_name : String
        [first_name, last_name].reject(&.empty?).join(" ")
      end
    end
  end
end
