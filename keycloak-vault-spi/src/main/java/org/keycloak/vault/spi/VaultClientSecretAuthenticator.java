package org.keycloak.vault.spi;

import org.jboss.logging.Logger;
import org.keycloak.authentication.ClientAuthenticator;
import org.keycloak.authentication.ClientAuthenticatorFactory;
import org.keycloak.authentication.authenticators.client.ClientIdAndSecretAuthenticator;
import org.keycloak.models.ClientModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.provider.ProviderConfigProperty;

import java.util.Collections;
import java.util.List;
import java.util.Map;

/**
 * A client authenticator that uses Vault to verify client secrets.
 * This extends the default ClientIdAndSecretAuthenticator to replace the secret verification logic.
 */
public class VaultClientSecretAuthenticator extends ClientIdAndSecretAuthenticator implements ClientAuthenticator {
    private static final Logger logger = Logger.getLogger(VaultClientSecretAuthenticator.class);
    public static final String PROVIDER_ID = "vault-client-secret-authenticator";

    /**
     * Validate the client secret against the one stored in Vault
     */
    protected boolean validateClientCredentials(KeycloakSession session, RealmModel realm, ClientModel client, String secret) {
        if (secret == null) {
            logger.debug("No client secret provided");
            return false;
        }

        // Create the vault provider and adapter
        VaultClientSecretProviderConfig config = new VaultClientSecretProviderConfig(null);
        KeycloakClientSecretAdapter adapter = new KeycloakClientSecretAdapter(session, config);

        // Get client secret from Vault
        String vaultSecret = adapter.getClientSecret(client);

        if (vaultSecret == null) {
            logger.warnf("No Vault secret found for client '%s', falling back to standard authentication", 
                    client.getClientId());
            // Fall back to standard validation if no Vault secret exists
            return super.validateClientCredentials(session, realm, client, secret);
        }

        boolean result = vaultSecret.equals(secret);
        if (result) {
            logger.debugf("Successfully authenticated client '%s' using Vault-provided secret", client.getClientId());
        } else {
            logger.warnf("Failed to authenticate client '%s' with Vault-provided secret", client.getClientId());
        }
        return result;
    }

    /**
     * Factory for creating VaultClientSecretAuthenticator instances
     */
    public static class Factory implements ClientAuthenticatorFactory {

        @Override
        public ClientAuthenticator create(KeycloakSession session) {
            return new VaultClientSecretAuthenticator();
        }

        @Override
        public void init(org.keycloak.Config.Scope config) {
            // No initialization needed
        }

        @Override
        public void postInit(org.keycloak.models.KeycloakSessionFactory factory) {
            // No post-initialization needed
        }

        @Override
        public void close() {
            // No resources to close
        }

        @Override
        public String getId() {
            return PROVIDER_ID;
        }

        @Override
        public String getDisplayType() {
            return "Client ID and Secret with Vault Integration";
        }

        @Override
        public boolean isConfigurable() {
            return false;
        }

        @Override
        public List<ProviderConfigProperty> getConfigPropertiesPerClient() {
            return Collections.emptyList();
        }

        @Override
        public String getHelpText() {
            return "Clients authenticate with client ID and secret from HashiCorp Vault";
        }

        @Override
        public List<ProviderConfigProperty> getConfigProperties() {
            return Collections.emptyList();
        }
        
        @Override
        public Map<String, Object> getAdapterConfiguration(ClientModel client) {
            return Collections.emptyMap();
        }

        @Override
        public String getProtocol() {
            return "openid-connect";
        }
        
        @Override
        public List<String> getProtocolAuthenticatorMethods(String loginProtocol) {
            if ("openid-connect".equals(loginProtocol)) {
                return Collections.singletonList("client_secret");
            } else {
                return Collections.emptyList();
            }
        }
    }
} 