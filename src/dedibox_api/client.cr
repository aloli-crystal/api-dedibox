require "http/client"
require "json"
require "uri"

require "./errors"

module DediboxApi
  # Endpoint par défaut de l'API Dedibox (racine v1).
  DEFAULT_ENDPOINT = "https://api.online.net/api/v1"

  # Transport HTTP abstrait — permet d'injecter un double dans les tests.
  # Une implémentation doit retourner `{status, body}`. Le `Client` se
  # charge du décodage JSON et des exceptions.
  abstract class HttpTransport
    abstract def request(
      method : String,
      url : String,
      headers : HTTP::Headers,
      body : String,
    ) : {Int32, String}
  end

  # Transport par défaut, basé sur `HTTP::Client` de la stdlib.
  class DefaultHttpTransport < HttpTransport
    def request(method, url, headers, body) : {Int32, String}
      response = HTTP::Client.exec(
        method: method,
        url: url,
        headers: headers,
        body: body.empty? ? nil : body,
      )
      {response.status_code, response.body}
    end
  end

  # Client Dedibox / Online.net API v1.
  #
  # Auth par Bearer token (un jeton unique, généré depuis la console
  # https://console.online.net/fr/api/access). Contrairement à OVH, pas
  # de signature HMAC ni de consumer key à dériver — un seul token sert
  # pour toutes les requêtes.
  #
  # ```
  # client = DediboxApi::Client.new(token: ENV["DEDIBOX_TOKEN"])
  # info = client.servers.info(186260)
  # puts info.hostname
  # ```
  class Client
    getter token : String
    getter endpoint : String
    property transport : HttpTransport

    def initialize(
      @token : String,
      @endpoint : String = DEFAULT_ENDPOINT,
      @transport : HttpTransport = DefaultHttpTransport.new,
    )
    end

    # Effectue un appel API et retourne le corps parsé en JSON
    # (ou `nil` si vide).
    #
    # * `method` : `"GET"`, `"POST"`, `"PUT"`, `"DELETE"`
    # * `path`   : chemin relatif au endpoint (ex. `"/server/186260"`)
    # * `query`  : paramètres query string
    # * `body`   : objet JSON-sérialisable (ou `nil`)
    def call(
      method : String,
      path : String,
      query : Hash(String, String)? = nil,
      body = nil,
    ) : JSON::Any?
      url = build_url(path, query)
      body_str = serialize_body(body)
      headers = HTTP::Headers{
        "Authorization" => "Bearer #{@token}",
        "Accept"        => "application/json",
        "Content-Type"  => "application/json",
      }
      status, response_body = @transport.request(method, url, headers, body_str)
      handle_response(status, response_body, method, path)
    end

    private def build_url(path : String, query : Hash(String, String)?) : String
      full = @endpoint + (path.starts_with?("/") ? path : "/#{path}")
      if query && !query.empty?
        pairs = query.map { |k, v| "#{URI.encode_path_segment(k)}=#{URI.encode_path_segment(v)}" }
        full + "?" + pairs.join("&")
      else
        full
      end
    end

    private def serialize_body(body) : String
      case body
      when Nil
        ""
      when String
        body
      else
        body.to_json
      end
    end

    private def handle_response(status : Int32, body : String, method : String, path : String) : JSON::Any?
      case status
      when 200..299
        return nil if body.empty?
        JSON.parse(body)
      when 401, 403
        raise AuthenticationError.new(format_error(status, body, method, path), status, extract_error_code(body))
      when 404
        raise NotFound.new(format_error(status, body, method, path), status, extract_error_code(body))
      when 429
        retry_after = extract_retry_after(body)
        raise RateLimited.new(format_error(status, body, method, path), retry_after)
      else
        raise ApiError.new(format_error(status, body, method, path), status, extract_error_code(body))
      end
    end

    private def format_error(status : Int32, body : String, method : String, path : String) : String
      "Dedibox API #{method} #{path} → HTTP #{status} : #{body.empty? ? "(corps vide)" : body}"
    end

    # Le format d'erreur Dedibox est `{"error":"Unknown method","code":3}`.
    # On extrait le code entier si présent.
    private def extract_error_code(body : String) : Int32?
      parsed = JSON.parse(body)
      parsed["code"]?.try(&.as_i?)
    rescue
      nil
    end

    private def extract_retry_after(body : String) : Int32?
      parsed = JSON.parse(body)
      parsed["retryAfter"]?.try(&.as_i?) || parsed["retry_after"]?.try(&.as_i?)
    rescue
      nil
    end

    # Accès paresseux aux endpoints (un seul objet par Client).
    def servers : Endpoints::Servers
      @servers ||= Endpoints::Servers.new(self)
    end

    def ssh_keys : Endpoints::SshKeys
      @ssh_keys ||= Endpoints::SshKeys.new(self)
    end

    def user : Endpoints::User
      @user ||= Endpoints::User.new(self)
    end

    @servers : Endpoints::Servers?
    @ssh_keys : Endpoints::SshKeys?
    @user : Endpoints::User?
  end
end
