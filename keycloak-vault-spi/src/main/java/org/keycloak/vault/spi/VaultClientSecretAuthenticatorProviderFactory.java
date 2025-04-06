package org.keycloak.vault.spi;

import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.jboss.logging.Logger;
import org.keycloak.Config;
import org.keycloak.authentication.ClientAuthenticator;
import org.keycloak.authentication.ClientAuthenticatorFactory;
import org.keycloak.authentication.authenticators.client.ClientIdAndSecretAuthenticator;
import org.keycloak.models.AuthenticationExecutionModel;
import org.keycloak.models.ClientModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;
import org.keycloak.models.RealmModel;
import org.keycloak.provider.ProviderConfigProperty;

/**
 * This factory creates a client secret authenticator that uses Vault integration.
 */
public class VaultClientSecretAuthenticatorProviderFactory implements ClientAuthenticatorFactory {
    private static final Logger logger = Logger.getLogger(VaultClientSecretAuthenticatorProviderFactory.class);
    public static final String PROVIDER_ID = "client-secret-vault";

    @Override
    public ClientAuthenticator create(KeycloakSession session) {
        return new VaultAwareClientSecretAuthenticator(session);
    }

    @Override
    public void init(Config.Scope config) {
        logger.info("Initializing Vault Client Secret Authenticator Provider");
    }

    @Override
    public void postInit(KeycloakSessionFactory factory) {
        logger.info("Vault Client Secret Authenticator Provider initialized");
    }

    @Override
    public void close() {
        logger.info("Closing Vault Client Secret Authenticator Provider");
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
    public String getHelpText() {
        return "Clients authenticate with client ID and secret from HashiCorp Vault";
    }

    @Override
    public boolean isConfigurable() {
        return false;
    }

    @Override
    public List<ProviderConfigProperty> getConfigProperties() {
        return Collections.emptyList();
    }

    @Override
    public Set<String> getProtocolAuthenticatorMethods(String loginProtocol) {
        return Collections.singleton("client_secret");
    }

    @Override
    public List<ProviderConfigProperty> getConfigPropertiesPerClient() {
        return Collections.emptyList();
    }

    @Override
    public Map<String, Object> getAdapterConfiguration(ClientModel client) {
        return new HashMap<>();
    }

    /**
     * The actual authenticator that checks client secrets against Vault.
     */
    private static class VaultAwareClientSecretAuthenticator extends ClientIdAndSecretAuthenticator {
        private final KeycloakSession session;
        private final Logger logger = Logger.getLogger(VaultAwareClientSecretAuthenticator.class);

        public VaultAwareClientSecretAuthenticator(KeycloakSession session) {
            this.session = session;
        }

        @Override
        public boolean authenticateClient(KeycloakSession session, RealmModel realm, ClientModel client, Map<String, String> credentials) {
            // Get the secret from credentials
            String secret = credentials.get("secret");
            if (secret == null) {
                logger.debug("No client secret provided");
                return false;
            }

            // Create the vault provider
            VaultClientSecretProviderConfig config = new VaultClientSecretProviderConfig(null);
            VaultClientSecretProvider vaultProvider = new VaultClientSecretProvider(session, config);

            // Check if this client is configured to use Vault
            if (vaultProvider.shouldUseVaultForClient(client)) {
                logger.debugf("Client '%s' is configured to use Vault for secret verification", client.getClientId());
                
                // Verify with Vault
                boolean result = vaultProvider.verifyClientSecret(client, secret);
                
                // If successful, we're done
                if (result) {
                    logger.debugf("Successfully authenticated client '%s' using Vault-provided secret", client.getClientId());
                    return true;
                }
                
                // If verification fails and we want to fall back to the local secret
                logger.warnf("Vault verification failed for client '%s', falling back to local secret", client.getClientId());
            }

            // Fall back to standard validation
            return super.authenticateClient(session, realm, client, credentials);
        }
    }
} 