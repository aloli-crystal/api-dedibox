# Cycle complet de provisioning d'un serveur Dedibox via l'API :
#
#   1. Vérifie le compte (user.info) et la présence d'au moins une
#      clé SSH IAM (sinon le rescue ne sera accessible que par
#      password).
#   2. Détaille le serveur cible (info).
#   3. Liste les images rescue disponibles et choisit `debian-12_amd64`.
#   4. prepare_rescue + reboot.
#   5. Poll l'état (`GET /server/{id}.boot_mode` = "rescue" attendu).
#   6. (simulation de bootstrap — pas fait ici, c'est le job de beryl)
#   7. boot_normal + reboot.
#
# **Garde-fou** : lance UNIQUEMENT si `DEDIBOX_CONFIRM=yes` est dans
# l'environnement. Par défaut, affiche le plan et s'arrête. Évite tout
# déclenchement accidentel qui rebooterait un serveur de prod.
#
# Usage :
#   DEDIBOX_TOKEN=... DEDIBOX_SERVER_ID=186260 crystal run examples/provision_freebsd.cr
#   DEDIBOX_TOKEN=... DEDIBOX_SERVER_ID=186260 DEDIBOX_CONFIRM=yes crystal run examples/provision_freebsd.cr

require "../src/dedibox_api"

token = ENV["DEDIBOX_TOKEN"]? || begin
  STDERR.puts "ERREUR : variable DEDIBOX_TOKEN non définie."
  STDERR.puts "  Générer un token depuis https://console.online.net/fr/api/access"
  exit 1
end

server_id = (ENV["DEDIBOX_SERVER_ID"]? || begin
  STDERR.puts "ERREUR : variable DEDIBOX_SERVER_ID non définie."
  exit 1
end).to_i

confirm = ENV["DEDIBOX_CONFIRM"]? == "yes"
image = ENV["DEDIBOX_RESCUE_IMAGE"]? || "debian-12_amd64"

client = DediboxApi::Client.new(token: token)

puts "=== Compte courant ==="
me = client.user.info
puts "  #{me.display_name} (#{me.login}, #{me.company})"
puts

puts "=== Clés SSH IAM ==="
keys = client.ssh_keys.list
if keys.empty?
  STDERR.puts "AVERTISSEMENT : aucune clé SSH IAM. Le rescue sera"
  STDERR.puts "accessible UNIQUEMENT par password. Ajouter une clé :"
  STDERR.puts "  client.ssh_keys.create(\"laptop\", \"ssh-ed25519 …\")"
else
  keys.each { |k| puts "  [#{k.id}] #{k.description}" }
end
puts

puts "=== Serveur #{server_id} ==="
info = client.servers.info(server_id)
puts "  offer       : #{info.offer}"
puts "  hostname    : #{info.hostname}"
puts "  power       : #{info.power}"
puts "  boot_mode   : #{info.boot_mode}"
puts "  public_ip   : #{info.public_ip}"
puts "  reverse     : #{info.public_reverse}"
puts

puts "=== Images rescue disponibles ==="
client.servers.rescue_images(server_id).each { |i| puts "  - #{i}" }
puts

unless confirm
  puts "=== DRY-RUN (DEDIBOX_CONFIRM ≠ yes) ==="
  puts "Plan prévu :"
  puts "  1. prepare_rescue(#{server_id}, #{image.inspect})"
  puts "  2. reboot(#{server_id}, reason: \"provision dedibox-api example\")"
  puts "  3. [simulation bootstrap — non couvert]"
  puts "  4. boot_normal(#{server_id})"
  puts "  5. reboot(#{server_id}, reason: \"first boot on disk\")"
  puts
  puts "Pour exécuter pour de vrai : DEDIBOX_CONFIRM=yes …"
  exit 0
end

puts "=== 1/5 prepare_rescue (#{image}) ==="
creds = client.servers.prepare_rescue(server_id, image)
puts "  login    : #{creds.login}"
puts "  password : #{creds.password}"
puts "  protocol : #{creds.protocol}"
puts "  ip       : #{creds.ip}"
puts

puts "=== 2/5 reboot vers rescue ==="
ok = client.servers.reboot(server_id, reason: "provision dedibox-api example")
if ok
  puts "  reboot déclenché, attendre ~2 min le retour SSH sur #{creds.ip}"
else
  STDERR.puts "  ÉCHEC reboot (l'API a refusé)"
  exit 2
end
puts

puts "=== 3/5 (simulation bootstrap FreeBSD hors périmètre) ==="
puts "  Dans un flow beryl complet, c'est ici que mfsBSD-in-QEMU + bsdinstall"
puts "  tournent depuis le rescue Debian."
puts

puts "=== 4/5 boot_normal ==="
if client.servers.boot_normal(server_id)
  puts "  mode boot disque armé pour le prochain reboot"
else
  STDERR.puts "  ÉCHEC boot_normal"
  exit 3
end
puts

puts "=== 5/5 reboot vers disque ==="
if client.servers.reboot(server_id, reason: "first boot on disk")
  puts "  reboot déclenché, attendre le retour SSH sur le FreeBSD installé"
else
  STDERR.puts "  ÉCHEC reboot"
  exit 4
end
