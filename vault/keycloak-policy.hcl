path "secret/data/keycloak/client-secrets/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/keycloak/client-secrets/*" {
  capabilities = ["read", "list"]
} 