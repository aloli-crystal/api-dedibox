require "spec"
require "../src/dedibox_api"

# Transport HTTP stubbé : renvoie un `{status, body}` prédéfini, et
# enregistre chaque requête reçue (méthode, URL, headers, body) pour
# vérifications dans les tests.
class StubTransport < DediboxApi::HttpTransport
  class Recorded
    getter method : String
    getter url : String
    getter headers : HTTP::Headers
    getter body : String

    def initialize(@method, @url, @headers, @body)
    end
  end

  getter recorded : Array(Recorded) = [] of Recorded
  property responses : Array({Int32, String}) = [] of {Int32, String}

  def request(method, url, headers, body) : {Int32, String}
    @recorded << Recorded.new(method, url, headers.dup, body)
    response = @responses.shift? || {200, ""}
    response
  end

  def last : Recorded
    @recorded.last
  end
end
