path "secret/data/keycloak/keys/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/keycloak/keys/*" {
  capabilities = ["read", "list"]
} 