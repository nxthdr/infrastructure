# # Infrastructure
# resource "porkbun_dns_record" "core_A_record" {
#   domain   = "nxthdr.dev"
#   name     = "core.infra"
#   type     = "A"
#   content  = "163.172.213.99"
# }

# resource "porkbun_dns_record" "fra_A_record" {
#   domain   = "nxthdr.dev"
#   name     = "fra.infra"
#   type     = "A"
#   content  = "193.148.249.125"
# }

# resource "porkbun_dns_record" "ams_A_record" {
#   domain   = "nxthdr.dev"
#   name     = "ams.infra"
#   type     = "A"
#   content  = "193.148.248.249"
# }

# # DMZ
# resource "porkbun_dns_record" "proxy" {
#   domain   = "nxthdr.dev"
#   name     = "proxy"
#   type     = "AAAA"
#   content  = "2a06:de00:50:cafe:100::a"
# }

# # Services behind reverse proxy
# resource "porkbun_dns_record" "backends" {
#   domain   = "nxthdr.dev"
#   name     = "*"
#   type     = "AAAA"
#   content  = "2a06:de00:50:cafe:100::a"
# }
