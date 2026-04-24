require "./dedibox_api/version"
require "./dedibox_api/errors"
require "./dedibox_api/endpoints/servers"
require "./dedibox_api/endpoints/ssh_keys"
require "./dedibox_api/endpoints/user"
require "./dedibox_api/client"

# DediboxApi — client Crystal pur (stdlib uniquement) pour l'API
# Dedibox / Online.net v1.
#
# Auth par Bearer token simple (un jeton unique, généré depuis la
# console https://console.online.net/fr/api/access). Couvre le strict
# nécessaire au provisioning de serveurs dédiés Dedibox :
#
# * `client.servers`
#   * `list`               — liste les IDs des serveurs du compte
#   * `info(id)`           — détail serveur (hostname, IPs, boot mode…)
#   * `rescue_images(id)`  — liste des slugs images rescue disponibles
#   * `prepare_rescue(id, image)` — sélectionne l'image rescue à booter
#   * `reboot(id)`         — déclenche un reboot bare metal (applique le rescue)
#   * `boot_normal(id)`    — demande le retour boot disque (post-bootstrap)
#
# * `client.ssh_keys`
#   * `list`, `info(id)`, `create(description, key)`, `delete(id)`
#
# Flux typique pour un bootstrap Aloli :
#
# ```
# require "dedibox-api"
#
# client = DediboxApi::Client.new(token: ENV["DEDIBOX_TOKEN"])
# info = client.servers.info(186260)
# puts info.public_ip # => "195.154.254.221"
#
# images = client.servers.rescue_images(186260)
# client.servers.prepare_rescue(186260, "debian-12_amd64")
# client.servers.reboot(186260)
# # ... attendre retour SSH en rescue, lancer mfsBSD-in-QEMU …
# client.servers.boot_normal(186260)
# client.servers.reboot(186260)
# ```
module DediboxApi
end
