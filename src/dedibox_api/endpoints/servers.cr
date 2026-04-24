require "json"

module DediboxApi
  module Endpoints
    # Endpoints `/server/*` de l'API Dedibox.
    #
    # Les serveurs Dedibox sont identifiés par un **entier** (`id`)
    # contrairement à OVH qui utilise un `serviceName` textuel.
    #
    # Pattern général (confirmé en live 24 avril 2026) :
    #   * `GET    /server/`                         → liste URIs
    #   * `GET    /server/{id}`                     → détail
    #   * `PUT    /server/{id}`                     → update (hostname…)
    #   * `GET    /server/rescue_images/{id}`       → images rescue dispo
    #   * `POST   /server/boot/rescue/{id}`         → prépare passage en rescue
    #                                                  (retourne credentials)
    #   * `POST   /server/reboot/{id}?reason=...`   → reboot bare metal
    #                                                  (reason obligatoire)
    #   * `POST   /server/boot/normal/{id}`         → retour boot disque
    #
    # Limitation connue : l'API Dedibox n'expose PAS d'endpoint public
    # pour modifier le reverse DNS d'une IP. L'opération se fait via la
    # console web (https://console.online.net → Serveur → IP failover /
    # Reverse DNS) ou via ticket support. Les tentatives
    # `POST /server/{id}/reverse`, `PUT /server/{id}/reverse`,
    # `POST /reverse/{ip}` retournent toutes « Unknown method ».
    class Servers
      # Image rescue par défaut utilisée par {#prepare_rescue} quand
      # l'appelant ne spécifie pas `image`. Debian 12 est le choix le
      # plus stable pour héberger un environnement de provisioning
      # (mfsBSD-in-QEMU, scripts shell, …) et reste disponible sur
      # toutes les offres Dedibox à fin 2026.
      #
      # La liste des images disponibles pour un serveur donné est
      # retournée par {#rescue_images}.
      DEFAULT_RESCUE_IMAGE = "debian-12_amd64"

      def initialize(@client : DediboxApi::Client)
      end

      # Liste des URIs des serveurs du compte.
      # Format retourné par Dedibox : `["/api/v1/server/186260", ...]`.
      # On les normalise en entiers `[186260, ...]` pour l'appelant.
      def list : Array(Int32)
        result = @client.call("GET", "/server/")
        return [] of Int32 unless result
        result.as_a.compact_map do |uri_any|
          uri = uri_any.as_s?
          next nil unless uri
          # extrait l'entier en fin de chemin
          uri.split('/').last.to_i?
        end
      end

      # Détail complet d'un serveur. Retourne la structure riche Dedibox :
      # `id`, `offer`, `hostname`, `os`, `power`, `boot_mode`, `ip[]`,
      # `location`, etc. Voir {Server} pour l'accès structuré.
      def info(id : Int32) : Server
        Server.new(@client.call("GET", "/server/#{id}").not_nil!)
      end

      # Met à jour les champs modifiables d'un serveur. Aujourd'hui
      # seul `hostname` (nom console Dedibox, visible dans le panel)
      # est couvert — l'API accepte aussi d'autres champs (`support`,
      # `anti_ddos`, `proactive_monitoring`) mais beryl n'en a pas
      # l'usage. Retourne `true` si l'update a été appliqué.
      #
      # Attention : ce hostname est celui AFFICHÉ dans la console
      # Dedibox. Le hostname système (uname -n) est géré côté OS et
      # n'est pas modifié par cet appel.
      def update_hostname(id : Int32, hostname : String) : Bool
        result = @client.call(
          "PUT", "/server/#{id}",
          body: {"hostname" => hostname},
        )
        result.try(&.as_bool?) || false
      end

      # Liste des images de rescue disponibles pour un serveur (slugs).
      # Exemple : `["ubuntu-22.04_amd64v2", "debian-12_amd64", "debian-10_amd64"]`.
      # Varie selon le type/offre de serveur.
      def rescue_images(id : Int32) : Array(String)
        result = @client.call("GET", "/server/rescue_images/#{id}")
        result.try(&.as_a.map(&.as_s)) || [] of String
      end

      # Prépare le passage en rescue. Positionne le `boot_mode` à
      # `rescue` côté Dedibox (visible dans `info(id).boot_mode`), le
      # reboot EFFECTIF doit être déclenché ensuite via {#reboot}.
      #
      # Dedibox injecte automatiquement toutes les clés SSH IAM du
      # compte (via {SshKeys#list}) dans le rescue — pas besoin de
      # passer de ssh_key_id.
      #
      # * `image` — slug d'une image renvoyée par {#rescue_images}
      #   (ex: `"debian-12_amd64"`, `"ubuntu-22.04_amd64v2"`). Défaut :
      #   {DEFAULT_RESCUE_IMAGE}.
      #
      # Retourne une struct {RescueCredentials} avec les identifiants
      # générés (login `sd-<id>`, password random, IP publique). Utile
      # même si on auth par clé — au moins pour les logs.
      def prepare_rescue(id : Int32, image : String = DEFAULT_RESCUE_IMAGE) : RescueCredentials
        result = @client.call(
          "POST", "/server/boot/rescue/#{id}",
          body: {"image" => image},
        ).not_nil!
        RescueCredentials.new(result)
      end

      # Déclenche un reboot bare metal. `reason` est obligatoire côté
      # API Dedibox : sans reason, l'endpoint retourne `false` sans
      # action. Avec reason, retourne `true` et le serveur redémarre.
      #
      # Après {#prepare_rescue}, ce reboot boote sur l'image rescue.
      # Après {#boot_normal}, il boote sur le disque.
      def reboot(id : Int32, reason : String = "beryl provisioning") : Bool
        result = @client.call(
          "POST", "/server/reboot/#{id}",
          query: {"reason" => reason},
        )
        result.try(&.as_bool?) || false
      end

      # Demande le retour au boot disque (post-rescue). Positionne
      # `boot_mode` à `normal` ; le prochain {#reboot} bootera sur le
      # disque système.
      def boot_normal(id : Int32) : Bool
        result = @client.call("POST", "/server/boot/normal/#{id}")
        result.try(&.as_bool?) || false
      end

      # Helper combo : bascule le serveur en boot disque ET le
      # reboote pour que le changement prenne effet. Équivalent
      # sémantique du `boot_from_disk` OVH (qui gère tout côté
      # API hébergeur en une seule opération).
      #
      # Contrairement à un `reboot` seul (qui laisse `boot_mode` à
      # `rescue` s'il y était), cette méthode est la seule façon
      # correcte de revenir sur disque via l'API Dedibox.
      #
      # Retourne `true` si les deux appels API ont été acceptés.
      # L'opérateur doit ensuite attendre le retour SSH côté OS
      # installé — l'API Dedibox ne propose pas de task async
      # pollable.
      def reboot_to_disk(id : Int32, reason : String = "beryl boot-disk") : Bool
        return false unless boot_normal(id)
        reboot(id, reason: reason)
      end
    end

    # Identifiants renvoyés par `prepare_rescue`. Dedibox génère un
    # password random + login `sd-<id>` pour chaque passage en rescue.
    # La clé SSH IAM reste le moyen privilégié de se connecter —
    # ces credentials servent surtout pour les logs et le fallback.
    struct RescueCredentials
      getter raw : JSON::Any

      def initialize(@raw : JSON::Any)
      end

      # Login du rescue, typiquement `sd-<id>` (ex: `sd-186260`).
      def login : String
        @raw["login"].as_s
      end

      def password : String
        @raw["password"].as_s
      end

      # IP publique sur laquelle le rescue répondra.
      def ip : String
        @raw["ip"].as_s
      end

      # "ssh" typiquement.
      def protocol : String
        @raw["protocol"]?.try(&.as_s?) || "ssh"
      end
    end

    # Wrapper structuré autour de la réponse JSON de `GET /server/{id}`.
    # Accès typé aux champs courants ; les détails plus exotiques
    # restent accessibles via `#raw` pour l'appelant qui veut creuser.
    struct Server
      getter raw : JSON::Any

      def initialize(@raw : JSON::Any)
      end

      def id : Int32
        @raw["id"].as_i
      end

      # Ex: "Start-9-M", "PRO-3-S", etc.
      def offer : String
        @raw["offer"].as_s
      end

      # Hostname défini côté console Dedibox (peut différer du hostname
      # OS installé).
      def hostname : String
        @raw["hostname"]?.try(&.as_s?) || ""
      end

      # Nom de l'OS installé selon Dedibox (peut être "custom installation"
      # si on a installé hors template Dedibox, cas typique beryl).
      def os_name : String
        @raw["os"]?.try(&.["name"]?).try(&.as_s?) || ""
      end

      # "ON" ou "OFF".
      def power : String
        @raw["power"]?.try(&.as_s?) || ""
      end

      # "normal" (boot disque) ou "rescue".
      def boot_mode : String
        @raw["boot_mode"]?.try(&.as_s?) || ""
      end

      # Toutes les IPs (publiques + privées) avec leur reverse et MAC.
      def ips : Array(Ip)
        arr = @raw["ip"]?.try(&.as_a?) || [] of JSON::Any
        arr.map { |x| Ip.new(x) }
      end

      # Première IP publique (pratique pour beryl qui cherche une IP
      # routable). `nil` si aucune (rare, mais possible).
      def public_ip : String?
        ips.find(&.public?).try(&.address)
      end

      # Reverse DNS associé à la première IP publique.
      def public_reverse : String?
        ips.find(&.public?).try(&.reverse)
      end
    end

    # Une IP associée à un serveur Dedibox.
    struct Ip
      getter raw : JSON::Any

      def initialize(@raw : JSON::Any)
      end

      def address : String
        @raw["address"].as_s
      end

      # "public" ou "private".
      def type : String
        @raw["type"]?.try(&.as_s?) || ""
      end

      def public? : Bool
        type == "public"
      end

      def reverse : String?
        @raw["reverse"]?.try(&.as_s?)
      end

      def mac : String?
        @raw["mac"]?.try(&.as_s?)
      end
    end
  end
end
