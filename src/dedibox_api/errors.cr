module DediboxApi
  # Erreur générique de l'API Dedibox. Les sous-classes précisent le
  # type (auth, not found, rate limit, etc.) pour que l'appelant puisse
  # réagir différemment.
  class ApiError < Exception
    getter status_code : Int32?
    getter error_code : Int32?

    def initialize(message : String, @status_code : Int32? = nil, @error_code : Int32? = nil)
      super(message)
    end
  end

  # HTTP 401/403 — token invalide, révoqué ou scope insuffisant.
  class AuthenticationError < ApiError
  end

  # HTTP 404 — ressource inexistante (serveur, clé SSH, image…).
  class NotFound < ApiError
  end

  # HTTP 429 — throttling Dedibox. `retry_after` si l'API le fournit
  # dans le corps de la réponse, `nil` sinon.
  class RateLimited < ApiError
    getter retry_after : Int32?

    def initialize(message : String, @retry_after : Int32? = nil)
      super(message)
    end
  end
end
