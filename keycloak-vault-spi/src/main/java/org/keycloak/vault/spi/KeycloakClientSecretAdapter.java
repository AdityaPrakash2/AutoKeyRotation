package org.keycloak.vault.spi;

import org.jboss.logging.Logger;
import org.keycloak.models.ClientModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;

/**
 * This class serves as an adapter between the Keycloak credential system and Vault.
 * It allows Keycloak to retrieve client secrets from Vault instead of using internally stored secrets.
 */
public class KeycloakClientSecretAdapter {
    private static final Logger logger = Logger.getLogger(KeycloakClientSecretAdapter.class);
    private final VaultClientSecretProvider vaultProvider;
    private final KeycloakSession session;

    public KeycloakClientSecretAdapter(KeycloakSession session, VaultClientSecretProviderConfig config) {
        this.session = session;
        this.vaultProvider = new VaultClientSecretProvider(session, config);
    }

    /**
     * Retrieves a client's secret from Vault
     * @param client The client
     * @return The client secret from Vault, or null if not found
     */
    public String getClientSecret(ClientModel client) {
        if (client == null) {
            logger.warn("Cannot get secret for null client");
            return null;
        }

        RealmModel realm = client.getRealm();
        String realmName = realm.getName();
        String clientId = client.getClientId();

        logger.debugf("Retrieving secret for client '%s' in realm '%s' from Vault", clientId, realmName);
        String secret = vaultProvider.getClientSecretFromVault(realmName, clientId);

        if (secret == null) {
            logger.warnf("No secret found in Vault for client '%s' in realm '%s', falling back to local secret", 
                    clientId, realmName);
            // Fallback to the stored secret if no Vault secret is available
            return client.getSecret();
        }

        logger.debugf("Successfully retrieved secret for client '%s' in realm '%s' from Vault", clientId, realmName);
        return secret;
    }
} 