path "secret/data/keycloak/client-secrets/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/keycloak/client-secrets/*" {
  capabilities = ["read", "list"]
}

# Add paths for the kv engine we're actually using
path "kv/data/keycloak/clients/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "kv/metadata/keycloak/clients/*" {
  capabilities = ["read", "list"]
} 